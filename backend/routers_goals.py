from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import current_user_id
from .repositories import (
    RepositoryConflictError,
    RepositoryNotFoundError,
    RepositoryValidationError,
    add_goal_task,
    delete_goal,
    list_goals,
    update_goal_task,
    upsert_goal,
)
from .schemas import Goal, GoalTask


router = APIRouter(prefix="/goals", tags=["goals"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


def _map_repository_error(exc: Exception) -> HTTPException:
    if isinstance(exc, RepositoryConflictError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    if isinstance(exc, RepositoryNotFoundError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    if isinstance(exc, RepositoryValidationError):
        return HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))
    return HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(exc))


@router.get("", response_model=list[Goal])
def get_goals(
    request: Request,
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    return list_goals(_db_path(request), user_id)


@router.post("", response_model=Goal)
def create_goal(
    payload: Goal,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return upsert_goal(_db_path(request), user_id, payload.model_dump(mode="json", by_alias=True))
    except (RepositoryConflictError, RepositoryNotFoundError, RepositoryValidationError) as exc:
        raise _map_repository_error(exc) from exc


@router.put("/{goal_id}", response_model=Goal)
def update_goal(
    goal_id: str,
    payload: Goal,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    data = payload.model_dump(mode="json", by_alias=True)
    data["id"] = goal_id
    try:
        return upsert_goal(_db_path(request), user_id, data)
    except (RepositoryConflictError, RepositoryNotFoundError, RepositoryValidationError) as exc:
        raise _map_repository_error(exc) from exc


@router.delete("/{goal_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_goal(
    goal_id: str,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> Response:
    delete_goal(_db_path(request), user_id, goal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/{goal_id}/tasks", response_model=Goal)
def create_goal_task(
    goal_id: str,
    payload: GoalTask,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return add_goal_task(
            _db_path(request),
            user_id,
            goal_id,
            payload.model_dump(mode="json", by_alias=True),
        )
    except (RepositoryConflictError, RepositoryNotFoundError, RepositoryValidationError) as exc:
        raise _map_repository_error(exc) from exc


@router.put("/{goal_id}/tasks/{task_id}", response_model=Goal)
def update_goal_task_route(
    goal_id: str,
    task_id: str,
    payload: GoalTask,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return update_goal_task(
            _db_path(request),
            user_id,
            goal_id,
            task_id,
            payload.model_dump(mode="json", by_alias=True),
        )
    except (RepositoryConflictError, RepositoryNotFoundError, RepositoryValidationError) as exc:
        raise _map_repository_error(exc) from exc
