from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, status

from .auth import current_user_id
from .repositories import RepositoryValidationError, get_user_settings, update_user_settings
from .schemas import UserSettingsOut, UserSettingsUpdate


router = APIRouter(prefix="/settings", tags=["settings"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


@router.get("", response_model=UserSettingsOut)
def read_settings(request: Request, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    return get_user_settings(_db_path(request), user_id)


@router.put("", response_model=UserSettingsOut)
def write_settings(
    payload: UserSettingsUpdate,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return update_user_settings(
            _db_path(request),
            user_id,
            payload.model_dump(mode="json", by_alias=True, exclude_unset=True),
        )
    except RepositoryValidationError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc
