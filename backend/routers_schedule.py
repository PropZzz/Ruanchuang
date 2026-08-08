from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status

from .auth import current_user_id
from .repositories import delete_schedule, list_schedules, upsert_schedule
from .schemas import ScheduleEntryIn, ScheduleEntryOut, SchedulingPlanOut, SchedulingRequest
from .services_scheduling import plan_schedule


router = APIRouter(prefix="/schedule", tags=["schedule"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


def _date_filter(value: object | None) -> str | None:
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


@router.get("", response_model=list[ScheduleEntryOut])
def get_schedule(
    request: Request,
    user_id: str = Depends(current_user_id),
    from_date: date | None = Query(default=None, alias="from"),
    to_date: date | None = Query(default=None, alias="to"),
) -> list[dict[str, object]]:
    items = list_schedules(_db_path(request), user_id)
    from_iso = _date_filter(from_date)
    to_iso = _date_filter(to_date)
    if from_iso is None and to_iso is None:
        return items

    filtered: list[dict[str, object]] = []
    for item in items:
        day = item.get("day")
        if day is not None and not isinstance(day, str):
            day = str(day)
        if day is None:
            continue
        if from_iso is not None and day < from_iso:
            continue
        if to_iso is not None and day > to_iso:
            continue
        filtered.append(item)
    return filtered


@router.post("", response_model=ScheduleEntryOut)
def create_schedule(
    payload: ScheduleEntryIn,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return upsert_schedule(_db_path(request), user_id, payload.model_dump(mode="json", by_alias=True))


@router.put("/{entry_id}", response_model=ScheduleEntryOut)
def update_schedule(
    entry_id: str,
    payload: ScheduleEntryIn,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    data = payload.model_dump(mode="json", by_alias=True)
    data["id"] = entry_id
    return upsert_schedule(_db_path(request), user_id, data)


@router.delete("/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_schedule(
    entry_id: str,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> Response:
    delete_schedule(_db_path(request), user_id, entry_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/replan", response_model=SchedulingPlanOut)
def replan(payload: SchedulingRequest, user_id: str = Depends(current_user_id)) -> dict[str, object]:
    return plan_schedule(payload.model_dump(mode="json", by_alias=True))
