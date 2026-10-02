"""Add persistent streaming transcription sessions and segments.

Revision ID: 0002_streaming_transcription
Revises: 0001_initial_schema
Create Date: 2026-10-02
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0002_streaming_transcription"
down_revision: str | None = "0001_initial_schema"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

session_status = postgresql.ENUM(
    "active",
    "completed",
    "interrupted",
    "error",
    name="transcription_session_status",
    create_type=False,
)


def timestamps() -> list[sa.Column[object]]:
    return [
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    ]


def upgrade() -> None:
    session_status.create(op.get_bind(), checkfirst=True)
    op.create_table(
        "transcription_sessions",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "status",
            session_status,
            server_default=sa.text("'active'"),
            nullable=False,
        ),
        sa.Column(
            "provider",
            sa.String(length=100),
            server_default=sa.text("'google-cloud-speech-v2'"),
            nullable=False,
        ),
        sa.Column(
            "started_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("has_gap", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("gap_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_transcription_sessions_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_transcription_sessions_person_id_people",
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_transcription_sessions"),
    )
    op.create_index(
        "ix_transcription_sessions_owner_started_at",
        "transcription_sessions",
        ["owner_user_id", "started_at"],
    )

    op.create_table(
        "transcript_segments",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("session_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("start_seconds", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("end_seconds", sa.Numeric(precision=12, scale=3), nullable=False),
        sa.Column("provider_result_id", sa.String(length=255), nullable=True),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["session_id"],
            ["transcription_sessions.id"],
            name="fk_transcript_segments_session_id_transcription_sessions",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_transcript_segments"),
        sa.UniqueConstraint(
            "session_id",
            "provider_result_id",
            name="uq_transcript_segments_session_provider_result",
        ),
        sa.UniqueConstraint(
            "session_id",
            "sequence",
            name="uq_transcript_segments_session_sequence",
        ),
    )
    op.create_index(
        "ix_transcript_segments_session_sequence",
        "transcript_segments",
        ["session_id", "sequence"],
    )

    op.add_column(
        "conversations",
        sa.Column("transcription_session_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_unique_constraint(
        "uq_conversations_transcription_session_id",
        "conversations",
        ["transcription_session_id"],
    )
    op.create_foreign_key(
        "fk_conversation_stream_session",
        "conversations",
        "transcription_sessions",
        ["transcription_session_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "fk_conversation_stream_session",
        "conversations",
        type_="foreignkey",
    )
    op.drop_constraint(
        "uq_conversations_transcription_session_id",
        "conversations",
        type_="unique",
    )
    op.drop_column("conversations", "transcription_session_id")
    op.drop_table("transcript_segments")
    op.drop_table("transcription_sessions")
    session_status.drop(op.get_bind(), checkfirst=True)
