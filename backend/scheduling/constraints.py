"""Pure hard-constraint and interval operations for scheduling."""

from __future__ import annotations

from typing import Any

from .normalization import parse_datetime


def merge_busy(blocks: list[tuple[int, int]] | tuple[tuple[int, int], ...]) -> list[tuple[int, int]]:
    merged: list[tuple[int, int]] = []
    for start, end in sorted(blocks):
        if end <= start:
            continue
        if not merged or start > merged[-1][1]:
            merged.append((start, end))
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    return merged


def subtract(
    window: tuple[int, int],
    busy: list[tuple[int, int]] | tuple[tuple[int, int], ...],
) -> list[tuple[int, int]]:
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


def consume_interval(intervals: list[tuple[int, int]], used: tuple[int, int]) -> None:
    remaining: list[tuple[int, int]] = []
    for interval in intervals:
        remaining.extend(subtract(interval, [used]))
    intervals[:] = remaining


def earliest_start_minutes(task: dict[str, Any], current_day: str | None) -> int | None:
    earliest = parse_datetime(task.get("earliestStart"))
    if earliest is None or current_day is None:
        return None
    earliest_day = earliest.date().isoformat()
    if earliest_day > current_day:
        return 24 * 60
    if earliest_day == current_day:
        return earliest.hour * 60 + earliest.minute
    return None


def due_minutes_for_day(task: dict[str, Any], current_day: str | None) -> int | None:
    due = parse_datetime(task.get("due"))
    if due is None or current_day is None:
        return None
    due_day = due.date().isoformat()
    if due_day == current_day:
        return due.hour * 60 + due.minute
    if due_day < current_day:
        return -1
    return None


def next_chunk_duration(
    remaining: int,
    minimum_chunk: int,
    slots: list[tuple[int, int]],
    earliest_start: int | None = None,
) -> int | None:
    lengths = [
        end - (start if earliest_start is None or start > earliest_start else earliest_start)
        for start, end in slots
    ]
    lengths = [length for length in lengths if length > 0]
    if any(length >= remaining for length in lengths):
        return remaining
    largest = max(lengths, default=0)
    if largest < minimum_chunk:
        return None
    candidate = min(remaining, largest)
    remainder = remaining - candidate
    if 0 < remainder < minimum_chunk:
        candidate = remaining - minimum_chunk
    if candidate < minimum_chunk or candidate > largest:
        return None
    return candidate


class ConstraintEngine:
    """Evaluate fixed blocks, windows, dependencies, and deadline boundaries."""

    def fixed_conflicts(
        self,
        fixed_blocks: list[tuple[int, int]] | tuple[tuple[int, int], ...],
        windows: list[tuple[int, int]] | tuple[tuple[int, int], ...],
    ) -> set[int]:
        conflicts: set[int] = set()
        blocks = list(fixed_blocks)
        valid_windows = list(windows)
        for index, (start, end) in enumerate(blocks):
            if not any(
                window_start <= start and end <= window_end
                for window_start, window_end in valid_windows
            ):
                conflicts.add(index)
            for other_index, (other_start, other_end) in enumerate(blocks):
                if index != other_index and start < other_end and other_start < end:
                    conflicts.add(index)
        return conflicts

    def free_slots(
        self,
        windows: list[tuple[int, int]] | tuple[tuple[int, int], ...],
        fixed_blocks: list[tuple[int, int]] | tuple[tuple[int, int], ...],
    ) -> list[tuple[int, int]]:
        busy = merge_busy(fixed_blocks)
        slots: list[tuple[int, int]] = []
        for window in windows:
            slots.extend(subtract(window, busy))
        return slots

    def blocked_dependencies(
        self,
        task: dict[str, Any],
        placed_ids: set[str],
        task_ids: set[str],
        failed_ids: set[str],
    ) -> tuple[list[str], bool]:
        dependencies = [str(dep) for dep in (task.get("dependsOn") or [])]
        blocked_by = [dependency for dependency in dependencies if dependency not in placed_ids]
        unresolved = any(
            dependency not in task_ids or dependency in failed_ids
            for dependency in blocked_by
        )
        return blocked_by, unresolved

    def earliest_start(self, task: dict[str, Any], current_day: str | None) -> int | None:
        return earliest_start_minutes(task, current_day)

    def due_minutes(self, task: dict[str, Any], current_day: str | None) -> int | None:
        return due_minutes_for_day(task, current_day)

    def next_chunk(
        self,
        remaining: int,
        minimum_chunk: int,
        slots: list[tuple[int, int]],
        earliest_start: int | None = None,
    ) -> int | None:
        return next_chunk_duration(remaining, minimum_chunk, slots, earliest_start)

    def consume(self, intervals: list[tuple[int, int]], used: tuple[int, int]) -> None:
        consume_interval(intervals, used)


_merge_busy = merge_busy
_subtract = subtract
_consume_interval = consume_interval
_due_minutes_for_day = due_minutes_for_day
_next_chunk_duration = next_chunk_duration
