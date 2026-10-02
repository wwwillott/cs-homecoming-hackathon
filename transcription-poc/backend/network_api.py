import hashlib
import math
import os
from collections.abc import Sequence
from datetime import UTC, datetime
from itertools import combinations
from typing import Annotated, cast
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from api_models import (
    ConnectionCreate,
    ConnectionResponse,
    ContactMethodResponse,
    ConversationCreate,
    ConversationResponse,
    IntroductionSuggestion,
    NetworkAnswer,
    NetworkCitation,
    NetworkQuestion,
    NetworkResponse,
    NetworkTreeExportResponse,
    NetworkTreeImportRequest,
    NetworkTreeResponse,
    NoteResponse,
    OrganizationResponse,
    PersonCreate,
    PersonResponse,
    PersonUpdate,
    RecapCommitRequest,
    RecapCommitResponse,
    SuggestionApproval,
)
from database.models import (
    Connection,
    ContactMethod,
    Conversation,
    ConversationPerson,
    KnowledgeChunk,
    NetworkSnapshot,
    NetworkTree,
    Organization,
    Person,
    PersonNote,
    PersonOrganization,
    PersonTopic,
    ProfileSuggestion,
    SuggestionStatus,
    TopicKind,
    TranscriptionSession,
    TranscriptionSessionStatus,
    User,
)
from database.session import get_session
from models import ConversationSummary, PersonProfileSuggestion, SuggestedText
from providers import VertexGeminiProvider
from transcription_store import canonical_transcript
from tree_store import (
    create_snapshot,
    ensure_primary_tree,
    import_snapshot,
    owned_tree,
)

router = APIRouter(prefix="/api")
Session = Annotated[AsyncSession, Depends(get_session)]
DEFAULT_USER_ID = UUID(os.getenv("DEVELOPMENT_USER_ID", "00000000-0000-0000-0000-000000000001"))


async def current_user_id(
    session: Session,
    x_user_id: Annotated[str | None, Header()] = None,
) -> UUID:
    try:
        user_id = UUID(x_user_id) if x_user_id else DEFAULT_USER_ID
    except ValueError as error:
        raise HTTPException(status_code=400, detail="X-User-Id must be a UUID.") from error

    if await session.get(User, user_id) is None:
        session.add(User(id=user_id))
        await session.flush()
    await ensure_primary_tree(session, user_id)
    await session.commit()
    return user_id


CurrentUser = Annotated[UUID, Depends(current_user_id)]


def tree_response(tree: NetworkTree, *, attributed_username: str | None = None) -> NetworkTreeResponse:
    return NetworkTreeResponse(
        id=tree.id,
        label=tree.label,
        is_primary=tree.is_primary,
        is_read_only=tree.is_read_only,
        attributed_user_id=tree.attributed_user_id,
        attributed_username=attributed_username,
        source_snapshot_id=tree.source_snapshot_id,
        created_at=tree.created_at,
    )


async def attributed_username_for(
    session: AsyncSession, tree: NetworkTree
) -> str | None:
    if tree.attributed_user_id is None:
        return None
    user = await session.get(User, tree.attributed_user_id)
    return user.username if user is not None else None


async def tree_response_async(
    session: AsyncSession, tree: NetworkTree
) -> NetworkTreeResponse:
    return tree_response(
        tree,
        attributed_username=await attributed_username_for(session, tree),
    )


async def require_owned_tree(
    session: AsyncSession, user_id: UUID, tree_id: UUID
) -> NetworkTree:
    tree = await owned_tree(session, user_id, tree_id)
    if tree is None:
        raise HTTPException(status_code=404, detail="Network tree not found.")
    return tree


async def require_writable_tree(tree: NetworkTree) -> NetworkTree:
    if tree.is_read_only:
        raise HTTPException(status_code=403, detail="This shared tree is read-only.")
    return tree


async def primary_tree(session: AsyncSession, user_id: UUID) -> NetworkTree:
    return await ensure_primary_tree(session, user_id)


async def owned_person(session: AsyncSession, user_id: UUID, person_id: UUID) -> Person:
    person = await session.scalar(
        select(Person).where(Person.id == person_id, Person.owner_user_id == user_id)
    )
    if person is None:
        raise HTTPException(status_code=404, detail="Person not found.")
    return person


async def writable_person(session: AsyncSession, user_id: UUID, person_id: UUID) -> Person:
    person = await owned_person(session, user_id, person_id)
    tree = await session.get(NetworkTree, person.network_tree_id)
    if tree is None or tree.is_read_only:
        raise HTTPException(status_code=403, detail="This shared tree is read-only.")
    return person


async def person_response(session: AsyncSession, person: Person) -> PersonResponse:
    contacts = (
        await session.scalars(
            select(ContactMethod)
            .where(ContactMethod.person_id == person.id)
            .order_by(ContactMethod.is_primary.desc(), ContactMethod.created_at)
        )
    ).all()
    organization_rows = (
        await session.execute(
            select(Organization, PersonOrganization.role)
            .join(
                PersonOrganization,
                PersonOrganization.organization_id == Organization.id,
            )
            .where(PersonOrganization.person_id == person.id)
            .order_by(Organization.name)
        )
    ).all()
    topics = (
        await session.scalars(
            select(PersonTopic)
            .where(PersonTopic.person_id == person.id)
            .order_by(PersonTopic.kind, PersonTopic.topic)
        )
    ).all()

    return PersonResponse(
        id=person.id,
        name=person.name,
        alpha_score=float(person.alpha_score) if person.alpha_score is not None else None,
        how_met=person.how_met,
        where_met=person.where_met,
        met_at=person.met_at,
        is_self=person.is_self,
        network_tree_id=person.network_tree_id,
        contact_methods=[ContactMethodResponse.model_validate(contact) for contact in contacts],
        organizations=[
            OrganizationResponse(
                id=organization.id,
                name=organization.name,
                kind=organization.kind,
                role=role,
            )
            for organization, role in organization_rows
        ],
        goals=[topic.topic for topic in topics if topic.kind == TopicKind.GOAL],
        interests=[topic.topic for topic in topics if topic.kind == TopicKind.INTEREST],
        notes=[
            NoteResponse(
                id=note.id,
                general_note=note.general_note,
                next_steps=note.next_steps,
                how_to_serve=note.how_to_serve,
                conversation_id=note.conversation_id,
                created_at=note.created_at,
            )
            for note in (
                await session.scalars(
                    select(PersonNote)
                    .where(PersonNote.person_id == person.id)
                    .order_by(PersonNote.created_at)
                )
            ).all()
        ],
        created_at=person.created_at,
        updated_at=person.updated_at,
    )


async def add_organization(
    session: AsyncSession,
    user_id: UUID,
    tree_id: UUID,
    person_id: UUID,
    name: str,
    kind: str,
    role: str | None,
) -> None:
    organization = await session.scalar(
        select(Organization).where(
            Organization.network_tree_id == tree_id,
            Organization.name == name,
        )
    )
    if organization is None:
        organization = Organization(
            owner_user_id=user_id,
            network_tree_id=tree_id,
            name=name,
            kind=kind,
        )
        session.add(organization)
        await session.flush()
    session.add(
        PersonOrganization(
            person_id=person_id,
            organization_id=organization.id,
            role=role,
        )
    )


@router.post("/people", response_model=PersonResponse, status_code=status.HTTP_201_CREATED)
async def create_person(
    payload: PersonCreate, session: Session, user_id: CurrentUser
) -> PersonResponse:
    tree = await require_writable_tree(await primary_tree(session, user_id))
    person = Person(
        owner_user_id=user_id,
        network_tree_id=tree.id,
        name=payload.name,
        alpha_score=payload.alpha_score,
        how_met=payload.how_met,
        where_met=payload.where_met,
        met_at=payload.met_at,
        is_self=payload.is_self,
    )
    session.add(person)
    await session.flush()
    session.add_all(
        [
            ContactMethod(person_id=person.id, **contact.model_dump())
            for contact in payload.contact_methods
        ]
    )
    session.add_all(
        [
            PersonTopic(person_id=person.id, kind=TopicKind.GOAL, topic=value)
            for value in payload.goals
        ]
        + [
            PersonTopic(person_id=person.id, kind=TopicKind.INTEREST, topic=value)
            for value in payload.interests
        ]
    )
    for organization in payload.organizations:
        await add_organization(
            session,
            user_id,
            tree.id,
            person.id,
            organization.name,
            organization.kind,
            organization.role,
        )
    try:
        await session.commit()
    except IntegrityError as error:
        await session.rollback()
        raise HTTPException(
            status_code=409, detail="The person conflicts with existing network data."
        ) from error
    await session.refresh(person)
    return await person_response(session, person)


@router.get("/people", response_model=list[PersonResponse])
async def list_people(
    session: Session,
    user_id: CurrentUser,
    tree_id: UUID | None = None,
) -> list[PersonResponse]:
    tree = (
        await require_owned_tree(session, user_id, tree_id)
        if tree_id is not None
        else await primary_tree(session, user_id)
    )
    people = (
        await session.scalars(
            select(Person)
            .where(Person.owner_user_id == user_id, Person.network_tree_id == tree.id)
            .order_by(Person.name)
        )
    ).all()
    return [await person_response(session, person) for person in people]


@router.get("/people/{person_id}", response_model=PersonResponse)
async def get_person(person_id: UUID, session: Session, user_id: CurrentUser) -> PersonResponse:
    return await person_response(session, await owned_person(session, user_id, person_id))


@router.patch("/people/{person_id}", response_model=PersonResponse)
async def update_person(
    person_id: UUID,
    payload: PersonUpdate,
    session: Session,
    user_id: CurrentUser,
) -> PersonResponse:
    person = await writable_person(session, user_id, person_id)
    for field in payload.model_fields_set:
        setattr(person, field, getattr(payload, field))
    await session.commit()
    await session.refresh(person)
    return await person_response(session, person)


@router.delete("/people/{person_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_person(person_id: UUID, session: Session, user_id: CurrentUser) -> None:
    person = await writable_person(session, user_id, person_id)
    await session.delete(person)
    await session.commit()


@router.post(
    "/connections",
    response_model=ConnectionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_connection(
    payload: ConnectionCreate, session: Session, user_id: CurrentUser
) -> ConnectionResponse:
    person_a = await writable_person(session, user_id, payload.person_a_id)
    person_b = await writable_person(session, user_id, payload.person_b_id)
    if payload.person_a_id == payload.person_b_id:
        raise HTTPException(status_code=400, detail="A person cannot connect to themself.")
    if person_a.network_tree_id != person_b.network_tree_id:
        raise HTTPException(status_code=400, detail="People must belong to the same tree.")
    person_a_id, person_b_id = sorted([payload.person_a_id, payload.person_b_id], key=str)
    connection = Connection(
        owner_user_id=user_id,
        network_tree_id=person_a.network_tree_id,
        person_a_id=person_a_id,
        person_b_id=person_b_id,
        label=payload.label,
        context=payload.context,
    )
    session.add(connection)
    try:
        await session.commit()
    except IntegrityError as error:
        await session.rollback()
        raise HTTPException(status_code=409, detail="Connection already exists.") from error
    await session.refresh(connection)
    return ConnectionResponse.model_validate(connection, from_attributes=True)


@router.delete("/connections/{connection_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_connection(connection_id: UUID, session: Session, user_id: CurrentUser) -> None:
    connection = await session.scalar(
        select(Connection).where(
            Connection.id == connection_id, Connection.owner_user_id == user_id
        )
    )
    if connection is None:
        raise HTTPException(status_code=404, detail="Connection not found.")
    tree = await session.get(NetworkTree, connection.network_tree_id)
    if tree is None or tree.is_read_only:
        raise HTTPException(status_code=403, detail="This shared tree is read-only.")
    await session.delete(connection)
    await session.commit()


@router.get("/network", response_model=NetworkResponse)
async def get_network(
    session: Session,
    user_id: CurrentUser,
    tree_id: UUID | None = None,
) -> NetworkResponse:
    tree = (
        await require_owned_tree(session, user_id, tree_id)
        if tree_id is not None
        else await primary_tree(session, user_id)
    )
    people = (
        await session.scalars(
            select(Person)
            .where(Person.owner_user_id == user_id, Person.network_tree_id == tree.id)
            .order_by(Person.name)
        )
    ).all()
    connections = (
        await session.scalars(
            select(Connection).where(
                Connection.owner_user_id == user_id,
                Connection.network_tree_id == tree.id,
            )
        )
    ).all()
    return NetworkResponse(
        nodes=[await person_response(session, person) for person in people],
        edges=[
            ConnectionResponse.model_validate(connection, from_attributes=True)
            for connection in connections
        ],
    )


def gemini_provider(request: Request) -> VertexGeminiProvider:
    provider = request.app.state.summary_provider
    if provider is None:
        raise HTTPException(status_code=503, detail="Gemini is not configured.")
    return cast(VertexGeminiProvider, provider)


@router.post(
    "/conversations",
    response_model=ConversationResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_conversation(
    payload: ConversationCreate,
    request: Request,
    session: Session,
    user_id: CurrentUser,
) -> ConversationResponse:
    person = await writable_person(session, user_id, payload.person_id)
    provider = gemini_provider(request)
    transcript = payload.transcript
    transcription_session: TranscriptionSession | None = None
    if payload.transcription_session_id is not None:
        transcription_session = await session.scalar(
            select(TranscriptionSession).where(
                TranscriptionSession.id == payload.transcription_session_id,
                TranscriptionSession.owner_user_id == user_id,
            )
        )
        if transcription_session is None:
            raise HTTPException(status_code=404, detail="Transcription session not found.")
        if transcription_session.status != TranscriptionSessionStatus.COMPLETED:
            raise HTTPException(status_code=409, detail="Transcription session is not completed.")
        if (
            transcription_session.person_id is not None
            and transcription_session.person_id != person.id
        ):
            raise HTTPException(
                status_code=409,
                detail="Transcription session belongs to a different person.",
            )
        transcript = await canonical_transcript(session, transcription_session.id)
    if not transcript:
        raise HTTPException(status_code=422, detail="The canonical transcript is empty.")

    summary = await provider.summarize(transcript)
    conversation = Conversation(
        owner_user_id=user_id,
        transcription_session_id=(
            transcription_session.id if transcription_session is not None else None
        ),
        transcript=transcript,
        summary_json=summary.model_dump(mode="json"),
        provider=(
            transcription_session.provider
            if transcription_session is not None
            else payload.provider
        ),
        occurred_at=payload.occurred_at or datetime.now(UTC),
    )
    session.add(conversation)
    await session.flush()
    session.add(
        ConversationPerson(conversation_id=conversation.id, person_id=person.id, role="contact")
    )
    suggestion = ProfileSuggestion(
        owner_user_id=user_id,
        person_id=person.id,
        conversation_id=conversation.id,
        payload=summary.profile_suggestion.model_dump(mode="json"),
    )
    session.add(suggestion)
    await session.commit()
    await session.refresh(conversation)
    await session.refresh(suggestion)
    return ConversationResponse(
        id=conversation.id,
        person_id=person.id,
        transcript=conversation.transcript,
        summary=summary,
        suggestion_id=suggestion.id,
        created_at=conversation.created_at,
    )


async def owned_transcription_session(
    session: AsyncSession,
    user_id: UUID,
    transcription_session_id: UUID,
) -> TranscriptionSession:
    transcription_session = await session.scalar(
        select(TranscriptionSession).where(
            TranscriptionSession.id == transcription_session_id,
            TranscriptionSession.owner_user_id == user_id,
        )
    )
    if transcription_session is None:
        raise HTTPException(status_code=404, detail="Transcription session not found.")
    return transcription_session


def recap_contact(summary: ConversationSummary, session_id: UUID) -> dict[str, object]:
    profile = summary.profile_suggestion
    contacts = {item.kind: item.value for item in profile.contact_methods}
    linkedin = next(
        (
            item.value
            for item in profile.contact_methods
            if item.kind == "other" and (item.label or "").casefold() in {"linkedin", "linked in"}
        ),
        "",
    )
    organization = profile.organizations[0] if profile.organizations else None
    notes = [item.value for item in profile.general_notes]
    notes.extend(item.value for item in profile.next_steps)
    interests = [item.value for item in profile.interests]
    goals = [item.value for item in profile.goals]
    hooks = list(dict.fromkeys([*summary.connection_points, *interests]))
    title = organization.role if organization and organization.role else ""
    title_lower = title.casefold()
    category = next(
        (
            value
            for keyword, value in (
                ("recruit", "recruiter"),
                ("founder", "founder"),
                ("engineer", "engineer"),
                ("mentor", "mentor"),
                ("alumni", "alumni"),
                ("student", "peer"),
            )
            if keyword in title_lower
        ),
        "other",
    )
    fields = {
        "name": profile.name.value if profile.name else "",
        "title": title,
        "company": organization.value if organization else "",
        "email": contacts.get("email", ""),
        "phone": contacts.get("phone", ""),
        "linkedin": linkedin,
        "location": profile.where_met.value if profile.where_met else "",
        "metAt": profile.where_met.value if profile.where_met else "",
        "metOn": datetime.now(UTC).isoformat(),
        "strength": 5,
        "category": category,
        "tags": interests,
        "notes": "\n".join(notes),
        "conversationHooks": "\n".join(hooks),
        "howTheyCanHelp": "\n".join(goals),
        "howICanHelp": "\n".join(item.value for item in profile.how_to_serve),
        "aiSummary": summary.summary,
        "school": "",
        "skills": goals,
        "canRefer": any("refer" in value.casefold() for value in notes + goals),
    }
    ai_fields = [key for key, value in fields.items() if value not in ("", [], False)]
    return {
        "contact": {"id": f"draft-{session_id}", **fields},
        "aiFields": ai_fields,
    }


@router.post("/transcription-sessions/{transcription_session_id}/draft")
async def create_recap_draft(
    transcription_session_id: UUID,
    request: Request,
    session: Session,
    user_id: CurrentUser,
) -> dict[str, object]:
    transcription_session = await owned_transcription_session(
        session, user_id, transcription_session_id
    )
    if transcription_session.status != TranscriptionSessionStatus.COMPLETED:
        raise HTTPException(status_code=409, detail="Transcription session is not completed.")
    transcript = await canonical_transcript(session, transcription_session.id)
    if not transcript:
        raise HTTPException(status_code=422, detail="The canonical transcript is empty.")
    summary = await gemini_provider(request).summarize(transcript)
    transcription_session.summary_json = summary.model_dump(mode="json")
    await session.commit()
    return {
        **recap_contact(summary, transcription_session.id),
        "transcript": transcript,
        "sessionId": str(transcription_session.id),
    }


@router.post(
    "/transcription-sessions/{transcription_session_id}/commit",
    response_model=RecapCommitResponse,
)
async def commit_recap_draft(
    transcription_session_id: UUID,
    payload: RecapCommitRequest,
    request: Request,
    session: Session,
    user_id: CurrentUser,
) -> RecapCommitResponse:
    transcription_session = await owned_transcription_session(
        session, user_id, transcription_session_id
    )
    existing = (
        await session.execute(
            select(Conversation, ConversationPerson)
            .join(
                ConversationPerson,
                ConversationPerson.conversation_id == Conversation.id,
            )
            .where(
                Conversation.owner_user_id == user_id,
                Conversation.transcription_session_id == transcription_session.id,
            )
        )
    ).first()
    if existing is not None:
        conversation, conversation_person = existing
        return RecapCommitResponse(
            person_id=conversation_person.person_id,
            conversation_id=conversation.id,
        )
    if transcription_session.status != TranscriptionSessionStatus.COMPLETED:
        raise HTTPException(status_code=409, detail="Transcription session is not completed.")
    transcript = await canonical_transcript(session, transcription_session.id)
    if not transcript:
        raise HTTPException(status_code=422, detail="The canonical transcript is empty.")

    contact = payload.contact
    tree = await require_writable_tree(await primary_tree(session, user_id))
    person = Person(
        owner_user_id=user_id,
        network_tree_id=tree.id,
        name=contact.name,
        alpha_score=contact.strength,
        how_met=contact.met_at or None,
        where_met=contact.location or contact.met_at or None,
        met_at=contact.met_on,
    )
    session.add(person)
    await session.flush()
    for kind, value, label in (
        ("email", contact.email, None),
        ("phone", contact.phone, None),
        ("other", contact.linkedin, "LinkedIn"),
    ):
        if value:
            session.add(
                ContactMethod(
                    person_id=person.id,
                    kind=kind,
                    value=value,
                    label=label,
                    is_primary=kind == "email",
                )
            )
    if contact.company:
        await add_organization(
            session,
            user_id,
            tree.id,
            person.id,
            contact.company,
            "company",
            contact.title or None,
        )
    topics = list(dict.fromkeys([*contact.tags, *contact.skills]))
    session.add_all(
        [
            PersonTopic(person_id=person.id, kind=TopicKind.INTEREST, topic=value)
            for value in topics
            if value
        ]
    )
    conversation = Conversation(
        owner_user_id=user_id,
        transcription_session_id=transcription_session.id,
        transcript=transcript,
        summary_json=transcription_session.summary_json,
        provider=transcription_session.provider,
        occurred_at=contact.met_on or datetime.now(UTC),
    )
    session.add(conversation)
    await session.flush()
    session.add(
        ConversationPerson(
            conversation_id=conversation.id,
            person_id=person.id,
            role="contact",
        )
    )
    general_note = "\n\n".join(
        value
        for value in (
            contact.notes,
            contact.conversation_hooks,
            contact.ai_summary,
            contact.how_they_can_help,
        )
        if value
    )
    note: PersonNote | None = None
    if general_note or contact.how_i_can_help:
        note = PersonNote(
            person_id=person.id,
            conversation_id=conversation.id,
            general_note=general_note or None,
            how_to_serve=contact.how_i_can_help or None,
        )
        session.add(note)
        await session.flush()
    provider = gemini_provider(request)
    profile_content = "\n".join(
        value
        for value in (
            f"Name: {contact.name}",
            f"Title: {contact.title}" if contact.title else "",
            f"Company: {contact.company}" if contact.company else "",
            f"Interests: {', '.join(topics)}" if topics else "",
            f"Notes: {general_note}" if general_note else "",
            f"How to help: {contact.how_i_can_help}" if contact.how_i_can_help else "",
        )
        if value
    )
    await store_chunk(
        session,
        provider,
        user_id,
        profile_content,
        "profile",
        person_id=person.id,
        note_id=note.id if note is not None else None,
    )
    await store_chunk(
        session,
        provider,
        user_id,
        transcript,
        "conversation",
        person_id=person.id,
        conversation_id=conversation.id,
    )
    transcription_session.person_id = person.id
    await session.commit()
    return RecapCommitResponse(person_id=person.id, conversation_id=conversation.id)


def join_suggestions(values: Sequence[SuggestedText]) -> str | None:
    texts = [value.value for value in values if value.value]
    return "\n".join(texts) or None


def profile_document(person: Person, profile: PersonProfileSuggestion) -> str:
    parts = [f"Name: {person.name}"]
    if person.how_met:
        parts.append(f"How we met: {person.how_met}")
    if person.where_met:
        parts.append(f"Where we met: {person.where_met}")
    for organization in profile.organizations:
        parts.append(f"Organization: {organization.value}")
    for interest in profile.interests:
        parts.append(f"Interest: {interest.value}")
    for goal in profile.goals:
        parts.append(f"Goal: {goal.value}")
    for note in profile.general_notes:
        parts.append(f"Note: {note.value}")
    for item in profile.how_to_serve:
        parts.append(f"How to help: {item.value}")
    return "\n".join(parts)


async def store_chunk(
    session: AsyncSession,
    provider: VertexGeminiProvider,
    user_id: UUID,
    content: str,
    kind: str,
    *,
    person_id: UUID | None = None,
    conversation_id: UUID | None = None,
    note_id: UUID | None = None,
    network_tree_id: UUID | None = None,
) -> None:
    if network_tree_id is None and person_id is not None:
        person = await session.get(Person, person_id)
        if person is not None:
            network_tree_id = person.network_tree_id
    if network_tree_id is None:
        network_tree_id = (await ensure_primary_tree(session, user_id)).id
    identity = f"{kind}:{person_id}:{conversation_id}:{note_id}:{content}"
    content_hash = hashlib.sha256(identity.encode()).hexdigest()
    embedding = await provider.embed(content)
    session.add(
        KnowledgeChunk(
            owner_user_id=user_id,
            network_tree_id=network_tree_id,
            person_id=person_id,
            conversation_id=conversation_id,
            note_id=note_id,
            kind=kind,
            content=content,
            content_hash=content_hash,
            embedding_model=provider.embedding_model,
            embedding=embedding,
        )
    )


@router.post("/suggestions/{suggestion_id}/approve", response_model=PersonResponse)
async def approve_suggestion(
    suggestion_id: UUID,
    payload: SuggestionApproval,
    request: Request,
    session: Session,
    user_id: CurrentUser,
) -> PersonResponse:
    suggestion = await session.scalar(
        select(ProfileSuggestion).where(
            ProfileSuggestion.id == suggestion_id,
            ProfileSuggestion.owner_user_id == user_id,
        )
    )
    if suggestion is None:
        raise HTTPException(status_code=404, detail="Suggestion not found.")
    if suggestion.status != SuggestionStatus.PENDING:
        raise HTTPException(status_code=409, detail="Suggestion is already resolved.")
    person = await writable_person(session, user_id, suggestion.person_id)
    profile = payload.profile
    if profile.name:
        person.name = profile.name.value
    if profile.how_met:
        person.how_met = profile.how_met.value
    if profile.where_met:
        person.where_met = profile.where_met.value

    existing_contacts = set(
        (
            await session.execute(
                select(ContactMethod.kind, ContactMethod.value).where(
                    ContactMethod.person_id == person.id
                )
            )
        ).all()
    )
    for contact in profile.contact_methods:
        if (contact.kind, contact.value) not in existing_contacts:
            session.add(
                ContactMethod(
                    person_id=person.id,
                    kind=contact.kind,
                    value=contact.value,
                    label=contact.label,
                )
            )
    for organization in profile.organizations:
        existing = await session.scalar(
            select(PersonOrganization)
            .join(Organization)
            .where(
                PersonOrganization.person_id == person.id,
                Organization.name == organization.value,
            )
        )
        if existing is None:
            await add_organization(
                session,
                user_id,
                person.network_tree_id,
                person.id,
                organization.value,
                organization.kind,
                organization.role,
            )
    existing_topics = set(
        (
            await session.execute(
                select(PersonTopic.kind, PersonTopic.topic).where(
                    PersonTopic.person_id == person.id
                )
            )
        ).all()
    )
    for kind, values in (
        (TopicKind.GOAL, profile.goals),
        (TopicKind.INTEREST, profile.interests),
    ):
        for value in values:
            if (kind, value.value) not in existing_topics:
                session.add(PersonTopic(person_id=person.id, kind=kind, topic=value.value))

    note = PersonNote(
        person_id=person.id,
        conversation_id=suggestion.conversation_id,
        general_note=join_suggestions(profile.general_notes),
        next_steps=join_suggestions(profile.next_steps),
        how_to_serve=join_suggestions(profile.how_to_serve),
    )
    if note.general_note or note.next_steps or note.how_to_serve:
        session.add(note)
        await session.flush()

    provider = gemini_provider(request)
    await session.execute(
        delete(KnowledgeChunk).where(
            KnowledgeChunk.owner_user_id == user_id,
            KnowledgeChunk.person_id == person.id,
            KnowledgeChunk.kind == "profile",
        )
    )
    await store_chunk(
        session,
        provider,
        user_id,
        profile_document(person, profile),
        "profile",
        person_id=person.id,
    )
    conversation = await session.get(Conversation, suggestion.conversation_id)
    if conversation is not None:
        await store_chunk(
            session,
            provider,
            user_id,
            conversation.transcript,
            "conversation",
            person_id=person.id,
            conversation_id=conversation.id,
        )
    suggestion.status = SuggestionStatus.ACCEPTED
    await session.commit()
    await session.refresh(person)
    return await person_response(session, person)


@router.post("/suggestions/{suggestion_id}/reject", status_code=status.HTTP_204_NO_CONTENT)
async def reject_suggestion(suggestion_id: UUID, session: Session, user_id: CurrentUser) -> None:
    suggestion = await session.scalar(
        select(ProfileSuggestion).where(
            ProfileSuggestion.id == suggestion_id,
            ProfileSuggestion.owner_user_id == user_id,
        )
    )
    if suggestion is None:
        raise HTTPException(status_code=404, detail="Suggestion not found.")
    suggestion.status = SuggestionStatus.REJECTED
    await session.commit()


@router.get("/network-trees", response_model=list[NetworkTreeResponse])
async def list_network_trees(session: Session, user_id: CurrentUser) -> list[NetworkTreeResponse]:
    trees = (
        await session.scalars(
            select(NetworkTree)
            .where(NetworkTree.owner_user_id == user_id)
            .order_by(NetworkTree.is_primary.desc(), NetworkTree.created_at)
        )
    ).all()
    return [await tree_response_async(session, tree) for tree in trees]


@router.post(
    "/network-trees/{tree_id}/export",
    response_model=NetworkTreeExportResponse,
    status_code=status.HTTP_201_CREATED,
)
async def export_network_tree(
    tree_id: UUID, session: Session, user_id: CurrentUser
) -> NetworkTreeExportResponse:
    tree = await require_writable_tree(await require_owned_tree(session, user_id, tree_id))
    if not tree.is_primary:
        raise HTTPException(status_code=400, detail="Only the primary tree can be shared.")
    snapshot = await create_snapshot(session, tree)
    await session.commit()
    await session.refresh(snapshot)
    return NetworkTreeExportResponse(
        share_token=snapshot.share_token,
        expires_at=snapshot.expires_at,
        snapshot_id=snapshot.id,
    )


@router.post(
    "/network-trees/import",
    response_model=NetworkTreeResponse,
    status_code=status.HTTP_201_CREATED,
)
async def import_network_tree(
    payload: NetworkTreeImportRequest,
    request: Request,
    session: Session,
    user_id: CurrentUser,
) -> NetworkTreeResponse:
    token = payload.share_token.strip().upper()
    snapshot = await session.scalar(
        select(NetworkSnapshot).where(NetworkSnapshot.share_token == token)
    )
    if snapshot is None:
        raise HTTPException(status_code=404, detail="Share code not found.")
    if snapshot.source_user_id == user_id:
        raise HTTPException(status_code=400, detail="You cannot import your own network.")
    if snapshot.expires_at is not None and snapshot.expires_at < datetime.now(UTC):
        raise HTTPException(status_code=410, detail="This share code has expired.")
    if snapshot.consumed_at is not None:
        raise HTTPException(status_code=410, detail="This share code has already been used.")
    already = await session.scalar(
        select(NetworkTree).where(
            NetworkTree.owner_user_id == user_id,
            NetworkTree.source_snapshot_id == snapshot.id,
        )
    )
    if already is not None:
        raise HTTPException(status_code=409, detail="This network is already attached.")
    provider = getattr(request.app.state, "summary_provider", None)
    tree = await import_snapshot(session, user_id, snapshot, provider)
    await session.commit()
    await session.refresh(tree)
    return await tree_response_async(session, tree)


async def resolve_tree_ids(
    session: AsyncSession, user_id: UUID, tree_ids: list[UUID] | None
) -> list[UUID]:
    if not tree_ids:
        return [(await primary_tree(session, user_id)).id]
    resolved: list[UUID] = []
    for tree_id in tree_ids:
        resolved.append((await require_owned_tree(session, user_id, tree_id)).id)
    return resolved


@router.post("/network/ask", response_model=NetworkAnswer)
async def ask_network(
    payload: NetworkQuestion,
    request: Request,
    session: Session,
    user_id: CurrentUser,
) -> NetworkAnswer:
    provider = gemini_provider(request)
    tree_ids = await resolve_tree_ids(session, user_id, payload.tree_ids)
    query_embedding = await provider.embed(payload.question, query=True)
    distance = KnowledgeChunk.embedding.cosine_distance(query_embedding)
    rows = (
        await session.execute(
            select(KnowledgeChunk, Person.name, distance.label("distance"))
            .outerjoin(Person, KnowledgeChunk.person_id == Person.id)
            .where(
                KnowledgeChunk.owner_user_id == user_id,
                KnowledgeChunk.network_tree_id.in_(tree_ids),
            )
            .order_by(distance)
            .limit(8)
        )
    ).all()
    if not rows:
        return NetworkAnswer(
            answer="There is not enough approved network information to answer that yet.",
            citations=[],
        )
    evidence = [chunk.content for chunk, _, _ in rows]
    answer = await provider.answer_network(payload.question, evidence)
    return NetworkAnswer(
        answer=answer,
        citations=[
            NetworkCitation(
                chunk_id=chunk.id,
                person_id=chunk.person_id,
                person_name=name,
                excerpt=chunk.content[:500],
                similarity=max(0.0, 1.0 - float(distance_value)),
            )
            for chunk, name, distance_value in rows
        ],
    )


def cosine_similarity(left: list[float], right: list[float]) -> float:
    dot = sum(a * b for a, b in zip(left, right, strict=True))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    return dot / (left_norm * right_norm) if left_norm and right_norm else 0


@router.get(
    "/network/introduction-suggestions",
    response_model=list[IntroductionSuggestion],
)
async def introduction_suggestions(
    session: Session,
    user_id: CurrentUser,
    mode: str = "same_tree",
    tree_id: UUID | None = None,
) -> list[IntroductionSuggestion]:
    primary = await primary_tree(session, user_id)
    if mode == "cross_tree":
        if tree_id is None:
            raise HTTPException(
                status_code=400,
                detail="tree_id is required for cross-tree introductions.",
            )
        attached = await require_owned_tree(session, user_id, tree_id)
        if attached.is_primary:
            raise HTTPException(
                status_code=400,
                detail="Cross-tree introductions need an attached tree.",
            )
        left_rows = await _profile_rows(session, user_id, primary.id)
        right_rows = await _profile_rows(session, user_id, attached.id)
        pairs = ((left, right) for left in left_rows for right in right_rows)
    else:
        scoped_id = (await require_owned_tree(session, user_id, tree_id)).id if tree_id else primary.id
        rows = await _profile_rows(session, user_id, scoped_id)
        pairs = combinations(rows, 2)

    connected_rows = (
        await session.execute(
            select(Connection.person_a_id, Connection.person_b_id).where(
                Connection.owner_user_id == user_id
            )
        )
    ).all()
    connected = {frozenset(pair) for pair in connected_rows}
    topics = (
        await session.execute(
            select(PersonTopic.person_id, PersonTopic.topic)
            .join(Person, Person.id == PersonTopic.person_id)
            .where(Person.owner_user_id == user_id)
        )
    ).all()
    topic_map: dict[UUID, set[str]] = {}
    for person_id, topic in topics:
        topic_map.setdefault(person_id, set()).add(topic.casefold())

    suggestions: list[IntroductionSuggestion] = []
    for (person_a, embedding_a), (person_b, embedding_b) in pairs:
        if frozenset((person_a.id, person_b.id)) in connected:
            continue
        similarity = cosine_similarity(list(embedding_a), list(embedding_b))
        shared = sorted(topic_map.get(person_a.id, set()) & topic_map.get(person_b.id, set()))
        score = min(1.0, similarity * 0.8 + min(len(shared), 2) * 0.1)
        reason = (
            f"Shared interests or goals: {', '.join(shared)}."
            if shared
            else "Their approved profiles are semantically related."
        )
        suggestions.append(
            IntroductionSuggestion(
                person_a_id=person_a.id,
                person_a_name=person_a.name,
                person_b_id=person_b.id,
                person_b_name=person_b.name,
                score=score,
                reason=reason,
                person_a_tree_id=person_a.network_tree_id,
                person_b_tree_id=person_b.network_tree_id,
            )
        )
    return sorted(suggestions, key=lambda item: item.score, reverse=True)[:10]


async def _profile_rows(
    session: AsyncSession, user_id: UUID, tree_id: UUID
) -> list[tuple[Person, list[float]]]:
    return list(
        (
            await session.execute(
                select(Person, KnowledgeChunk.embedding)
                .join(KnowledgeChunk, KnowledgeChunk.person_id == Person.id)
                .where(
                    Person.owner_user_id == user_id,
                    Person.network_tree_id == tree_id,
                    Person.is_self.is_(False),
                    KnowledgeChunk.kind == "profile",
                )
            )
        ).all()
    )
