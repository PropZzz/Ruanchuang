from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, Request

from .auth import current_user_id
from .repositories import user_diagnostics
from .schemas import DiagnosticsOut, ServerTimeOut, VersionOut


router = APIRouter(tags=["platform"])


@router.get("/version", response_model=VersionOut)
def version(user_id: str = Depends(current_user_id)) -> dict[str, str]:
    del user_id
    return {"apiVersion": "0.1.0", "clientCompatibility": "0.1.x"}


@router.get("/server/time", response_model=ServerTimeOut)
def server_time(user_id: str = Depends(current_user_id)) -> dict[str, object]:
    del user_id
    now = datetime.now(timezone.utc)
    return {
        "serverTime": now,
        "unixMillis": int(now.timestamp() * 1000),
        "timezone": "UTC",
    }


@router.get("/diagnostics/summary", response_model=DiagnosticsOut)
def diagnostics(request: Request, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    return user_diagnostics(getattr(request.app.state, "db_path", None), user_id)
