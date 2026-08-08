from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from .auth import current_user_id
from .repositories import (
    TaskEventBatchValidationError,
    TaskEventConflictError,
    list_task_events,
    upsert_task_event,
    upsert_task_events,
)
from .schemas import TaskEvent


router = APIRouter(prefix="/events", tags=["events"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


@router.post("", response_model=TaskEvent)
def create_event(
    payload: TaskEvent,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return upsert_task_event(
            _db_path(request),
            user_id,
            payload.model_dump(mode="json", by_alias=True),
        )
    except TaskEventConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc


@router.post("/batch", response_model=list[TaskEvent])
def create_event_batch(
    payload: list[TaskEvent],
    request: Request,
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    try:
        return upsert_task_events(
            _db_path(request),
            user_id,
            [event.model_dump(mode="json", by_alias=True) for event in payload],
        )
    except TaskEventBatchValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc
    except TaskEventConflictError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc


@router.get("", response_model=list[TaskEvent])
def get_events(
    request: Request,
    from_at: datetime | None = Query(default=None, alias="from"),
    to_at: datetime | None = Query(default=None, alias="to"),
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    return list_task_events(
        _db_path(request),
        user_id,
        from_at.isoformat() if from_at else None,
        to_at.isoformat() if to_at else None,
    )
