from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class TranscriptSegment(BaseModel):
    start_seconds: float = Field(ge=0)
    end_seconds: float = Field(ge=0)
    text: str = Field(min_length=1)


class TranscriptionResponse(BaseModel):
    transcript: str
    segments: list[TranscriptSegment]
    provider: str
    language: str | None = None


class SummaryRequest(BaseModel):
    transcript: str = Field(min_length=1, max_length=100_000)

    model_config = ConfigDict(str_strip_whitespace=True)


class Evidence(BaseModel):
    excerpt: str = Field(
        description="A short, exact excerpt from the transcript supporting the suggestion."
    )


class PersonDetail(BaseModel):
    label: str
    value: str
    evidence: list[Evidence] = Field(default_factory=list)


class FollowUp(BaseModel):
    action: str
    owner: Literal["user", "contact", "shared", "unknown"] = "unknown"
    timing: str | None = None
    evidence: list[Evidence] = Field(default_factory=list)


class SuggestedNote(BaseModel):
    text: str
    evidence: list[Evidence] = Field(default_factory=list)


class SuggestedText(BaseModel):
    value: str
    confidence: float = Field(ge=0, le=1)
    evidence: list[Evidence] = Field(default_factory=list)


class SuggestedContactMethod(SuggestedText):
    kind: Literal["email", "phone", "other"]
    label: str | None = None


class SuggestedOrganization(SuggestedText):
    kind: Literal["group", "organization", "company", "other"] = "organization"
    role: str | None = None


class PersonProfileSuggestion(BaseModel):
    name: SuggestedText | None = None
    contact_methods: list[SuggestedContactMethod] = Field(default_factory=list)
    organizations: list[SuggestedOrganization] = Field(default_factory=list)
    goals: list[SuggestedText] = Field(default_factory=list)
    interests: list[SuggestedText] = Field(default_factory=list)
    how_met: SuggestedText | None = None
    where_met: SuggestedText | None = None
    general_notes: list[SuggestedText] = Field(default_factory=list)
    next_steps: list[SuggestedText] = Field(default_factory=list)
    how_to_serve: list[SuggestedText] = Field(default_factory=list)


class ConversationSummary(BaseModel):
    summary: str
    connection_points: list[str] = Field(default_factory=list)
    person_details: list[PersonDetail] = Field(default_factory=list)
    follow_ups: list[FollowUp] = Field(default_factory=list)
    suggested_notes: list[SuggestedNote] = Field(default_factory=list)
    profile_suggestion: PersonProfileSuggestion = Field(default_factory=PersonProfileSuggestion)


class CapabilitiesResponse(BaseModel):
    cloud_transcription: bool
    summarization: bool
    max_upload_mb: int
