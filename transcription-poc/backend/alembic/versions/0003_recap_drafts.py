"""Store generated recap drafts on transcription sessions.

Revision ID: 0003_recap_drafts
Revises: 0002_streaming_transcription
Create Date: 2026-10-02
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0003_recap_drafts"
down_revision: str | None = "0002_streaming_transcription"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "transcription_sessions",
        sa.Column(
            "summary_json",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("transcription_sessions", "summary_json")
