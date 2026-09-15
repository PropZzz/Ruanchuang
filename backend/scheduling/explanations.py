"""Stable issue, entry, and explanation construction."""

from __future__ import annotations

from typing import Any

from .normalization import height_from_duration, minutes_to_time
from .scoring import palette


EXPLANATION_CODE_ORDER = (
    "deadline_proximity",
    "priority",
    "energy_fit",
    "kept_baseline",
    "fixed_conflict",
)


def ordered_explanation_codes(codes: object) -> list[str]:
    if not isinstance(codes, list):
        return []
    values = {str(code) for code in codes}
    return [code for code in EXPLANATION_CODE_ORDER if code in values]


def task_explanation_codes(task: dict[str, Any], energy: object) -> list[str]:
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
    return ordered_explanation_codes(codes)


class ExplanationBuilder:
    """Build deterministic diagnostics while keeping wording at the adapter edge."""

    def ordered_codes(self, codes: object) -> list[str]:
        return ordered_explanation_codes(codes)

    def task_codes(self, task: dict[str, Any], energy: object) -> list[str]:
        return task_explanation_codes(task, energy)

    def no_slot(
        self,
        task_id: str,
        title: object,
        *,
        due: object,
        hard_deadline: bool,
    ) -> dict[str, Any]:
        return {
            "code": "no_slot",
            "message": f"No time slot left for task: {title}",
            "taskId": task_id,
            "explanationCodes": ["deadline_proximity"] if due else [],
            "hard": bool(hard_deadline),
        }

    def overdue(self, task_id: str, title: object) -> dict[str, Any]:
        return {
            "code": "overdue",
            "message": f"Task due before the requested day: {title}",
            "taskId": task_id,
            "explanationCodes": ["deadline_proximity"],
        }

    def miss_due(self, task_id: str, title: object) -> dict[str, Any]:
        return {
            "code": "miss_due",
            "message": f"Task scheduled past due time: {title}",
            "taskId": task_id,
            "explanationCodes": ["deadline_proximity"],
        }

    def dependency_blocked(
        self,
        task_id: str,
        blocked_by: list[str],
    ) -> dict[str, Any]:
        return {
            "code": "dependency_blocked",
            "message": "Task cannot be scheduled until its dependency is placed",
            "taskId": task_id,
            "blockedBy": blocked_by,
            "explanationCodes": [],
        }

    def fixed_conflict(self, task_id: str) -> dict[str, Any]:
        return {
            "code": "fixed_conflict",
            "message": "Fixed entry overlaps another fixed entry or lies outside every work window",
            "taskId": task_id,
            "explanationCodes": ["fixed_conflict"],
            "hard": True,
        }

    def planned_entry(
        self,
        task: dict[str, Any],
        task_id: str,
        day: str | None,
        duration: int,
        start_minutes: int,
        energy: object,
    ) -> dict[str, Any]:
        return {
            "id": task_id,
            "day": day,
            "title": str(task.get("title") or ""),
            "tag": str(task.get("tag") or "Task"),
            "load": task.get("load"),
            "goalId": task.get("goalId"),
            "goalTaskId": task.get("goalTaskId"),
            "height": height_from_duration(duration),
            "color": palette(task.get("load")),
            "time": minutes_to_time(start_minutes),
            "reminderMinutesBefore": 10,
            "repeat": "none",
            "repeatUntil": None,
            "source": "planned",
            "explanationCodes": task_explanation_codes(task, energy),
        }

    def fixed_entry(
        self,
        entry: dict[str, Any],
        index: int,
        day: str | None,
        conflict: bool,
    ) -> dict[str, Any]:
        supplied_codes = (
            entry.get("explanationCodes")
            if isinstance(entry.get("explanationCodes"), list)
            else []
        )
        return {
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
            "explanationCodes": ordered_explanation_codes(
                [
                    *supplied_codes,
                    *(["fixed_conflict"] if conflict else []),
                ]
            ),
        }


_ordered_explanation_codes = ordered_explanation_codes
_explanation_codes = task_explanation_codes
