from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response, status
from fastapi.responses import PlainTextResponse

from .auth import current_user_id
from .repositories import (
    RepositoryConflictError,
    RepositoryNotFoundError,
    delete_schedule,
    list_rescue_snapshots,
    list_schedules,
    replace_schedules_with_snapshot,
    schedule_baseline_hash,
    undo_schedule_snapshot,
    upsert_schedule,
    upsert_schedules_batch,
)
from .schemas import (
    RescueApplyRequest,
    RescueOptionsOut,
    RescueOptionsRequest,
    RescueSnapshotOut,
    RescueUndoRequest,
    ScheduleConflictsOut,
    ScheduleEntryIn,
    ScheduleEntryOut,
    ScheduleImportRequest,
    SchedulingPlanOut,
    SchedulingRequest,
)
from .services_ics import IcsValidationError, export_ics, parse_ics
from .services_rescue import build_rescue_options
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


@router.post("/batch", response_model=list[ScheduleEntryOut])
def batch_schedule(
    payload: list[ScheduleEntryIn],
    request: Request,
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    return upsert_schedules_batch(_db_path(request), user_id, [item.model_dump(mode="json", by_alias=True) for item in payload])


@router.get("/conflicts", response_model=ScheduleConflictsOut)
def schedule_conflicts(
    request: Request,
    day: date | None = Query(default=None),
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    entries = list_schedules(_db_path(request), user_id)
    if day is not None:
        entries = [entry for entry in entries if entry.get("day") == day.isoformat()]
    conflicts: list[dict[str, object]] = []
    for index, left in enumerate(entries):
        left_start = int((left.get("time") or {}).get("hour", 0)) * 60 + int((left.get("time") or {}).get("minute", 0))
        left_end = left_start + max(1, round(float(left.get("height") or 60) / 80 * 60))
        for right in entries[index + 1 :]:
            right_start = int((right.get("time") or {}).get("hour", 0)) * 60 + int((right.get("time") or {}).get("minute", 0))
            right_end = right_start + max(1, round(float(right.get("height") or 60) / 80 * 60))
            if left_start < right_end and right_start < left_end:
                conflicts.append({"entryIds": [left["id"], right["id"]], "start": max(left_start, right_start), "end": min(left_end, right_end)})
    return {"baselineHash": schedule_baseline_hash(_db_path(request), user_id), "conflicts": conflicts}


@router.post("/import-ics", response_model=list[ScheduleEntryOut])
def import_ics(
    payload: ScheduleImportRequest,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    try:
        entries = parse_ics(payload.ics)
    except IcsValidationError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc
    return upsert_schedules_batch(_db_path(request), user_id, entries)


@router.get("/export-ics", response_class=PlainTextResponse)
def export_schedule_ics(
    request: Request,
    from_date: date | None = Query(default=None, alias="from"),
    to_date: date | None = Query(default=None, alias="to"),
    user_id: str = Depends(current_user_id),
) -> PlainTextResponse:
    entries = list_schedules(_db_path(request), user_id)
    if from_date is not None:
        entries = [entry for entry in entries if str(entry.get("day") or "") >= from_date.isoformat()]
    if to_date is not None:
        entries = [entry for entry in entries if str(entry.get("day") or "") <= to_date.isoformat()]
    return PlainTextResponse(export_ics(entries), media_type="text/calendar")


@router.post("/rescue/options", response_model=RescueOptionsOut)
def rescue_options(
    payload: RescueOptionsRequest,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return {
        "baselineHash": schedule_baseline_hash(_db_path(request), user_id),
        "options": build_rescue_options(payload.model_dump(mode="json", by_alias=True)),
    }


@router.post("/rescue/apply", response_model=RescueSnapshotOut)
def rescue_apply(
    payload: RescueApplyRequest,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return replace_schedules_with_snapshot(
            _db_path(request),
            user_id,
            [item.model_dump(mode="json", by_alias=True) for item in payload.before],
            [item.model_dump(mode="json", by_alias=True) for item in payload.after],
            payload.strategy,
            payload.baseline_hash,
        )
    except RepositoryConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc


@router.post("/rescue/undo", response_model=RescueSnapshotOut)
def rescue_undo(
    payload: RescueUndoRequest,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    try:
        return undo_schedule_snapshot(_db_path(request), user_id, payload.snapshot_id)
    except RepositoryConflictError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except RepositoryNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc


@router.get("/rescue/history", response_model=list[dict[str, object]])
def rescue_history(
    request: Request,
    user_id: str = Depends(current_user_id),
) -> list[dict[str, object]]:
    return list_rescue_snapshots(_db_path(request), user_id)
