from uuid import uuid4

from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from database.session import get_session
from main import Settings, create_app

TEST_DATABASE_URL = "postgresql+psycopg://network:network@localhost:5432/network_test"


def auth_client() -> TestClient:
    engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    app = create_app(Settings(google_cloud_project=None))

    async def override_session():  # type: ignore[no-untyped-def]
        async with session_factory() as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    return TestClient(app)


def test_register_and_login() -> None:
    client = auth_client()
    username = f"user_{uuid4().hex[:8]}"
    password = "hackathon"

    register = client.post(
        "/api/auth/register",
        json={"username": username, "password": password},
    )
    assert register.status_code == 201, register.text
    body = register.json()
    assert body["username"] == username
    assert body["user_id"]

    duplicate = client.post(
        "/api/auth/register",
        json={"username": username.upper(), "password": "other"},
    )
    assert duplicate.status_code == 409

    bad_login = client.post(
        "/api/auth/login",
        json={"username": username, "password": "wrong"},
    )
    assert bad_login.status_code == 401

    login = client.post(
        "/api/auth/login",
        json={"username": username, "password": password},
    )
    assert login.status_code == 200
    assert login.json()["user_id"] == body["user_id"]
