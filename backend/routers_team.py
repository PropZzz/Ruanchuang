from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status

from .auth import current_user_id
from .repositories import (
    RepositoryConflictError,
    RepositoryNotFoundError,
    delete_team_member,
    list_team_members,
    update_team_member_permission,
    upsert_team_member,
    list_schedules,
    upsert_schedule,
)
from .schemas import TeamBookMeetingRequest, TeamConflictsRequest, TeamGoldenWindowsRequest, TeamMemberCalendar, TeamPermissionUpdate, ScheduleEntryOut
from .services_team import conflicts as calculate_conflicts, golden_windows


router = APIRouter(prefix="/team", tags=["team"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


def _map_repository_error(exc: Exception) -> HTTPException:
    if isinstance(exc, RepositoryConflictError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    if isinstance(exc, RepositoryNotFoundError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))


@router.get("/members", response_model=list[TeamMemberCalendar])
def get_team_members(
    request: Request,
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    return list_team_members(_db_path(request), user_id)


@router.post("/members", response_model=TeamMemberCalendar)
def create_team_member(
    payload: TeamMemberCalendar,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return upsert_team_member(
            _db_path(request),
            user_id,
            payload.model_dump(mode="json", by_alias=True),
        )
    except (RepositoryConflictError, RepositoryNotFoundError) as exc:
        raise _map_repository_error(exc) from exc


@router.put("/members/{member_id}", response_model=TeamMemberCalendar)
def update_team_member(
    member_id: str,
    payload: TeamMemberCalendar,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return upsert_team_member(
            _db_path(request),
            user_id,
            payload.model_dump(mode="json", by_alias=True),
            member_id=member_id,
        )
    except (RepositoryConflictError, RepositoryNotFoundError) as exc:
        raise _map_repository_error(exc) from exc


@router.delete("/members/{member_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_team_member(
    member_id: str,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> Response:
    delete_team_member(_db_path(request), user_id, member_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/members/{member_id}/permission", response_model=TeamMemberCalendar)
def update_permission(
    member_id: str,
    payload: TeamPermissionUpdate,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return update_team_member_permission(
            _db_path(request),
            user_id,
            member_id,
            payload.permission,
        )
    except (RepositoryConflictError, RepositoryNotFoundError) as exc:
        raise _map_repository_error(exc) from exc


@router.get("/calendars", response_model=list[TeamMemberCalendar])
def get_team_calendars(
    request: Request,
    day: date = Query(...),
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    return list_team_members(_db_path(request), user_id, day=day.isoformat())


def _members_for_ids(request: Request, user_id: str, member_ids: list[str], day: str) -> list[dict[str, object]]:
    members = list_team_members(_db_path(request), user_id, day=day)
    selected = [member for member in members if member["memberId"] in member_ids]
    if len(selected) != len(set(member_ids)):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="One or more team members were not found")
    return selected


@router.post("/conflicts")
def team_conflicts(payload: TeamConflictsRequest, request: Request, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    members = _members_for_ids(request, user_id, payload.member_ids, payload.day.isoformat())
    start = payload.start.hour * 60 + payload.start.minute
    return {"conflicts": calculate_conflicts(members, payload.day.isoformat(), start, payload.minutes)}


@router.post("/golden-windows")
def team_golden_windows(payload: TeamGoldenWindowsRequest, request: Request, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    members = _members_for_ids(request, user_id, payload.member_ids, payload.day.isoformat())
    return {"windows": golden_windows(members, payload.day.isoformat(), [window.model_dump(mode="json") for window in payload.windows], payload.minutes)}


@router.post("/book-meeting", response_model=ScheduleEntryOut)
def book_team_meeting(payload: TeamBookMeetingRequest, request: Request, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    members = _members_for_ids(request, user_id, payload.participant_ids, payload.day.isoformat())
    start = payload.start.hour * 60 + payload.start.minute
    conflicts = calculate_conflicts(members, payload.day.isoformat(), start, payload.minutes)
    if conflicts:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail={"message": "Meeting overlaps a member busy block", "conflicts": conflicts})
    return upsert_schedule(_db_path(request), user_id, {"id": f"meeting-{payload.day.isoformat()}-{start}", "day": payload.day.isoformat(), "title": payload.title, "tag": "Team meeting", "height": payload.minutes * 80 / 60, "color": 0, "time": payload.start.model_dump()})
