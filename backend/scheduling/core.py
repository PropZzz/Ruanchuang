from __future__ import annotations

from datetime import date, datetime
from typing import Any


_EXPLANATION_CODE_ORDER = (
    "deadline_proximity",
    "priority",
    "energy_fit",
    "kept_baseline",
    "fixed_conflict",
)


def _ordered_explanation_codes(codes: object) -> list[str]:
    if not isinstance(codes, list):
        return []
    values = {str(code) for code in codes}
    return [code for code in _EXPLANATION_CODE_ORDER if code in values]


def _time_to_minutes(value: object) -> int:
    if isinstance(value, dict):
        hour = int(value.get("hour", 0) or 0)
        minute = int(value.get("minute", 0) or 0)
        return hour * 60 + minute
    return 0


def _minutes_to_time(minutes: int) -> dict[str, int]:
    minutes = max(0, min(24 * 60 - 1, minutes))
    return {"hour": minutes // 60, "minute": minutes % 60}


def _parse_day(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        return text.split("T", 1)[0]
    return None


def _parse_datetime(value: object | None) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        try:
            if text.endswith("Z"):
                text = text[:-1] + "+00:00"
            return datetime.fromisoformat(text)
        except ValueError:
            return None
    return None


def _duration_from_height(height: float) -> int:
    return max(1, min(24 * 60, round((height / 80.0) * 60.0)))


def _height_from_duration(minutes: int) -> float:
    return round((minutes / 60.0) * 80.0, 2)


def _load_penalty(load: object, energy: object, tuning: dict[str, Any]) -> float:
    if energy not in {"low", "veryLow"}:
        return 1.0
    if load == "high":
        return float(tuning.get("highLoadPenaltyWhenLowEnergy") or 1.2)
    if load == "medium":
        return 1.05
    return 1.0


def _task_duration(task: dict[str, Any], energy: object, tuning: dict[str, Any]) -> int:
    duration = int(task.get("durationMinutes") or 0)
    if duration <= 0:
        duration = 15

    load = task.get("load")
    tag = str(task.get("tag") or "")
    multipliers = tuning.get("tagDurationMultiplier") if isinstance(tuning, dict) else {}
    tag_multiplier = 1.0
    if isinstance(multipliers, dict):
        raw = multipliers.get(tag)
        if isinstance(raw, (int, float)):
            tag_multiplier = float(raw)

    base = duration * float(tuning.get("defaultDurationMultiplier") or 1.0)
    base *= tag_multiplier
    base *= _load_penalty(load, energy, tuning)
    return max(1, round(base))


def _task_priority(task: dict[str, Any], current_day: str | None) -> tuple:
    priority = int(task.get("priority") or 3)
    duration = max(1, int(task.get("durationMinutes") or 15))
    due = _parse_datetime(task.get("due"))
    due_rank = 2
    due_minutes = 10**9
    if due is not None:
        if current_day is not None and due.date().isoformat() == current_day:
            due_rank = 0
            due_minutes = due.hour * 60 + due.minute
        else:
            due_rank = 1
            due_minutes = int(due.timestamp() // 60)
    return (due_rank, due_minutes, -priority, -duration, str(task.get("id") or ""))


def _task_id(task: dict[str, Any], index: int) -> str:
    return str(task.get("id") or f"plan_{index}")


def _explanation_codes(task: dict[str, Any], energy: object) -> list[str]:
    codes = ["deadline_proximity"] if task.get("due") else []
    codes.append("priority")
    target_load = {
        "veryLow": "low",
        "low": "low",
        "medium": "medium",
        "high": "high",
        "veryHigh": "high",
    }.get(str(energy))
    if target_load is not None and task.get("load") == target_load:
        codes.append("energy_fit")
    return _ordered_explanation_codes(codes)


def _due_minutes_for_day(task: dict[str, Any], current_day: str | None) -> int | None:
    due = _parse_datetime(task.get("due"))
    if due is None or current_day is None:
        return None
    if due.date().isoformat() == current_day:
        return due.hour * 60 + due.minute
    if due.date().isoformat() < current_day:
        return -1
    return None


def _pick_slot(
    free: list[tuple[int, int]],
    duration: int,
    earliest_start: int | None,
    due_minutes: int | None,
    hard_deadline: bool,
) -> int | None:
    def first_candidate() -> int | None:
        for start, end in free:
            candidate = max(start, earliest_start if earliest_start is not None else start)
            if candidate + duration <= end:
                return candidate
        return None

    for start, end in free:
        candidate = max(start, earliest_start if earliest_start is not None else start)
        if candidate + duration > end:
            continue
        if due_minutes is not None and (due_minutes < 0 or candidate + duration > due_minutes):
            continue
        return candidate
    if hard_deadline and due_minutes is not None:
        return None
    return first_candidate()


def _merge_busy(blocks: list[tuple[int, int]]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for start, end in sorted(blocks):
        if end <= start:
            continue
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def _subtract(window: tuple[int, int], busy: list[tuple[int, int]]) -> list[tuple[int, int]]:
    free: list[tuple[int, int]] = []
    cursor = window[0]
    for start, end in busy:
        if end <= cursor:
            continue
        if start >= window[1]:
            break
        start = max(start, window[0])
        end = min(end, window[1])
        if start > cursor:
            free.append((cursor, start))
        cursor = max(cursor, end)
    if cursor < window[1]:
        free.append((cursor, window[1]))
    return free


def _consume_interval(intervals: list[tuple[int, int]], used: tuple[int, int]) -> None:
    remaining: list[tuple[int, int]] = []
    for interval in intervals:
        remaining.extend(_subtract(interval, [used]))
    intervals[:] = remaining


def _palette(load: object) -> int:
    palette = {
        "high": 0xFFB42318,
        "medium": 0xFF0F766E,
        "low": 0xFF2563EB,
    }
    return palette.get(str(load or ""), 0xFF334155)


def _next_chunk_duration(remaining: int, minimum_chunk: int, slots: list[tuple[int, int]]) -> int | None:
    if any(end - start >= remaining for start, end in slots):
        return remaining
    largest = max((end - start for start, end in slots), default=0)
    if largest < minimum_chunk:
        return None
    candidate = min(remaining, largest)
    remainder = remaining - candidate
    if 0 < remainder < minimum_chunk:
        candidate = remaining - minimum_chunk
    if candidate < minimum_chunk or candidate > largest:
        return None
    return candidate


def _plan_schedule(request: dict[str, Any]) -> dict[str, Any]:
    day = _parse_day(request.get("day"))
    windows_raw = request.get("windows") or []
    fixed_raw = request.get("fixed") or []
    tasks_raw = request.get("tasks") or []
    energy = request.get("energy") or "medium"
    tuning = request.get("tuning") or {}

    busy_blocks: list[tuple[int, int]] = []
    fixed_entries: list[dict[str, Any]] = []
    fixed_blocks: list[tuple[int, int]] = []
    for entry in fixed_raw:
        if not isinstance(entry, dict):
            continue
        start = _time_to_minutes(entry.get("time"))
        duration = int(entry.get("durationMinutes") or entry.get("minutes") or _duration_from_height(float(entry.get("height") or 80.0)))
        fixed_blocks.append((start, start + max(1, duration)))
        fixed_entries.append(entry)

    supplied_windows: list[tuple[int, int]] = []
    for window in windows_raw:
        if not isinstance(window, dict):
            continue
        start = _time_to_minutes(window.get("start"))
        end = _time_to_minutes(window.get("end"))
        if end > start:
            supplied_windows.append((start, end))

    fixed_conflicts: set[int] = set()
    for index, (start, end) in enumerate(fixed_blocks):
        if not any(window_start <= start and end <= window_end for window_start, window_end in supplied_windows):
            fixed_conflicts.add(index)
        for other_index, (other_start, other_end) in enumerate(fixed_blocks):
            if index != other_index and start < other_end and other_start < end:
                fixed_conflicts.add(index)

    # A conflicting fixed entry remains immutable and continues to occupy time;
    # diagnostics must not make ordinary tasks overlap it.
    busy_blocks.extend(fixed_blocks)

    slots: list[tuple[int, int]] = []
    for start, end in supplied_windows:
        slots.extend(_subtract((start, end), _merge_busy(busy_blocks)))

    tasks = [task for task in tasks_raw if isinstance(task, dict)]
    tasks.sort(key=lambda task: _task_priority(task, day))

    entries: list[dict[str, Any]] = []
    issues: list[dict[str, Any]] = []
    for index in sorted(fixed_conflicts):
        fixed_id = _task_id(fixed_entries[index], index)
        issues.append(
            {
                "code": "fixed_conflict",
                "message": "Fixed entry overlaps another fixed entry or lies outside every work window",
                "taskId": fixed_id,
                "explanationCodes": ["fixed_conflict"],
                "hard": True,
            }
        )
    fixed_ids = {_task_id(entry, index) for index, entry in enumerate(fixed_entries)}
    task_by_id = {_task_id(task, index): task for index, task in enumerate(tasks)}
    pending = list(enumerate(tasks))
    placed_ids = set(fixed_ids)
    failed_ids: set[str] = set()
    while pending:
        progressed = False
        next_pending: list[tuple[int, dict[str, Any]]] = []
        for index, task in pending:
            task_id = _task_id(task, index)
            if task_id in fixed_ids:
                progressed = True
                continue
            dependencies = [str(dep) for dep in (task.get("dependsOn") or [])]
            blocked_by = [dep for dep in dependencies if dep not in placed_ids]
            unknown = [dep for dep in blocked_by if dep not in task_by_id and dep not in fixed_ids]
            failed = [dep for dep in blocked_by if dep in failed_ids]
            if unknown or failed:
                issues.append(
                    {
                        "code": "dependency_blocked",
                        "message": "Task cannot be scheduled until its dependency is placed",
                        "taskId": task_id,
                        "blockedBy": blocked_by,
                        "explanationCodes": [],
                    }
                )
                failed_ids.add(task_id)
                progressed = True
                continue
            if blocked_by:
                next_pending.append((index, task))
                continue

            duration = _task_duration(task, energy, tuning)
            splittable = bool(task.get("splittable"))
            minimum_chunk = int(task.get("minimumChunkMinutes") or 15)
            earliest = _parse_datetime(task.get("earliestStart"))
            earliest_minutes = None
            if earliest is not None and day is not None:
                if earliest.date().isoformat() > day:
                    earliest_minutes = 24 * 60
                elif earliest.date().isoformat() == day:
                    earliest_minutes = earliest.hour * 60 + earliest.minute
            due_minutes = _due_minutes_for_day(task, day)
            slots_before_task = list(slots)
            chunks: list[tuple[int, int]] = []
            remaining = duration
            while remaining > 0:
                chunk_duration = (
                    _next_chunk_duration(remaining, minimum_chunk, slots)
                    if splittable
                    else remaining
                )
                if chunk_duration is None:
                    break
                start = _pick_slot(
                    slots,
                    chunk_duration,
                    earliest_minutes,
                    due_minutes,
                    bool(task.get("hardDeadline")),
                )
                if start is None:
                    break
                chunks.append((start, chunk_duration))
                _consume_interval(slots, (start, start + chunk_duration))
                remaining -= chunk_duration

            if remaining > 0:
                slots[:] = slots_before_task
                issue_code = "no_slot"
                issue = {
                    "code": issue_code,
                    "message": f"No time slot left for task: {task.get('title', '')}",
                    "taskId": task_id,
                    "explanationCodes": ["deadline_proximity"] if task.get("due") else [],
                    "hard": bool(task.get("hardDeadline")),
                }
                issues.append(issue)
                if due_minutes is not None and due_minutes < 0:
                    issues.append(
                        {
                            "code": "overdue",
                            "message": f"Task due before the requested day: {task.get('title', '')}",
                            "taskId": task_id,
                            "explanationCodes": ["deadline_proximity"],
                        }
                    )
                failed_ids.add(task_id)
                progressed = True
                continue

            entry = {
                "id": task_id,
                "day": day,
                "title": str(task.get("title") or ""),
                "tag": str(task.get("tag") or "Task"),
                "load": task.get("load"),
                "goalId": task.get("goalId"),
                "goalTaskId": task.get("goalTaskId"),
                "height": _height_from_duration(duration),
                "color": _palette(task.get("load")),
                "time": _minutes_to_time(start),
                "reminderMinutesBefore": 10,
                "repeat": "none",
                "repeatUntil": None,
                "source": "planned",
                "explanationCodes": _explanation_codes(task, energy),
            }
            for chunk_index, (start, chunk_duration) in enumerate(chunks, start=1):
                chunk_entry = dict(entry)
                chunk_entry["id"] = task_id if not splittable else f"{task_id}#{chunk_index}"
                chunk_entry["height"] = _height_from_duration(chunk_duration)
                chunk_entry["time"] = _minutes_to_time(start)
                entries.append(chunk_entry)
            placed_ids.add(task_id)
            progressed = True

            due = _parse_datetime(task.get("due"))
            if due is not None and due_minutes is not None:
                if due_minutes < 0:
                    issues.append(
                        {
                            "code": "overdue",
                            "message": f"Task due before the requested day: {entry['title']}",
                            "taskId": task_id,
                            "explanationCodes": ["deadline_proximity"],
                        }
                    )
                elif chunks[-1][0] + chunks[-1][1] > due_minutes:
                    issues.append(
                        {
                            "code": "miss_due",
                            "message": f"Task scheduled past due time: {entry['title']}",
                            "taskId": task_id,
                            "explanationCodes": ["deadline_proximity"],
                        }
                    )

        if not progressed:
            for index, task in next_pending:
                task_id = _task_id(task, index)
                blocked_by = [str(dep) for dep in (task.get("dependsOn") or []) if str(dep) not in placed_ids]
                issues.append(
                    {
                        "code": "dependency_blocked",
                        "message": "Task cannot be scheduled until its dependency is placed",
                        "taskId": task_id,
                        "blockedBy": blocked_by,
                        "explanationCodes": [],
                    }
                )
                failed_ids.add(task_id)
            break
        pending = next_pending

    entries.extend(
        {
            "id": str(entry.get("id") or f"fixed_{index}"),
            "day": entry.get("day") or day,
            "title": str(entry.get("title") or ""),
            "tag": str(entry.get("tag") or "Fixed"),
            "load": entry.get("load"),
            "goalId": entry.get("goalId"),
            "goalTaskId": entry.get("goalTaskId"),
            "height": float(entry.get("height") or 80.0),
            "color": int(entry.get("color") or 0xFF64748B),
            "time": entry.get("time") or {"hour": 0, "minute": 0},
            "reminderMinutesBefore": int(entry.get("reminderMinutesBefore") or 10),
            "repeat": str(entry.get("repeat") or "none"),
            "repeatUntil": entry.get("repeatUntil"),
            "source": "fixed",
            "explanationCodes": (
                ["fixed_conflict"]
                if index in fixed_conflicts
                else (
                    _ordered_explanation_codes(entry.get("explanationCodes"))
                )
            ),
        }
        for index, entry in enumerate(fixed_entries)
    )

    entries.sort(key=lambda item: _time_to_minutes(item.get("time")))
    return {"entries": entries, "issues": issues}


class SchedulerCore:
    """Pure scheduling facade used by API and rescue adapters."""

    def plan(self, request: dict[str, Any]) -> dict[str, Any]:
        return _plan_schedule(request)
