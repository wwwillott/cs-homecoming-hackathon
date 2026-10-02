"""Create the initial relationship knowledge schema.

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-10-02
"""

from collections.abc import Sequence

import sqlalchemy as sa
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0001_initial_schema"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

topic_kind = postgresql.ENUM("goal", "interest", name="person_topic_kind", create_type=False)
suggestion_status = postgresql.ENUM(
    "pending",
    "accepted",
    "rejected",
    name="profile_suggestion_status",
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
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")
    topic_kind.create(op.get_bind(), checkfirst=True)
    suggestion_status.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("email", sa.String(length=320), nullable=True),
        *timestamps(),
        sa.PrimaryKeyConstraint("id", name="pk_users"),
        sa.UniqueConstraint("email", name="uq_users_email"),
    )

    op.create_table(
        "people",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column("alpha_score", sa.Numeric(precision=5, scale=2), nullable=True),
        sa.Column("is_self", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("how_met", sa.Text(), nullable=True),
        sa.Column("where_met", sa.Text(), nullable=True),
        sa.Column("met_at", sa.DateTime(timezone=True), nullable=True),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_people_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_people"),
    )
    op.create_index("ix_people_owner_name", "people", ["owner_user_id", "name"])
    op.create_index(
        "uq_people_owner_self",
        "people",
        ["owner_user_id"],
        unique=True,
        postgresql_where=sa.text("is_self"),
    )

    op.create_table(
        "organizations",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=255), nullable=False),
        sa.Column(
            "kind",
            sa.String(length=50),
            server_default=sa.text("'organization'"),
            nullable=False,
        ),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_organizations_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_organizations"),
        sa.UniqueConstraint(
            "owner_user_id",
            "name",
            name="uq_organizations_owner_name",
        ),
    )

    op.create_table(
        "conversations",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("transcript", sa.Text(), nullable=False),
        sa.Column("summary_json", postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column("provider", sa.String(length=100), nullable=False),
        sa.Column(
            "occurred_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_conversations_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_conversations"),
    )
    op.create_index(
        "ix_conversations_owner_occurred_at",
        "conversations",
        ["owner_user_id", "occurred_at"],
    )

    op.create_table(
        "contact_methods",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("kind", sa.String(length=50), nullable=False),
        sa.Column("value", sa.String(length=500), nullable=False),
        sa.Column("label", sa.String(length=100), nullable=True),
        sa.Column("is_primary", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_contact_methods_person_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_contact_methods"),
        sa.UniqueConstraint(
            "person_id",
            "kind",
            "value",
            name="uq_contact_methods_person_kind_value",
        ),
    )
    op.create_index(
        "ix_contact_methods_kind_value",
        "contact_methods",
        ["kind", "value"],
    )

    op.create_table(
        "person_organizations",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("organization_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("role", sa.String(length=255), nullable=True),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["organization_id"],
            ["organizations.id"],
            name="fk_person_organizations_organization_id_organizations",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_person_organizations_person_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_person_organizations"),
        sa.UniqueConstraint(
            "person_id",
            "organization_id",
            name="uq_person_organizations_person_organization",
        ),
    )

    op.create_table(
        "person_topics",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("kind", topic_kind, nullable=False),
        sa.Column("topic", sa.Text(), nullable=False),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_person_topics_person_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_person_topics"),
        sa.UniqueConstraint(
            "person_id",
            "kind",
            "topic",
            name="uq_person_topics_person_kind_topic",
        ),
    )

    op.create_table(
        "connections",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_a_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_b_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("label", sa.String(length=255), nullable=True),
        sa.Column("context", sa.Text(), nullable=True),
        *timestamps(),
        sa.CheckConstraint(
            "person_a_id < person_b_id",
            name="ck_connections_canonical_person_order",
        ),
        sa.CheckConstraint(
            "person_a_id <> person_b_id",
            name="ck_connections_no_self_connection",
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_connections_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["person_a_id"],
            ["people.id"],
            name="fk_connections_person_a_id_people",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["person_b_id"],
            ["people.id"],
            name="fk_connections_person_b_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_connections"),
        sa.UniqueConstraint(
            "owner_user_id",
            "person_a_id",
            "person_b_id",
            name="uq_connections_owner_pair",
        ),
    )
    op.create_index(
        "ix_connections_owner_person_a",
        "connections",
        ["owner_user_id", "person_a_id"],
    )
    op.create_index(
        "ix_connections_owner_person_b",
        "connections",
        ["owner_user_id", "person_b_id"],
    )

    op.create_table(
        "conversation_people",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("role", sa.String(length=100), nullable=True),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            name="fk_conversation_people_conversation_id_conversations",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_conversation_people_person_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_conversation_people"),
        sa.UniqueConstraint(
            "conversation_id",
            "person_id",
            name="uq_conversation_people_conversation_person",
        ),
    )

    op.create_table(
        "person_notes",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("general_note", sa.Text(), nullable=True),
        sa.Column("next_steps", sa.Text(), nullable=True),
        sa.Column("how_to_serve", sa.Text(), nullable=True),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            name="fk_person_notes_conversation_id_conversations",
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_person_notes_person_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_person_notes"),
    )
    op.create_index(
        "ix_person_notes_person_updated_at",
        "person_notes",
        ["person_id", "updated_at"],
    )

    op.create_table(
        "profile_suggestions",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "status",
            suggestion_status,
            server_default=sa.text("'pending'"),
            nullable=False,
        ),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            name="fk_profile_suggestions_conversation_id_conversations",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_profile_suggestions_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_profile_suggestions_person_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_profile_suggestions"),
    )
    op.create_index(
        "ix_profile_suggestions_owner_status",
        "profile_suggestions",
        ["owner_user_id", "status"],
    )
    op.create_index(
        "ix_profile_suggestions_person_created_at",
        "profile_suggestions",
        ["person_id", "created_at"],
    )

    op.create_table(
        "knowledge_chunks",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("person_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("conversation_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("note_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("kind", sa.String(length=100), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("content_hash", sa.String(length=64), nullable=False),
        sa.Column("embedding_model", sa.String(length=255), nullable=False),
        sa.Column("embedding", Vector(768), nullable=False),
        *timestamps(),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            name="fk_knowledge_chunks_conversation_id_conversations",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["note_id"],
            ["person_notes.id"],
            name="fk_knowledge_chunks_note_id_person_notes",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_knowledge_chunks_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["person_id"],
            ["people.id"],
            name="fk_knowledge_chunks_person_id_people",
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_knowledge_chunks"),
        sa.UniqueConstraint(
            "owner_user_id",
            "content_hash",
            "embedding_model",
            name="uq_knowledge_chunks_owner_hash_model",
        ),
    )
    op.create_index(
        "ix_knowledge_chunks_owner_kind",
        "knowledge_chunks",
        ["owner_user_id", "kind"],
    )
    op.create_index("ix_knowledge_chunks_person", "knowledge_chunks", ["person_id"])
    op.create_index(
        "ix_knowledge_chunks_conversation",
        "knowledge_chunks",
        ["conversation_id"],
    )
    op.create_index("ix_knowledge_chunks_note", "knowledge_chunks", ["note_id"])


def downgrade() -> None:
    op.drop_table("knowledge_chunks")
    op.drop_table("profile_suggestions")
    op.drop_table("person_notes")
    op.drop_table("conversation_people")
    op.drop_table("connections")
    op.drop_table("person_topics")
    op.drop_table("person_organizations")
    op.drop_table("contact_methods")
    op.drop_table("conversations")
    op.drop_table("organizations")
    op.drop_table("people")
    op.drop_table("users")

    suggestion_status.drop(op.get_bind(), checkfirst=True)
    topic_kind.drop(op.get_bind(), checkfirst=True)
    op.execute("DROP EXTENSION IF EXISTS vector")
