"""Add network trees and snapshots, then backfill one primary tree per user.

Revision ID: 0005_network_trees
Revises: 0004_user_auth
Create Date: 2026-10-02
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0005_network_trees"
down_revision: str | None = "0004_user_auth"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "network_snapshots",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("source_tree_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("payload_json", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("share_token", sa.String(length=64), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("consumed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("consumed_by_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["source_user_id"],
            ["users.id"],
            name="fk_network_snapshots_source_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["consumed_by_user_id"],
            ["users.id"],
            name="fk_network_snapshots_consumed_by_user_id_users",
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_network_snapshots"),
        sa.UniqueConstraint("share_token", name="uq_network_snapshots_share_token"),
    )

    op.create_table(
        "network_trees",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("attributed_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("label", sa.String(length=255), nullable=False),
        sa.Column("is_primary", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_read_only", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("source_snapshot_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["owner_user_id"],
            ["users.id"],
            name="fk_network_trees_owner_user_id_users",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["attributed_user_id"],
            ["users.id"],
            name="fk_network_trees_attributed_user_id_users",
            ondelete="SET NULL",
        ),
        sa.ForeignKeyConstraint(
            ["source_snapshot_id"],
            ["network_snapshots.id"],
            name="fk_network_trees_source_snapshot_id_network_snapshots",
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_network_trees"),
    )
    op.create_index("ix_network_trees_owner", "network_trees", ["owner_user_id"])
    op.create_index(
        "uq_network_trees_owner_primary",
        "network_trees",
        ["owner_user_id"],
        unique=True,
        postgresql_where=sa.text("is_primary"),
    )
    op.create_foreign_key(
        "fk_network_snapshots_source_tree_id_network_trees",
        "network_snapshots",
        "network_trees",
        ["source_tree_id"],
        ["id"],
        ondelete="SET NULL",
    )

    op.execute(
        """
        INSERT INTO network_trees (
            id, owner_user_id, attributed_user_id, label,
            is_primary, is_read_only, created_at, updated_at
        )
        SELECT gen_random_uuid(), id, id, 'My network', true, false, now(), now()
        FROM users
        """
    )

    for table in ("people", "connections", "organizations", "knowledge_chunks"):
        op.add_column(
            table,
            sa.Column("network_tree_id", postgresql.UUID(as_uuid=True), nullable=True),
        )
        op.execute(
            f"""
            UPDATE {table} AS row
            SET network_tree_id = tree.id
            FROM network_trees AS tree
            WHERE tree.owner_user_id = row.owner_user_id AND tree.is_primary
            """
        )
        op.alter_column(table, "network_tree_id", nullable=False)
        op.create_foreign_key(
            f"fk_{table}_network_tree_id_network_trees",
            table,
            "network_trees",
            ["network_tree_id"],
            ["id"],
            ondelete="CASCADE",
        )

    op.drop_index("uq_people_owner_self", table_name="people")
    op.create_index(
        "uq_people_tree_self",
        "people",
        ["network_tree_id"],
        unique=True,
        postgresql_where=sa.text("is_self"),
    )

    op.drop_constraint("uq_organizations_owner_name", "organizations", type_="unique")
    op.create_unique_constraint(
        "uq_organizations_tree_name",
        "organizations",
        ["network_tree_id", "name"],
    )

    op.drop_constraint("uq_connections_owner_pair", "connections", type_="unique")
    op.create_unique_constraint(
        "uq_connections_tree_pair",
        "connections",
        ["network_tree_id", "person_a_id", "person_b_id"],
    )

    op.drop_constraint(
        "uq_knowledge_chunks_owner_hash_model",
        "knowledge_chunks",
        type_="unique",
    )
    op.create_unique_constraint(
        "uq_knowledge_chunks_tree_hash_model",
        "knowledge_chunks",
        ["network_tree_id", "content_hash", "embedding_model"],
    )


def downgrade() -> None:
    op.drop_constraint(
        "uq_knowledge_chunks_tree_hash_model",
        "knowledge_chunks",
        type_="unique",
    )
    op.create_unique_constraint(
        "uq_knowledge_chunks_owner_hash_model",
        "knowledge_chunks",
        ["owner_user_id", "content_hash", "embedding_model"],
    )
    op.drop_constraint("uq_connections_tree_pair", "connections", type_="unique")
    op.create_unique_constraint(
        "uq_connections_owner_pair",
        "connections",
        ["owner_user_id", "person_a_id", "person_b_id"],
    )
    op.drop_constraint("uq_organizations_tree_name", "organizations", type_="unique")
    op.create_unique_constraint(
        "uq_organizations_owner_name",
        "organizations",
        ["owner_user_id", "name"],
    )
    op.drop_index("uq_people_tree_self", table_name="people")
    op.create_index(
        "uq_people_owner_self",
        "people",
        ["owner_user_id"],
        unique=True,
        postgresql_where=sa.text("is_self"),
    )

    for table in ("people", "connections", "organizations", "knowledge_chunks"):
        op.drop_constraint(
            f"fk_{table}_network_tree_id_network_trees",
            table,
            type_="foreignkey",
        )
        op.drop_column(table, "network_tree_id")

    op.drop_constraint(
        "fk_network_snapshots_source_tree_id_network_trees",
        "network_snapshots",
        type_="foreignkey",
    )
    op.drop_index("uq_network_trees_owner_primary", table_name="network_trees")
    op.drop_index("ix_network_trees_owner", table_name="network_trees")
    op.drop_table("network_trees")
    op.drop_table("network_snapshots")
