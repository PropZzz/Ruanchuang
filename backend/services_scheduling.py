from __future__ import annotations

from datetime import date, datetime
from typing import Any


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
    due = _parse_datetime(task.get("due"))
    due_rank = 1
    due_minutes = 10**9
    if due is not None:
        due_rank = 0
        if current_day is not None and due.date().isoformat() == current_day:
            due_minutes = due.hour * 60 + due.minute
        else:
            due_minutes = int(due.timestamp() // 60)
    return (-priority, due_rank, due_minutes, _task_duration(task, task.get("energy"), {}), str(task.get("title") or ""))


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


def _palette(load: object) -> int:
    palette = {
        "high": 0xFFB42318,
        "medium": 0xFF0F766E,
        "low": 0xFF2563EB,
    }
    return palette.get(str(load or ""), 0xFF334155)


def plan_schedule(request: dict[str, Any]) -> dict[str, Any]:
    day = _parse_day(request.get("day"))
    windows_raw = request.get("windows") or []
    fixed_raw = request.get("fixed") or []
    tasks_raw = request.get("tasks") or []
    energy = request.get("energy") or "medium"
    tuning = request.get("tuning") or {}

    busy_blocks: list[tuple[int, int]] = []
    fixed_entries: list[dict[str, Any]] = []
    for entry in fixed_raw:
        if not isinstance(entry, dict):
            continue
        start = _time_to_minutes(entry.get("time"))
        duration = int(entry.get("durationMinutes") or entry.get("minutes") or _duration_from_height(float(entry.get("height") or 80.0)))
        busy_blocks.append((start, start + max(1, duration)))
        fixed_entries.append(entry)

    slots: list[tuple[int, int]] = []
    for window in windows_raw:
        if not isinstance(window, dict):
            continue
        start = _time_to_minutes(window.get("start"))
        end = _time_to_minutes(window.get("end"))
        if end <= start:
            continue
        slots.extend(_subtract((start, end), _merge_busy(busy_blocks)))

    if not slots:
        slots = [(8 * 60, 20 * 60)]

    tasks = [task for task in tasks_raw if isinstance(task, dict)]
    tasks.sort(key=lambda task: _task_priority(task, day))

    entries: list[dict[str, Any]] = []
    issues: list[dict[str, Any]] = []
    slot_index = 0
    cursor = slots[0][0] if slots else 0

    for index, task in enumerate(tasks):
        duration = _task_duration(task, energy, tuning)
        placed = False
        while slot_index < len(slots):
            slot_start, slot_end = slots[slot_index]
            cursor = max(cursor, slot_start)
            if cursor + duration <= slot_end:
                entry = {
                    "id": str(task.get("id") or f"plan_{index}"),
                    "day": day,
                    "title": str(task.get("title") or ""),
                    "tag": str(task.get("tag") or "Task"),
                    "load": task.get("load"),
                    "goalId": task.get("goalId"),
                    "goalTaskId": task.get("goalTaskId"),
                    "height": _height_from_duration(duration),
                    "color": _palette(task.get("load")),
                    "time": _minutes_to_time(cursor),
                    "reminderMinutesBefore": 10,
                    "repeat": "none",
                    "repeatUntil": None,
                }
                entries.append(entry)
                cursor += duration
                placed = True

                due = _parse_datetime(task.get("due"))
                if due is not None:
                    if day is not None and due.date().isoformat() == day and cursor > due.hour * 60 + due.minute:
                        issues.append(
                            {
                                "code": "miss_due",
                                "message": f"Task scheduled past due time: {entry['title']}",
                                "taskId": entry["id"],
                            }
                        )
                    elif day is not None and due.date().isoformat() < day:
                        issues.append(
                            {
                                "code": "overdue",
                                "message": f"Task due before the requested day: {entry['title']}",
                                "taskId": entry["id"],
                            }
                        )
                break

            slot_index += 1
            if slot_index < len(slots):
                cursor = slots[slot_index][0]

        if not placed:
            issues.append(
                {
                    "code": "no_slot",
                    "message": f"No time slot left for task: {task.get('title', '')}",
                    "taskId": task.get("id"),
                }
            )

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
        }
        for index, entry in enumerate(fixed_entries)
    )

    entries.sort(key=lambda item: _time_to_minutes(item.get("time")))
    return {"entries": entries, "issues": issues}
