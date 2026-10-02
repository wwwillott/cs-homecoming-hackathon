"""Simple username/password auth for the MVP."""

from typing import Annotated
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from api_models import AuthCredentials, AuthResponse
from database.models import User
from database.session import get_session
from tree_store import ensure_primary_tree

router = APIRouter(prefix="/api/auth", tags=["auth"])
Session = Annotated[AsyncSession, Depends(get_session)]


def _normalize_username(username: str) -> str:
    return username.strip().lower()


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: AuthCredentials, session: Session) -> AuthResponse:
    username = _normalize_username(payload.username)
    if not username:
        raise HTTPException(status_code=400, detail="Username is required.")

    user = User(
        id=uuid4(),
        username=username,
        password=payload.password,
    )
    session.add(user)
    try:
        await session.flush()
        await ensure_primary_tree(session, user.id)
        await session.commit()
    except IntegrityError as error:
        await session.rollback()
        raise HTTPException(status_code=409, detail="Username is already taken.") from error

    return AuthResponse(user_id=user.id, username=username)


@router.post("/login", response_model=AuthResponse)
async def login(payload: AuthCredentials, session: Session) -> AuthResponse:
    username = _normalize_username(payload.username)
    user = await session.scalar(select(User).where(User.username == username))
    if user is None or user.password != payload.password:
        raise HTTPException(status_code=401, detail="Invalid username or password.")
    return AuthResponse(user_id=user.id, username=username)
