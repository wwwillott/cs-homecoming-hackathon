from typing import cast
from uuid import uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient

from tests.test_database_api import FakeNetworkProvider, database_client


def _headers() -> dict[str, str]:
    return {"X-User-Id": str(uuid4())}


def _profiled_person(
    client: TestClient,
    headers: dict[str, str],
    name: str,
    interest: str,
) -> dict:
    person = client.post(
        "/api/people",
        headers=headers,
        json={"name": name, "interests": [interest]},
    )
    assert person.status_code == 201
    conversation = client.post(
        "/api/conversations",
        headers=headers,
        json={
            "person_id": person.json()["id"],
            "transcript": f"I enjoy {interest}. SECRET_TRANSCRIPT_PHRASE for {name}.",
        },
    )
    assert conversation.status_code == 201
    approved = client.post(
        f"/api/suggestions/{conversation.json()['suggestion_id']}/approve",
        headers=headers,
        json={"profile": conversation.json()["summary"]["profile_suggestion"]},
    )
    assert approved.status_code == 200
    return person.json()


def test_export_import_remaps_ids_and_omits_transcripts() -> None:
    sharer = _headers()
    receiver = _headers()

    with database_client() as client:
        cast(FastAPI, client.app).state.summary_provider = FakeNetworkProvider()
        registered = client.post(
            "/api/auth/register",
            json={"username": "maya", "password": "secret"},
        )
        assert registered.status_code == 201
        sharer = {"X-User-Id": registered.json()["user_id"]}

        maya = _profiled_person(client, sharer, "Maya", "Robotics")
        trees = client.get("/api/network-trees", headers=sharer)
        assert trees.status_code == 200
        primary = next(tree for tree in trees.json() if tree["is_primary"])

        exported = client.post(f"/api/network-trees/{primary['id']}/export", headers=sharer)
        assert exported.status_code == 201
        token = exported.json()["share_token"]
        assert len(token) == 6

        imported = client.post(
            "/api/network-trees/import",
            headers=receiver,
            json={"share_token": token},
        )
        assert imported.status_code == 201
        attached = imported.json()
        assert attached["is_read_only"] is True
        assert attached["is_primary"] is False
        assert attached["attributed_username"] == "maya"
        assert attached["label"] == "maya's network"

        copied = client.get(f"/api/people?tree_id={attached['id']}", headers=receiver)
        assert copied.status_code == 200
        copied_maya = next(person for person in copied.json() if person["name"] == "Maya")
        assert copied_maya["id"] != maya["id"]
        assert copied_maya["interests"] == ["Robotics"]
        assert copied_maya["network_tree_id"] == attached["id"]

        primary_people = client.get("/api/people", headers=receiver)
        assert primary_people.json() == []

        forbidden = client.patch(
            f"/api/people/{copied_maya['id']}",
            headers=receiver,
            json={"name": "Maya Edited"},
        )
        assert forbidden.status_code == 403

        asked = client.post(
            "/api/network/ask",
            headers=receiver,
            json={"question": "Who works in robotics?", "tree_ids": [attached["id"]]},
        )
        assert asked.status_code == 200
        citations = asked.json()["citations"]
        assert citations
        assert citations[0]["person_name"] == "Maya"
        assert all("SECRET_TRANSCRIPT_PHRASE" not in item["excerpt"] for item in citations)

        isolated = client.post(
            "/api/network/ask",
            headers=receiver,
            json={"question": "Who works in robotics?"},
        )
        assert isolated.status_code == 200
        assert isolated.json()["citations"] == []

        reused = client.post(
            "/api/network-trees/import",
            headers=receiver,
            json={"share_token": token},
        )
        assert reused.status_code == 410


def test_tree_isolation_and_cross_tree_introductions() -> None:
    sharer = _headers()
    receiver = _headers()

    with database_client() as client:
        cast(FastAPI, client.app).state.summary_provider = FakeNetworkProvider()
        maya = _profiled_person(client, sharer, "Maya", "Robotics")
        leo = _profiled_person(client, sharer, "Leo", "Robotics")
        alex = _profiled_person(client, sharer, "Alex", "Robotics")
        connected = client.post(
            "/api/connections",
            headers=sharer,
            json={"person_a_id": maya["id"], "person_b_id": leo["id"]},
        )
        assert connected.status_code == 201

        same_tree = client.get("/api/network/introduction-suggestions", headers=sharer)
        assert same_tree.status_code == 200
        pairs = {
            frozenset((item["person_a_name"], item["person_b_name"])) for item in same_tree.json()
        }
        assert frozenset({"Maya", "Leo"}) not in pairs
        assert frozenset({"Maya", "Alex"}) in pairs

        trees = client.get("/api/network-trees", headers=sharer).json()
        primary = next(tree for tree in trees if tree["is_primary"])
        token = client.post(
            f"/api/network-trees/{primary['id']}/export",
            headers=sharer,
        ).json()["share_token"]
        attached = client.post(
            "/api/network-trees/import",
            headers=receiver,
            json={"share_token": token},
        ).json()

        priya = _profiled_person(client, receiver, "Priya", "Robotics")
        intros = client.get(
            "/api/network/introduction-suggestions",
            headers=receiver,
            params={"mode": "cross_tree", "tree_id": attached["id"]},
        )
        assert intros.status_code == 200
        names = {
            frozenset((item["person_a_name"], item["person_b_name"])) for item in intros.json()
        }
        assert frozenset({"Priya", "Maya"}) in names
        assert frozenset({"Priya", "Leo"}) in names
        assert frozenset({"Maya", "Leo"}) not in names
        assert all(item["person_a_name"] == "Priya" or item["person_b_name"] == "Priya" for item in intros.json())

        other = client.get("/api/people", headers=sharer)
        assert {person["name"] for person in other.json()} == {"Maya", "Leo", "Alex"}
        assert priya["id"] not in {person["id"] for person in other.json()}
