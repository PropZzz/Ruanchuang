from __future__ import annotations

from datetime import date, datetime, timedelta


def _parse_at(value: object) -> datetime:
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        return datetime.fromisoformat(value)
    return datetime.min


def _event_int(event: dict[str, object], key: str, default: int = 0) -> int:
    value = event.get(key)
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    return default


def _empty_buckets() -> dict[str, int]:
    return {
        "<=15": 0,
        "16-30": 0,
        "31-60": 0,
        "61-120": 0,
        "121+": 0,
    }


def _bucket_actual_minutes(buckets: dict[str, int], actual: int) -> None:
    if actual <= 15:
        buckets["<=15"] += 1
    elif actual <= 30:
        buckets["16-30"] += 1
    elif actual <= 60:
        buckets["31-60"] += 1
    elif actual <= 120:
        buckets["61-120"] += 1
    else:
        buckets["121+"] += 1


def weekly_report(
    week_start: date,
    events: list[dict[str, object]],
    current_tuning: dict[str, object],
) -> dict[str, object]:
    start = datetime(week_start.year, week_start.month, week_start.day)
    end = start + timedelta(days=7)
    in_range = [
        event
        for event in events
        if start <= _parse_at(event.get("at")) < end
    ]

    started: dict[str, dict[str, object]] = {}
    completed: dict[str, dict[str, object]] = {}
    postpones: dict[str, list[dict[str, object]]] = {}

    for event in in_range:
        task_id = str(event.get("taskId") or "")
        if event.get("type") == "start":
            started[task_id] = event
        elif event.get("type") == "complete":
            completed[task_id] = event
        elif event.get("type") == "postpone":
            postpones.setdefault(task_id, []).append(event)

    planned_total = 0
    actual_total = 0
    buckets = _empty_buckets()
    attribution = {
        "underestimated": 0,
        "interruptions": 0,
        "context_switch": 0,
        "unknown": 0,
    }
    tag_under: dict[str, int] = {}
    tag_total: dict[str, int] = {}

    for task_id, start_event in started.items():
        complete_event = completed.get(task_id)
        planned = _event_int(start_event, "plannedMinutes")
        planned_total += planned
        if complete_event is None:
            continue

        actual = _event_int(complete_event, "actualMinutes", planned)
        actual_total += actual
        tag = str(start_event.get("tag") or "")
        tag_total[tag] = tag_total.get(tag, 0) + 1
        _bucket_actual_minutes(buckets, actual)

        interrupts = _event_int(complete_event, "interruptions")
        post_count = len(postpones.get(task_id, []))
        underestimated = planned > 0 and actual > planned * 1.3
        if interrupts >= 3:
            attribution["interruptions"] += 1
        elif underestimated:
            attribution["underestimated"] += 1
            tag_under[tag] = tag_under.get(tag, 0) + 1
        elif post_count >= 2:
            attribution["context_switch"] += 1
        else:
            attribution["unknown"] += 1

    started_count = len(started)
    completed_count = len(completed)
    completion_rate = 0.0 if started_count == 0 else completed_count / started_count

    tag_multipliers = dict(current_tuning.get("tagDurationMultiplier") or {})
    suggestions: list[str] = []
    for tag, total in tag_total.items():
        under = tag_under.get(tag, 0)
        if total >= 2 and under / total >= 0.4:
            current = float(tag_multipliers.get(tag) or current_tuning.get("defaultDurationMultiplier") or 1.0)
            tag_multipliers[tag] = min(1.8, max(1.0, current + 0.15))
            suggestions.append(f"建议为“{tag}”类任务上调时长预估（+15%）。")

    high_load_penalty = float(current_tuning.get("highLoadPenaltyWhenLowEnergy") or 1.0)
    low_high_total = 0
    low_high_strained = 0
    for task_id, start_event in started.items():
        if start_event.get("energy") not in {"low", "veryLow"}:
            continue
        if start_event.get("load") != "high":
            continue
        low_high_total += 1
        complete_event = completed.get(task_id)
        if complete_event is None:
            low_high_strained += 1
            continue
        planned = _event_int(start_event, "plannedMinutes")
        actual = _event_int(complete_event, "actualMinutes", planned)
        strained = (
            (planned > 0 and actual > planned * 1.3)
            or _event_int(complete_event, "interruptions") >= 3
            or len(postpones.get(task_id, [])) >= 2
        )
        if strained:
            low_high_strained += 1

    if low_high_total >= 3:
        strain_rate = low_high_strained / low_high_total
        if strain_rate >= 0.5:
            high_load_penalty = min(3.0, max(1.0, high_load_penalty + 0.2))
            suggestions.append("检测到低能量状态下的高负荷压力，建议将低能量时的高负荷惩罚提高 0.2。")
        elif strain_rate <= 0.2 and high_load_penalty > 1.0:
            high_load_penalty = min(3.0, max(1.0, high_load_penalty - 0.1))

    if attribution["interruptions"] >= 3:
        suggestions.append("本周打断较多，建议批量处理通知，并将任务切分为更短的块。")
    if completion_rate < 0.6 and started_count >= 5:
        suggestions.append("完成率偏低，建议降低每日负荷，或预留缓冲时间应对打断。")

    tuning = {
        "defaultDurationMultiplier": float(current_tuning.get("defaultDurationMultiplier") or 1.0),
        "tagDurationMultiplier": tag_multipliers,
        "highLoadPenaltyWhenLowEnergy": high_load_penalty,
    }

    return {
        "weekStart": start.isoformat(),
        "weekEnd": end.isoformat(),
        "startedCount": started_count,
        "completedCount": completed_count,
        "completionRate": completion_rate,
        "plannedMinutesTotal": planned_total,
        "actualMinutesTotal": actual_total,
        "actualDurationBuckets": buckets,
        "delayAttribution": attribution,
        "suggestions": suggestions,
        "tuning": tuning,
    }


def monthly_report(month_start: date, events: list[dict[str, object]]) -> dict[str, object]:
    start = date(month_start.year, month_start.month, 1)
    end = date(start.year + (1 if start.month == 12 else 0), 1 if start.month == 12 else start.month + 1, 1)
    start_dt = datetime(start.year, start.month, start.day)
    end_dt = datetime(end.year, end.month, end.day)
    in_range = [
        event
        for event in events
        if start_dt <= _parse_at(event.get("at")) < end_dt
    ]

    started: dict[str, dict[str, object]] = {}
    completed: dict[str, dict[str, object]] = {}
    postpones: dict[str, list[dict[str, object]]] = {}
    for event in in_range:
        task_id = str(event.get("taskId") or "")
        if event.get("type") == "start":
            started[task_id] = event
        elif event.get("type") == "complete":
            completed[task_id] = event
        elif event.get("type") == "postpone":
            postpones.setdefault(task_id, []).append(event)

    planned_total = 0
    actual_total = 0
    buckets = _empty_buckets()
    bottlenecks = {
        "underestimated": 0,
        "interruptions": 0,
        "context_switch": 0,
        "carry_over": 0,
    }
    by_day_started: dict[date, int] = {}
    by_day_completed: dict[date, int] = {}
    by_day_planned: dict[date, int] = {}
    by_day_actual: dict[date, int] = {}
    by_week_started: dict[date, int] = {}
    by_week_completed: dict[date, int] = {}

    def week_of(value: datetime) -> date:
        day = value.date()
        return day - timedelta(days=day.weekday())

    for task_id, start_event in started.items():
        start_at = _parse_at(start_event.get("at"))
        day = start_at.date()
        week = week_of(start_at)
        by_day_started[day] = by_day_started.get(day, 0) + 1
        by_week_started[week] = by_week_started.get(week, 0) + 1
        planned = _event_int(start_event, "plannedMinutes")
        planned_total += planned
        by_day_planned[day] = by_day_planned.get(day, 0) + planned

        complete_event = completed.get(task_id)
        if complete_event is None:
            bottlenecks["carry_over"] += 1
            continue

        actual = _event_int(complete_event, "actualMinutes", planned)
        actual_total += actual
        by_day_actual[day] = by_day_actual.get(day, 0) + actual
        by_day_completed[day] = by_day_completed.get(day, 0) + 1
        by_week_completed[week] = by_week_completed.get(week, 0) + 1
        _bucket_actual_minutes(buckets, actual)

        interrupts = _event_int(complete_event, "interruptions")
        underestimated = planned > 0 and actual > planned * 1.3
        if interrupts >= 3:
            bottlenecks["interruptions"] += 1
        elif underestimated:
            bottlenecks["underestimated"] += 1
        elif len(postpones.get(task_id, [])) >= 2:
            bottlenecks["context_switch"] += 1

    started_count = len(started)
    completed_count = len(completed)
    completion_rate = 0.0 if started_count == 0 else completed_count / started_count
    daily_trend = []
    day = start
    while day < end:
        daily_trend.append(
            {
                "day": day.isoformat(),
                "started": by_day_started.get(day, 0),
                "completed": by_day_completed.get(day, 0),
                "plannedMinutes": by_day_planned.get(day, 0),
                "actualMinutes": by_day_actual.get(day, 0),
            }
        )
        day += timedelta(days=1)

    weekly_completion_rate = {}
    for week in sorted(by_week_started):
        total = by_week_started[week]
        weekly_completion_rate[f"{week.month}/{week.day}"] = 0.0 if total == 0 else by_week_completed.get(week, 0) / total

    suggestions = []
    if bottlenecks["interruptions"] >= 4:
        suggestions.append("打断是本月最主要的瓶颈，建议批量处理通知并预留专注窗口。")
    if bottlenecks["underestimated"] >= 4:
        suggestions.append("检测到多次低估时长，建议将同类任务的默认预估上调 15% - 20%。")
    if bottlenecks["context_switch"] >= 4:
        suggestions.append("上下文切换偏多，建议将相似任务归类到专门的执行窗口中。")
    if bottlenecks["carry_over"] >= 4:
        suggestions.append("有较多任务被顺延，建议降低每日在制任务量，并增加一个保护性缓冲槽。")
    if completion_rate < 0.65 and started_count >= 12:
        suggestions.append("月度完成率偏低，建议先收缩每周承诺，再新增任务。")

    return {
        "monthStart": start.isoformat(),
        "monthEnd": end.isoformat(),
        "startedCount": started_count,
        "completedCount": completed_count,
        "completionRate": completion_rate,
        "plannedMinutesTotal": planned_total,
        "actualMinutesTotal": actual_total,
        "actualDurationBuckets": buckets,
        "bottleneckAttribution": bottlenecks,
        "weeklyCompletionRate": weekly_completion_rate,
        "dailyTrend": daily_trend,
        "suggestions": suggestions,
    }
