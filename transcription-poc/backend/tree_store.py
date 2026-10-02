from __future__ import annotations

import hashlib
import secrets
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database.models import (
    Connection,
    ContactMethod,
    KnowledgeChunk,
    NetworkSnapshot,
    NetworkTree,
    Organization,
    Person,
    PersonNote,
    PersonOrganization,
    PersonTopic,
    TopicKind,
)
SHARE_TOKEN_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
SNAPSHOT_TTL = timedelta(hours=24)


class EmbeddingProvider(Protocol):
    embedding_model: str

    async def embed(self, text: str, *, query: bool = False) -> list[float]: ...


async def ensure_primary_tree(session: AsyncSession, user_id: UUID) -> NetworkTree:
    tree = await session.scalar(
        select(NetworkTree).where(
            NetworkTree.owner_user_id == user_id,
            NetworkTree.is_primary.is_(True),
        )
    )
    if tree is not None:
        return tree
    tree = NetworkTree(
        owner_user_id=user_id,
        attributed_user_id=user_id,
        label="My network",
        is_primary=True,
        is_read_only=False,
    )
    session.add(tree)
    await session.flush()
    return tree


async def owned_tree(
    session: AsyncSession, user_id: UUID, tree_id: UUID
) -> NetworkTree | None:
    return await session.scalar(
        select(NetworkTree).where(
            NetworkTree.id == tree_id,
            NetworkTree.owner_user_id == user_id,
        )
    )


def _json_safe(value: Any) -> Any:
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, datetime):
        return value.isoformat()
    return value


def _embedding_list(value: Any) -> list[float] | None:
    if value is None:
        return None
    return [float(item) for item in list(value)]


def profile_text(
    person: Person,
    topics: list[PersonTopic],
    notes: list[PersonNote],
    organizations: list[tuple[Organization, str | None]],
) -> str:
    parts = [f"Name: {person.name}"]
    if person.how_met:
        parts.append(f"How we met: {person.how_met}")
    if person.where_met:
        parts.append(f"Where we met: {person.where_met}")
    for organization, role in organizations:
        label = f"{organization.name}" + (f" ({role})" if role else "")
        parts.append(f"Organization: {label}")
    for topic in topics:
        parts.append(f"{topic.kind.value.title()}: {topic.topic}")
    for note in notes:
        if note.general_note:
            parts.append(f"Note: {note.general_note}")
        if note.next_steps:
            parts.append(f"Next steps: {note.next_steps}")
        if note.how_to_serve:
            parts.append(f"How to help: {note.how_to_serve}")
    return "\n".join(parts)


async def serialize_tree(session: AsyncSession, tree: NetworkTree) -> dict[str, Any]:
    people = (
        await session.scalars(select(Person).where(Person.network_tree_id == tree.id))
    ).all()
    person_ids = [person.id for person in people]
    contacts = (
        await session.scalars(
            select(ContactMethod).where(ContactMethod.person_id.in_(person_ids))
        )
    ).all() if person_ids else []
    topics = (
        await session.scalars(select(PersonTopic).where(PersonTopic.person_id.in_(person_ids)))
    ).all() if person_ids else []
    notes = (
        await session.scalars(select(PersonNote).where(PersonNote.person_id.in_(person_ids)))
    ).all() if person_ids else []
    org_links = (
        await session.execute(
            select(Organization, PersonOrganization)
            .join(PersonOrganization, PersonOrganization.organization_id == Organization.id)
            .where(PersonOrganization.person_id.in_(person_ids))
        )
    ).all() if person_ids else []
    chunks = (
        await session.scalars(
            select(KnowledgeChunk).where(
                KnowledgeChunk.network_tree_id == tree.id,
                KnowledgeChunk.kind == "profile",
            )
        )
    ).all()
    connections = (
        await session.scalars(
            select(Connection).where(Connection.network_tree_id == tree.id)
        )
    ).all()

    contacts_by_person: dict[UUID, list[ContactMethod]] = {}
    for contact in contacts:
        contacts_by_person.setdefault(contact.person_id, []).append(contact)
    topics_by_person: dict[UUID, list[PersonTopic]] = {}
    for topic in topics:
        topics_by_person.setdefault(topic.person_id, []).append(topic)
    notes_by_person: dict[UUID, list[PersonNote]] = {}
    for note in notes:
        notes_by_person.setdefault(note.person_id, []).append(note)
    orgs_by_person: dict[UUID, list[tuple[Organization, str | None]]] = {}
    for organization, link in org_links:
        orgs_by_person.setdefault(link.person_id, []).append((organization, link.role))
    embedding_by_person = {chunk.person_id: chunk for chunk in chunks if chunk.person_id}

    self_name = next((person.name for person in people if person.is_self), None)
    people_payload = []
    for person in people:
        person_topics = topics_by_person.get(person.id, [])
        person_notes = notes_by_person.get(person.id, [])
        person_orgs = orgs_by_person.get(person.id, [])
        chunk = embedding_by_person.get(person.id)
        people_payload.append(
            {
                "id": str(person.id),
                "name": person.name,
                "alpha_score": float(person.alpha_score) if person.alpha_score is not None else None,
                "is_self": person.is_self,
                "how_met": person.how_met,
                "where_met": person.where_met,
                "met_at": _json_safe(person.met_at),
                "contact_methods": [
                    {
                        "kind": contact.kind,
                        "value": contact.value,
                        "label": contact.label,
                        "is_primary": contact.is_primary,
                    }
                    for contact in contacts_by_person.get(person.id, [])
                ],
                "organizations": [
                    {
                        "name": organization.name,
                        "kind": organization.kind,
                        "role": role,
                    }
                    for organization, role in person_orgs
                ],
                "goals": [
                    topic.topic for topic in person_topics if topic.kind == TopicKind.GOAL
                ],
                "interests": [
                    topic.topic for topic in person_topics if topic.kind == TopicKind.INTEREST
                ],
                "notes": [
                    {
                        "general_note": note.general_note,
                        "next_steps": note.next_steps,
                        "how_to_serve": note.how_to_serve,
                    }
                    for note in person_notes
                ],
                "profile_embedding": _embedding_list(chunk.embedding) if chunk else None,
                "profile_content": chunk.content
                if chunk
                else profile_text(person, person_topics, person_notes, person_orgs),
            }
        )

    return {
        "version": 1,
        "source_user_id": str(tree.owner_user_id),
        "source_tree_id": str(tree.id),
        "label": tree.label,
        "source_display_name": self_name or tree.label,
        "people": people_payload,
        "connections": [
            {
                "person_a_id": str(connection.person_a_id),
                "person_b_id": str(connection.person_b_id),
                "label": connection.label,
                "context": connection.context,
            }
            for connection in connections
        ],
    }


async def unique_share_token(session: AsyncSession) -> str:
    for _ in range(12):
        token = "".join(secrets.choice(SHARE_TOKEN_ALPHABET) for _ in range(6))
        existing = await session.scalar(
            select(NetworkSnapshot.id).where(NetworkSnapshot.share_token == token)
        )
        if existing is None:
            return token
    raise RuntimeError("Could not allocate a unique share token.")


async def create_snapshot(
    session: AsyncSession, tree: NetworkTree
) -> NetworkSnapshot:
    payload = await serialize_tree(session, tree)
    snapshot = NetworkSnapshot(
        source_user_id=tree.owner_user_id,
        source_tree_id=tree.id,
        payload_json=payload,
        share_token=await unique_share_token(session),
        expires_at=datetime.now(UTC) + SNAPSHOT_TTL,
    )
    session.add(snapshot)
    await session.flush()
    return snapshot


async def import_snapshot(
    session: AsyncSession,
    receiver_user_id: UUID,
    snapshot: NetworkSnapshot,
    provider: EmbeddingProvider | None,
) -> NetworkTree:
    payload = snapshot.payload_json
    display_name = str(payload.get("source_display_name") or "Shared network")
    tree = NetworkTree(
        owner_user_id=receiver_user_id,
        attributed_user_id=UUID(str(payload["source_user_id"])),
        label=f"{display_name}'s network",
        is_primary=False,
        is_read_only=True,
        source_snapshot_id=snapshot.id,
    )
    session.add(tree)
    await session.flush()

    id_map: dict[str, UUID] = {}
    for person_payload in payload.get("people", []):
        old_id = str(person_payload["id"])
        person = Person(
            id=uuid4(),
            owner_user_id=receiver_user_id,
            network_tree_id=tree.id,
            name=person_payload["name"],
            alpha_score=person_payload.get("alpha_score"),
            is_self=bool(person_payload.get("is_self")),
            how_met=person_payload.get("how_met"),
            where_met=person_payload.get("where_met"),
            met_at=_parse_datetime(person_payload.get("met_at")),
        )
        session.add(person)
        await session.flush()
        id_map[old_id] = person.id
        for contact in person_payload.get("contact_methods", []):
            session.add(
                ContactMethod(
                    person_id=person.id,
                    kind=contact["kind"],
                    value=contact["value"],
                    label=contact.get("label"),
                    is_primary=bool(contact.get("is_primary")),
                )
            )
        for topic in person_payload.get("goals", []):
            session.add(PersonTopic(person_id=person.id, kind=TopicKind.GOAL, topic=topic))
        for topic in person_payload.get("interests", []):
            session.add(
                PersonTopic(person_id=person.id, kind=TopicKind.INTEREST, topic=topic)
            )
        for note in person_payload.get("notes", []):
            if note.get("general_note") or note.get("next_steps") or note.get("how_to_serve"):
                session.add(
                    PersonNote(
                        person_id=person.id,
                        general_note=note.get("general_note"),
                        next_steps=note.get("next_steps"),
                        how_to_serve=note.get("how_to_serve"),
                    )
                )
        for organization_payload in person_payload.get("organizations", []):
            organization = await session.scalar(
                select(Organization).where(
                    Organization.network_tree_id == tree.id,
                    Organization.name == organization_payload["name"],
                )
            )
            if organization is None:
                organization = Organization(
                    owner_user_id=receiver_user_id,
                    network_tree_id=tree.id,
                    name=organization_payload["name"],
                    kind=organization_payload.get("kind") or "organization",
                )
                session.add(organization)
                await session.flush()
            session.add(
                PersonOrganization(
                    person_id=person.id,
                    organization_id=organization.id,
                    role=organization_payload.get("role"),
                )
            )
        await _store_imported_profile(session, provider, tree, person, person_payload)

    for connection_payload in payload.get("connections", []):
        person_a = id_map.get(str(connection_payload["person_a_id"]))
        person_b = id_map.get(str(connection_payload["person_b_id"]))
        if person_a is None or person_b is None or person_a == person_b:
            continue
        left, right = sorted([person_a, person_b], key=str)
        session.add(
            Connection(
                owner_user_id=receiver_user_id,
                network_tree_id=tree.id,
                person_a_id=left,
                person_b_id=right,
                label=connection_payload.get("label"),
                context=connection_payload.get("context"),
            )
        )

    snapshot.consumed_at = datetime.now(UTC)
    snapshot.consumed_by_user_id = receiver_user_id
    await session.flush()
    return tree


async def _store_imported_profile(
    session: AsyncSession,
    provider: EmbeddingProvider | None,
    tree: NetworkTree,
    person: Person,
    person_payload: dict[str, Any],
) -> None:
    content = str(person_payload.get("profile_content") or f"Name: {person.name}")
    embedding = person_payload.get("profile_embedding")
    if embedding is None and provider is not None:
        embedding = await provider.embed(content)
    if embedding is None:
        return
    identity = f"profile:{person.id}:None:None:{content}"
    session.add(
        KnowledgeChunk(
            owner_user_id=tree.owner_user_id,
            network_tree_id=tree.id,
            person_id=person.id,
            kind="profile",
            content=content,
            content_hash=hashlib.sha256(identity.encode()).hexdigest(),
            embedding_model=provider.embedding_model if provider is not None else "copied",
            embedding=list(embedding),
        )
    )


def _parse_datetime(value: Any) -> datetime | None:
    if not value:
        return None
    if isinstance(value, datetime):
        return value
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed
