from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from .auth import current_user_id
from .repositories import RepositoryValidationError, pull_sync_changes, push_sync_changes, sync_status
from .schemas import SyncPushRequest


router = APIRouter(prefix="/sync", tags=["sync"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


@router.get("/status")
def get_sync_status(request: Request, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    return sync_status(_db_path(request), user_id)


@router.get("/pull")
def pull(request: Request, since: int = Query(default=0, ge=0), user_id: str = Depends(current_user_id)) -> dict[str, object]:
    try:
        return pull_sync_changes(_db_path(request), user_id, since)
    except RepositoryValidationError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc


@router.post("/push")
def push(payload: SyncPushRequest, request: Request, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    try:
        return push_sync_changes(_db_path(request), user_id, [change.model_dump(mode="json", by_alias=True) for change in payload.changes])
    except RepositoryValidationError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc
