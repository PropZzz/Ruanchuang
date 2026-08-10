from __future__ import annotations

from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status

from .auth import current_user_id
from .repositories import (
    RepositoryConflictError,
    default_emotion_status,
    get_current_emotion,
    get_current_energy,
    get_energy_profile,
    get_latest_emotion_for_day,
    list_emotion_checkins,
    upsert_emotion_checkin,
    upsert_energy_sample,
)
from .schemas import (
    CareAlertOut,
    EmotionCheckIn,
    EmotionStatusOut,
    EnergyProfileOut,
    EnergySample,
    EnergyStatusOut,
)


router = APIRouter(tags=["emotion-energy"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


@router.get("/emotion/current", response_model=EmotionStatusOut)
def current_emotion(
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return get_current_emotion(_db_path(request), user_id)


@router.post("/emotion/checkins", response_model=EmotionCheckIn)
def create_emotion_checkin(
    payload: EmotionCheckIn,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return upsert_emotion_checkin(
            _db_path(request),
            user_id,
            payload.model_dump(mode="json", by_alias=True),
        )
    except RepositoryConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc


@router.get("/emotion/checkins", response_model=list[EmotionCheckIn])
def get_emotion_checkins(
    request: Request,
    day: date = Query(...),
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    return list_emotion_checkins(_db_path(request), user_id, day.isoformat())


@router.get("/emotion/care-alert", response_model=CareAlertOut)
def care_alert(
    request: Request,
    day: date | None = Query(default=None),
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    target_day = day or date.today()
    today = get_latest_emotion_for_day(_db_path(request), user_id, target_day.isoformat())
    yesterday = get_latest_emotion_for_day(
        _db_path(request),
        user_id,
        (target_day - timedelta(days=1)).isoformat(),
    )
    low_states = {"tired", "irritable"}
    active = (
        today is not None
        and yesterday is not None
        and today.get("state") in low_states
        and yesterday.get("state") in low_states
    )
    if not active:
        return {
            "active": False,
            "severity": "none",
            "message": "No continuous low-emotion pattern detected.",
        }
    return {
        "active": True,
        "severity": "gentle",
        "message": "Continuous low emotion detected; consider adding a recovery buffer today.",
    }


@router.get("/energy/current", response_model=EnergyStatusOut)
def current_energy(
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return get_current_energy(_db_path(request), user_id)


@router.post("/energy/samples", response_model=EnergySample)
def create_energy_sample(
    payload: EnergySample,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return upsert_energy_sample(
            _db_path(request),
            user_id,
            payload.model_dump(mode="json", by_alias=True),
        )
    except RepositoryConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc


@router.get("/energy/profile", response_model=EnergyProfileOut)
def energy_profile(
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return get_energy_profile(_db_path(request), user_id)
