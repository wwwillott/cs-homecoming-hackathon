from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator
from pydantic.alias_generators import to_camel

from models import ConversationSummary, PersonProfileSuggestion


class ContactMethodInput(BaseModel):
    kind: Literal["email", "phone", "other"]
    value: str = Field(min_length=1)
    label: str | None = None
    is_primary: bool = False


class OrganizationInput(BaseModel):
    name: str = Field(min_length=1)
    kind: Literal["group", "organization", "company", "other"] = "organization"
    role: str | None = None


class PersonCreate(BaseModel):
    name: str = Field(min_length=1)
    alpha_score: Decimal | None = None
    how_met: str | None = None
    where_met: str | None = None
    met_at: datetime | None = None
    is_self: bool = False
    contact_methods: list[ContactMethodInput] = Field(default_factory=list)
    organizations: list[OrganizationInput] = Field(default_factory=list)
    goals: list[str] = Field(default_factory=list)
    interests: list[str] = Field(default_factory=list)


class PersonUpdate(BaseModel):
    name: str | None = None
    alpha_score: Decimal | None = None
    how_met: str | None = None
    where_met: str | None = None
    met_at: datetime | None = None


class ContactMethodResponse(ContactMethodInput):
    id: UUID

    model_config = ConfigDict(from_attributes=True)


class OrganizationResponse(OrganizationInput):
    id: UUID


class PersonResponse(BaseModel):
    id: UUID
    name: str
    alpha_score: Decimal | None
    how_met: str | None
    where_met: str | None
    met_at: datetime | None
    is_self: bool
    network_tree_id: UUID | None = None
    contact_methods: list[ContactMethodResponse] = Field(default_factory=list)
    organizations: list[OrganizationResponse] = Field(default_factory=list)
    goals: list[str] = Field(default_factory=list)
    interests: list[str] = Field(default_factory=list)
    notes: list[NoteResponse] = Field(default_factory=list)
    created_at: datetime
    updated_at: datetime


class ConnectionCreate(BaseModel):
    person_a_id: UUID
    person_b_id: UUID
    label: str | None = None
    context: str | None = None


class ConnectionResponse(ConnectionCreate):
    id: UUID
    created_at: datetime


class NetworkResponse(BaseModel):
    nodes: list[PersonResponse]
    edges: list[ConnectionResponse]


class ConversationCreate(BaseModel):
    person_id: UUID
    transcript: str | None = Field(default=None, min_length=1, max_length=100_000)
    transcription_session_id: UUID | None = None
    provider: str = "unknown"
    occurred_at: datetime | None = None

    @model_validator(mode="after")
    def require_transcript_source(self) -> "ConversationCreate":
        if self.transcript is None and self.transcription_session_id is None:
            raise ValueError("Provide a transcript or transcription_session_id.")
        return self


class ConversationResponse(BaseModel):
    id: UUID
    person_id: UUID
    transcript: str
    summary: ConversationSummary
    suggestion_id: UUID
    created_at: datetime


class RecapContact(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)

    name: str = Field(min_length=1)
    title: str = ""
    company: str = ""
    email: str = ""
    phone: str = ""
    linkedin: str = ""
    location: str = ""
    met_at: str = ""
    met_on: datetime | None = None
    strength: int = Field(default=5, ge=1, le=10)
    category: str = "other"
    tags: list[str] = Field(default_factory=list)
    notes: str = ""
    conversation_hooks: str = ""
    how_they_can_help: str = ""
    how_i_can_help: str = ""
    ai_summary: str = ""
    school: str = ""
    skills: list[str] = Field(default_factory=list)
    can_refer: bool = False


class RecapCommitRequest(BaseModel):
    contact: RecapContact


class RecapCommitResponse(BaseModel):
    person_id: UUID
    conversation_id: UUID


class SuggestionApproval(BaseModel):
    profile: PersonProfileSuggestion


class NoteResponse(BaseModel):
    id: UUID
    general_note: str | None
    next_steps: str | None
    how_to_serve: str | None
    conversation_id: UUID | None
    created_at: datetime


class NetworkQuestion(BaseModel):
    question: str = Field(min_length=1, max_length=2_000)
    tree_ids: list[UUID] | None = None


class NetworkCitation(BaseModel):
    chunk_id: UUID
    person_id: UUID | None
    person_name: str | None
    excerpt: str
    similarity: float


class NetworkAnswer(BaseModel):
    answer: str
    citations: list[NetworkCitation]


class IntroductionSuggestion(BaseModel):
    person_a_id: UUID
    person_a_name: str
    person_b_id: UUID
    person_b_name: str
    score: float
    reason: str
    person_a_tree_id: UUID | None = None
    person_b_tree_id: UUID | None = None


class NetworkTreeResponse(BaseModel):
    id: UUID
    label: str
    is_primary: bool
    is_read_only: bool
    attributed_user_id: UUID | None
    source_snapshot_id: UUID | None
    created_at: datetime


class NetworkTreeExportResponse(BaseModel):
    share_token: str
    expires_at: datetime | None
    snapshot_id: UUID


class NetworkTreeImportRequest(BaseModel):
    share_token: str = Field(min_length=4, max_length=64)


class AuthCredentials(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=128)


class AuthResponse(BaseModel):
    user_id: UUID
    username: str
