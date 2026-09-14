"""Remote schedule-rescue routes: options / apply / undo / history.

Contract: docs/接口预留与服务器接口文档.md (日程救援接口) and
docs/后端开发守则.md 4.2. Errors use the unified `{code, message}` detail
shape; 4xx must never be swallowed by clients into local fallback.
"""

from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from .auth import current_user_id
from .repositories import (
    RepositoryConflictError,
    RepositoryNotFoundError,
    RepositoryValidationError,
    TaskEventConflictError,
    apply_rescue,
    list_task_events,
    undo_rescue,
)
from .schemas import (
    RescueApplyOut,
    RescueApplyRequest,
    RescueOptionsOut,
    RescueOptionsRequest,
    RescueUndoOut,
    RescueUndoRequest,
    TaskEvent,
)
from .services_rescue import build_options, build_rescue_event, filter_rescue_events


router = APIRouter(prefix="/schedule", tags=["schedule"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


def _error(status_code: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status_code, detail={"code": code, "message": message})


@router.post("/rescue/options", response_model=RescueOptionsOut)
def rescue_options(
    payload: RescueOptionsRequest,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    del user_id  # options are pure computation, but the route requires auth
    return build_options(payload.model_dump(mode="json", by_alias=True))


@router.post("/rescue/apply", response_model=RescueApplyOut)
def rescue_apply(
    payload: RescueApplyRequest,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    urgent = (
        payload.urgent_task.model_dump(mode="json", by_alias=True)
        if payload.urgent_task is not None
        else None
    )
    event_payload = build_rescue_event(urgent, payload.event_id, payload.energy)
    try:
        return apply_rescue(
            _db_path(request),
            user_id,
            payload.day.isoformat(),
            payload.strategy,
            payload.baseline_hash,
            [entry.model_dump(mode="json", by_alias=True) for entry in payload.after],
            event_payload,
            urgent,
        )
    except RepositoryConflictError as exc:
        raise _error(status.HTTP_409_CONFLICT, "CONFLICT", str(exc)) from exc
    except TaskEventConflictError as exc:
        raise _error(status.HTTP_409_CONFLICT, "CONFLICT", str(exc)) from exc
    except RepositoryValidationError as exc:
        raise _error(status.HTTP_422_UNPROCESSABLE_ENTITY, "VALIDATION_ERROR", str(exc)) from exc


@router.post("/rescue/undo", response_model=RescueUndoOut)
def rescue_undo(
    payload: RescueUndoRequest,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return undo_rescue(
            _db_path(request),
            user_id,
            payload.snapshot_id,
            payload.event_id,
        )
    except RepositoryNotFoundError as exc:
        raise _error(status.HTTP_404_NOT_FOUND, "NOT_FOUND", str(exc)) from exc
    except RepositoryConflictError as exc:
        raise _error(status.HTTP_409_CONFLICT, "CONFLICT", str(exc)) from exc
    except TaskEventConflictError as exc:
        raise _error(status.HTTP_409_CONFLICT, "CONFLICT", str(exc)) from exc


@router.get("/rescue/history", response_model=list[TaskEvent])
def rescue_history(
    request: Request,
    from_at: datetime | None = Query(default=None, alias="from"),
    to_at: datetime | None = Query(default=None, alias="to"),
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    events = list_task_events(
        _db_path(request),
        user_id,
        from_at.isoformat() if from_at else None,
        to_at.isoformat() if to_at else None,
    )
    return sorted(
        filter_rescue_events(events),
        key=lambda event: str(event.get("at") or ""),
        reverse=True,
    )
