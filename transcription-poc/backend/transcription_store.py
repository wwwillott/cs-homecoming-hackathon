import hashlib
from datetime import UTC, datetime
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from database.models import (
    Person,
    TranscriptionSession,
    TranscriptionSessionStatus,
    TranscriptSegmentRecord,
    User,
)


async def create_or_resume_session(
    db: AsyncSession,
    user_id: UUID,
    *,
    session_id: UUID | None = None,
    person_id: UUID | None = None,
) -> TranscriptionSession:
    if await db.get(User, user_id) is None:
        db.add(User(id=user_id))
        await db.flush()
    if person_id is not None:
        person = await db.scalar(
            select(Person).where(
                Person.id == person_id,
                Person.owner_user_id == user_id,
            )
        )
        if person is None:
            raise HTTPException(status_code=404, detail="Person not found.")

    if session_id is not None:
        transcription_session = await db.scalar(
            select(TranscriptionSession).where(
                TranscriptionSession.id == session_id,
                TranscriptionSession.owner_user_id == user_id,
            )
        )
        if transcription_session is None:
            raise HTTPException(status_code=404, detail="Transcription session not found.")
        if transcription_session.status == TranscriptionSessionStatus.COMPLETED:
            raise HTTPException(status_code=409, detail="Transcription session is completed.")
        transcription_session.status = TranscriptionSessionStatus.ACTIVE
        transcription_session.ended_at = None
        if person_id is not None:
            transcription_session.person_id = person_id
    else:
        transcription_session = TranscriptionSession(
            owner_user_id=user_id,
            person_id=person_id,
        )
        db.add(transcription_session)

    await db.commit()
    await db.refresh(transcription_session)
    return transcription_session


async def next_segment_sequence(db: AsyncSession, session_id: UUID) -> int:
    value = await db.scalar(
        select(func.max(TranscriptSegmentRecord.sequence)).where(
            TranscriptSegmentRecord.session_id == session_id
        )
    )
    return int(value or 0) + 1


async def persist_final_segment(
    db: AsyncSession,
    session_id: UUID,
    *,
    sequence: int,
    text: str,
    start_seconds: float,
    end_seconds: float,
    provider_result_id: str | None = None,
) -> bool:
    result_id = (
        provider_result_id
        or hashlib.sha256(f"{text}:{start_seconds:.3f}:{end_seconds:.3f}".encode()).hexdigest()
    )
    statement = (
        insert(TranscriptSegmentRecord)
        .values(
            session_id=session_id,
            sequence=sequence,
            text=text,
            start_seconds=Decimal(str(max(0, start_seconds))),
            end_seconds=Decimal(str(max(0, end_seconds))),
            provider_result_id=result_id,
        )
        .on_conflict_do_nothing()
        .returning(TranscriptSegmentRecord.id)
    )
    result = await db.execute(statement)
    await db.commit()
    return result.scalar_one_or_none() is not None


async def canonical_transcript(db: AsyncSession, session_id: UUID) -> str:
    segments = (
        await db.scalars(
            select(TranscriptSegmentRecord)
            .where(TranscriptSegmentRecord.session_id == session_id)
            .order_by(TranscriptSegmentRecord.sequence)
        )
    ).all()
    return " ".join(segment.text.strip() for segment in segments if segment.text.strip())


async def mark_session(
    db: AsyncSession,
    session_id: UUID,
    status: TranscriptionSessionStatus,
) -> None:
    transcription_session = await db.get(TranscriptionSession, session_id)
    if transcription_session is None:
        return
    transcription_session.status = status
    transcription_session.ended_at = datetime.now(UTC)
    await db.commit()


async def record_gap(db: AsyncSession, session_id: UUID, count: int = 1) -> None:
    transcription_session = await db.get(TranscriptionSession, session_id)
    if transcription_session is None:
        return
    transcription_session.has_gap = True
    transcription_session.gap_count += max(1, count)
    await db.commit()
