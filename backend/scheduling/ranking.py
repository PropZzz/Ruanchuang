"""Deterministic task ranking for scheduling."""

from __future__ import annotations

from typing import Any

from .normalization import parse_datetime


def task_sort_key(task: dict[str, Any], current_day: str | None) -> tuple:
    """Sort by same-day due, other due, no due, priority, duration, and id."""

    priority = int(task.get("priority") or 3)
    duration = max(1, int(task.get("durationMinutes") or 15))
    due = parse_datetime(task.get("due"))
    due_rank = 2
    due_value = 10**9
    if due is not None:
        if current_day is not None and due.date().isoformat() == current_day:
            due_rank = 0
            due_value = due.hour * 60 + due.minute
        else:
            due_rank = 1
            due_value = int(due.timestamp() // 60)
    return (due_rank, due_value, -priority, -duration, str(task.get("id") or ""))


class TaskRanker:
    """Pure stable ordering of task dictionaries."""

    def sort_key(self, task: dict[str, Any], current_day: str | None) -> tuple:
        return task_sort_key(task, current_day)

    def rank(
        self,
        tasks: list[dict[str, Any]],
        current_day: str | None,
    ) -> list[dict[str, Any]]:
        return sorted(tasks, key=lambda task: self.sort_key(task, current_day))


_task_priority = task_sort_key
