from __future__ import annotations

import enum
import uuid
from datetime import datetime
from decimal import Decimal
from typing import Any

from pgvector.sqlalchemy import Vector
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Enum,
    ForeignKey,
    Index,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    func,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database.base import Base, TimestampMixin


class TopicKind(enum.StrEnum):
    GOAL = "goal"
    INTEREST = "interest"


class SuggestionStatus(enum.StrEnum):
    PENDING = "pending"
    ACCEPTED = "accepted"
    REJECTED = "rejected"


class TranscriptionSessionStatus(enum.StrEnum):
    ACTIVE = "active"
    COMPLETED = "completed"
    INTERRUPTED = "interrupted"
    ERROR = "error"


topic_kind_enum = Enum(
    TopicKind,
    name="person_topic_kind",
    values_callable=lambda enum_class: [member.value for member in enum_class],
)
suggestion_status_enum = Enum(
    SuggestionStatus,
    name="profile_suggestion_status",
    values_callable=lambda enum_class: [member.value for member in enum_class],
)
transcription_session_status_enum = Enum(
    TranscriptionSessionStatus,
    name="transcription_session_status",
    values_callable=lambda enum_class: [member.value for member in enum_class],
)


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username: Mapped[str | None] = mapped_column(String(64), unique=True)
    password: Mapped[str | None] = mapped_column(String(255))
    email: Mapped[str | None] = mapped_column(String(320), unique=True)

    people: Mapped[list[Person]] = relationship(back_populates="owner")
    organizations: Mapped[list[Organization]] = relationship(back_populates="owner")
    conversations: Mapped[list[Conversation]] = relationship(back_populates="owner")
    transcription_sessions: Mapped[list[TranscriptionSession]] = relationship(
        back_populates="owner"
    )
    network_trees: Mapped[list[NetworkTree]] = relationship(
        back_populates="owner",
        foreign_keys="NetworkTree.owner_user_id",
    )


class NetworkTree(TimestampMixin, Base):
    __tablename__ = "network_trees"
    __table_args__ = (
        Index(
            "uq_network_trees_owner_primary",
            "owner_user_id",
            unique=True,
            postgresql_where=text("is_primary"),
        ),
        Index("ix_network_trees_owner", "owner_user_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    attributed_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
    )
    label: Mapped[str] = mapped_column(String(255), nullable=False, default="My network")
    is_primary: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    is_read_only: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    source_snapshot_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("network_snapshots.id", ondelete="SET NULL", use_alter=True),
    )

    owner: Mapped[User] = relationship(
        back_populates="network_trees",
        foreign_keys=[owner_user_id],
    )
    attributed_user: Mapped[User | None] = relationship(foreign_keys=[attributed_user_id])
    source_snapshot: Mapped[NetworkSnapshot | None] = relationship(
        foreign_keys=[source_snapshot_id]
    )


class NetworkSnapshot(TimestampMixin, Base):
    __tablename__ = "network_snapshots"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    source_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    source_tree_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("network_trees.id", ondelete="SET NULL"),
    )
    payload_json: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    share_token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consumed_by_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
    )

    source_user: Mapped[User] = relationship(foreign_keys=[source_user_id])


class Person(TimestampMixin, Base):
    __tablename__ = "people"
    __table_args__ = (
        Index("ix_people_owner_name", "owner_user_id", "name"),
        Index(
            "uq_people_tree_self",
            "network_tree_id",
            unique=True,
            postgresql_where=text("is_self"),
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    network_tree_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("network_trees.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    alpha_score: Mapped[Decimal | None] = mapped_column(Numeric(5, 2))
    is_self: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    how_met: Mapped[str | None] = mapped_column(Text)
    where_met: Mapped[str | None] = mapped_column(Text)
    met_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    owner: Mapped[User] = relationship(back_populates="people")
    network_tree: Mapped[NetworkTree] = relationship()
    contact_methods: Mapped[list[ContactMethod]] = relationship(
        back_populates="person",
        cascade="all, delete-orphan",
    )
    topics: Mapped[list[PersonTopic]] = relationship(
        back_populates="person",
        cascade="all, delete-orphan",
    )
    notes: Mapped[list[PersonNote]] = relationship(
        back_populates="person",
        cascade="all, delete-orphan",
    )
    transcription_sessions: Mapped[list[TranscriptionSession]] = relationship(
        back_populates="person"
    )


class ContactMethod(TimestampMixin, Base):
    __tablename__ = "contact_methods"
    __table_args__ = (
        UniqueConstraint("person_id", "kind", "value", name="uq_contact_methods_person_kind_value"),
        Index("ix_contact_methods_kind_value", "kind", "value"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    person_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    kind: Mapped[str] = mapped_column(String(50), nullable=False)
    value: Mapped[str] = mapped_column(String(500), nullable=False)
    label: Mapped[str | None] = mapped_column(String(100))
    is_primary: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )

    person: Mapped[Person] = relationship(back_populates="contact_methods")


class Organization(TimestampMixin, Base):
    __tablename__ = "organizations"
    __table_args__ = (
        UniqueConstraint("network_tree_id", "name", name="uq_organizations_tree_name"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    network_tree_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("network_trees.id", ondelete="CASCADE"),
        nullable=False,
    )
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    kind: Mapped[str] = mapped_column(
        String(50), nullable=False, default="organization", server_default="organization"
    )

    owner: Mapped[User] = relationship(back_populates="organizations")
    people: Mapped[list[PersonOrganization]] = relationship(
        back_populates="organization",
        cascade="all, delete-orphan",
    )


class PersonOrganization(TimestampMixin, Base):
    __tablename__ = "person_organizations"
    __table_args__ = (
        UniqueConstraint(
            "person_id",
            "organization_id",
            name="uq_person_organizations_person_organization",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    person_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    organization_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("organizations.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str | None] = mapped_column(String(255))

    person: Mapped[Person] = relationship()
    organization: Mapped[Organization] = relationship(back_populates="people")


class PersonTopic(TimestampMixin, Base):
    __tablename__ = "person_topics"
    __table_args__ = (
        UniqueConstraint("person_id", "kind", "topic", name="uq_person_topics_person_kind_topic"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    person_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    kind: Mapped[TopicKind] = mapped_column(topic_kind_enum, nullable=False)
    topic: Mapped[str] = mapped_column(Text, nullable=False)

    person: Mapped[Person] = relationship(back_populates="topics")


class Connection(TimestampMixin, Base):
    __tablename__ = "connections"
    __table_args__ = (
        CheckConstraint("person_a_id <> person_b_id", name="no_self_connection"),
        CheckConstraint("person_a_id < person_b_id", name="canonical_person_order"),
        UniqueConstraint(
            "network_tree_id",
            "person_a_id",
            "person_b_id",
            name="uq_connections_tree_pair",
        ),
        Index("ix_connections_owner_person_a", "owner_user_id", "person_a_id"),
        Index("ix_connections_owner_person_b", "owner_user_id", "person_b_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    network_tree_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("network_trees.id", ondelete="CASCADE"),
        nullable=False,
    )
    person_a_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    person_b_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    label: Mapped[str | None] = mapped_column(String(255))
    context: Mapped[str | None] = mapped_column(Text)

    owner: Mapped[User] = relationship()
    person_a: Mapped[Person] = relationship(foreign_keys=[person_a_id])
    person_b: Mapped[Person] = relationship(foreign_keys=[person_b_id])


class Conversation(TimestampMixin, Base):
    __tablename__ = "conversations"
    __table_args__ = (Index("ix_conversations_owner_occurred_at", "owner_user_id", "occurred_at"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    transcription_session_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("transcription_sessions.id", ondelete="SET NULL"),
        unique=True,
    )
    transcript: Mapped[str] = mapped_column(Text, nullable=False)
    summary_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB)
    provider: Mapped[str] = mapped_column(String(100), nullable=False)
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )

    owner: Mapped[User] = relationship(back_populates="conversations")
    people: Mapped[list[ConversationPerson]] = relationship(
        back_populates="conversation",
        cascade="all, delete-orphan",
    )
    notes: Mapped[list[PersonNote]] = relationship(back_populates="conversation")
    transcription_session: Mapped[TranscriptionSession | None] = relationship(
        back_populates="conversation"
    )


class TranscriptionSession(TimestampMixin, Base):
    __tablename__ = "transcription_sessions"
    __table_args__ = (
        Index(
            "ix_transcription_sessions_owner_started_at",
            "owner_user_id",
            "started_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    person_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="SET NULL"),
    )
    status: Mapped[TranscriptionSessionStatus] = mapped_column(
        transcription_session_status_enum,
        nullable=False,
        default=TranscriptionSessionStatus.ACTIVE,
        server_default=TranscriptionSessionStatus.ACTIVE.value,
    )
    provider: Mapped[str] = mapped_column(
        String(100),
        nullable=False,
        default="google-cloud-speech-v2",
        server_default="google-cloud-speech-v2",
    )
    started_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
    )
    ended_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    has_gap: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )
    gap_count: Mapped[int] = mapped_column(nullable=False, default=0, server_default="0")
    summary_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB)

    owner: Mapped[User] = relationship(back_populates="transcription_sessions")
    person: Mapped[Person | None] = relationship(back_populates="transcription_sessions")
    segments: Mapped[list[TranscriptSegmentRecord]] = relationship(
        back_populates="session",
        cascade="all, delete-orphan",
        order_by="TranscriptSegmentRecord.sequence",
    )
    conversation: Mapped[Conversation | None] = relationship(back_populates="transcription_session")


class TranscriptSegmentRecord(TimestampMixin, Base):
    __tablename__ = "transcript_segments"
    __table_args__ = (
        UniqueConstraint(
            "session_id",
            "sequence",
            name="uq_transcript_segments_session_sequence",
        ),
        UniqueConstraint(
            "session_id",
            "provider_result_id",
            name="uq_transcript_segments_session_provider_result",
        ),
        Index("ix_transcript_segments_session_sequence", "session_id", "sequence"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    session_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("transcription_sessions.id", ondelete="CASCADE"),
        nullable=False,
    )
    sequence: Mapped[int] = mapped_column(nullable=False)
    text: Mapped[str] = mapped_column(Text, nullable=False)
    start_seconds: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    end_seconds: Mapped[Decimal] = mapped_column(Numeric(12, 3), nullable=False)
    provider_result_id: Mapped[str | None] = mapped_column(String(255))

    session: Mapped[TranscriptionSession] = relationship(back_populates="segments")


class ConversationPerson(TimestampMixin, Base):
    __tablename__ = "conversation_people"
    __table_args__ = (
        UniqueConstraint(
            "conversation_id",
            "person_id",
            name="uq_conversation_people_conversation_person",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
    )
    person_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str | None] = mapped_column(String(100))

    conversation: Mapped[Conversation] = relationship(back_populates="people")
    person: Mapped[Person] = relationship()


class PersonNote(TimestampMixin, Base):
    __tablename__ = "person_notes"
    __table_args__ = (Index("ix_person_notes_person_updated_at", "person_id", "updated_at"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    person_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id", ondelete="SET NULL"),
    )
    general_note: Mapped[str | None] = mapped_column(Text)
    next_steps: Mapped[str | None] = mapped_column(Text)
    how_to_serve: Mapped[str | None] = mapped_column(Text)

    person: Mapped[Person] = relationship(back_populates="notes")
    conversation: Mapped[Conversation | None] = relationship(back_populates="notes")


class ProfileSuggestion(TimestampMixin, Base):
    __tablename__ = "profile_suggestions"
    __table_args__ = (
        Index("ix_profile_suggestions_owner_status", "owner_user_id", "status"),
        Index("ix_profile_suggestions_person_created_at", "person_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    person_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
        nullable=False,
    )
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id", ondelete="CASCADE"),
        nullable=False,
    )
    payload: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    status: Mapped[SuggestionStatus] = mapped_column(
        suggestion_status_enum,
        nullable=False,
        default=SuggestionStatus.PENDING,
        server_default=SuggestionStatus.PENDING.value,
    )

    owner: Mapped[User] = relationship()
    person: Mapped[Person] = relationship()
    conversation: Mapped[Conversation] = relationship()


class KnowledgeChunk(TimestampMixin, Base):
    __tablename__ = "knowledge_chunks"
    __table_args__ = (
        UniqueConstraint(
            "network_tree_id",
            "content_hash",
            "embedding_model",
            name="uq_knowledge_chunks_tree_hash_model",
        ),
        Index("ix_knowledge_chunks_owner_kind", "owner_user_id", "kind"),
        Index("ix_knowledge_chunks_person", "person_id"),
        Index("ix_knowledge_chunks_conversation", "conversation_id"),
        Index("ix_knowledge_chunks_note", "note_id"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    network_tree_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("network_trees.id", ondelete="CASCADE"),
        nullable=False,
    )
    person_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("people.id", ondelete="CASCADE"),
    )
    conversation_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversations.id", ondelete="CASCADE"),
    )
    note_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("person_notes.id", ondelete="CASCADE"),
    )
    kind: Mapped[str] = mapped_column(String(100), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    embedding_model: Mapped[str] = mapped_column(String(255), nullable=False)
    embedding: Mapped[list[float]] = mapped_column(Vector(768), nullable=False)

    owner: Mapped[User] = relationship()
    person: Mapped[Person | None] = relationship()
    conversation: Mapped[Conversation | None] = relationship()
    note: Mapped[PersonNote | None] = relationship()
