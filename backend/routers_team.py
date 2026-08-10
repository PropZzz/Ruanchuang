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
)
from .schemas import TeamMemberCalendar, TeamPermissionUpdate


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
