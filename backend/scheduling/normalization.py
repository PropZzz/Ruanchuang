"""Pure input normalization helpers for the scheduling core."""

from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any


def time_to_minutes(value: object) -> int:
    if isinstance(value, dict):
        hour = int(value.get("hour", 0) or 0)
        minute = int(value.get("minute", 0) or 0)
        return hour * 60 + minute
    return 0


def minutes_to_time(minutes: int) -> dict[str, int]:
    minutes = max(0, min(24 * 60 - 1, minutes))
    return {"hour": minutes // 60, "minute": minutes % 60}


def parse_day(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        return text.split("T", 1)[0]
    return None


def parse_datetime(value: object | None) -> datetime | None:
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


def duration_from_height(height: float) -> int:
    return max(1, min(24 * 60, round((height / 80.0) * 60.0)))


def height_from_duration(minutes: int) -> float:
    return round((minutes / 60.0) * 80.0, 2)


def task_id(task: dict[str, Any], index: int) -> str:
    return str(task.get("id") or f"plan_{index}")


@dataclass
class NormalizedRequest:
    day: str | None
    windows: tuple[tuple[int, int], ...]
    fixed_entries: list[dict[str, Any]]
    fixed_blocks: tuple[tuple[int, int], ...]
    tasks: list[dict[str, Any]]
    energy: object
    tuning: dict[str, Any]


class InputNormalizer:
    """Convert permissive adapter dictionaries into independent core inputs."""

    def normalize(self, request: dict[str, Any]) -> NormalizedRequest:
        payload = request if isinstance(request, dict) else {}
        day = parse_day(payload.get("day"))
        energy = payload.get("energy") or "medium"
        tuning_raw = payload.get("tuning") or {}
        tuning = deepcopy(tuning_raw) if isinstance(tuning_raw, dict) else {}

        windows: list[tuple[int, int]] = []
        for window in payload.get("windows") or []:
            if not isinstance(window, dict):
                continue
            start = time_to_minutes(window.get("start"))
            end = time_to_minutes(window.get("end"))
            if end > start:
                windows.append((start, end))

        fixed_pairs: list[tuple[dict[str, Any], tuple[int, int]]] = []
        for raw_entry in payload.get("fixed") or []:
            if not isinstance(raw_entry, dict):
                continue
            entry = deepcopy(raw_entry)
            start = time_to_minutes(entry.get("time"))
            duration = int(
                entry.get("durationMinutes")
                or entry.get("minutes")
                or duration_from_height(float(entry.get("height") or 80.0))
            )
            fixed_pairs.append((entry, (start, start + max(1, duration))))
        fixed_pairs.sort(
            key=lambda pair: (pair[1][0], str(pair[0].get("id") or ""))
        )

        tasks = [
            deepcopy(task)
            for task in payload.get("tasks") or []
            if isinstance(task, dict)
        ]
        return NormalizedRequest(
            day=day,
            windows=tuple(windows),
            fixed_entries=[entry for entry, _ in fixed_pairs],
            fixed_blocks=tuple(block for _, block in fixed_pairs),
            tasks=tasks,
            energy=energy,
            tuning=tuning,
        )


# Private aliases keep the old helper names available to local adapters.
_time_to_minutes = time_to_minutes
_minutes_to_time = minutes_to_time
_parse_day = parse_day
_parse_datetime = parse_datetime
_duration_from_height = duration_from_height
_height_from_duration = height_from_duration
_task_id = task_id
