from __future__ import annotations

from datetime import date, datetime, timedelta

from fastapi import APIRouter, Depends, Query, Request

from .auth import current_user_id
from .repositories import (
    get_scheduling_tuning,
    list_task_events,
    set_scheduling_tuning,
)
from .schemas import (
    MonthReviewReport,
    ReviewReport,
    SchedulingTuning,
    TaskEvent,
    TuningApplyRequest,
)
from .services_review import monthly_report, weekly_report


router = APIRouter(prefix="/review", tags=["review"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


@router.get("/weekly", response_model=ReviewReport)
def get_weekly_review(
    request: Request,
    week_start: date = Query(alias="week_start"),
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    start = datetime(week_start.year, week_start.month, week_start.day)
    end = start + timedelta(days=7)
    events = list_task_events(_db_path(request), user_id, start.isoformat(), end.isoformat())
    current_tuning = get_scheduling_tuning(_db_path(request), user_id)
    report = weekly_report(week_start, events, current_tuning)
    set_scheduling_tuning(_db_path(request), user_id, report["tuning"])
    return report


@router.get("/monthly", response_model=MonthReviewReport)
def get_monthly_review(
    request: Request,
    month: str = Query(),
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    parsed = datetime.strptime(month, "%Y-%m").date()
    events = list_task_events(_db_path(request), user_id)
    return monthly_report(parsed, events)


@router.get("/rescue-history", response_model=list[TaskEvent])
def get_rescue_history(
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
    rescue_events = [
        event
        for event in events
        if isinstance(event.get("reason"), str)
        and (
            str(event["reason"]).startswith("rescue_accept:")
            or str(event["reason"]).startswith("rescue_undo:")
        )
    ]
    return sorted(rescue_events, key=lambda event: str(event.get("at") or ""), reverse=True)


@router.get("/tuning", response_model=SchedulingTuning)
def get_review_tuning(
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return get_scheduling_tuning(_db_path(request), user_id)


@router.put("/tuning", response_model=SchedulingTuning)
def put_review_tuning(
    payload: SchedulingTuning,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return set_scheduling_tuning(_db_path(request), user_id, payload.model_dump(mode="json", by_alias=True))


@router.post("/tuning/apply", response_model=SchedulingTuning)
def apply_review_tuning(
    payload: TuningApplyRequest,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return set_scheduling_tuning(
        _db_path(request),
        user_id,
        payload.tuning.model_dump(mode="json", by_alias=True),
    )
