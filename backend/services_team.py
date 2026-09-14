from __future__ import annotations

from typing import Any


def _minutes(value: object) -> int:
    if not isinstance(value, dict):
        return 0
    return int(value.get("hour", 0) or 0) * 60 + int(value.get("minute", 0) or 0)


def _time(value: int) -> dict[str, int]:
    value = max(0, min(1439, value))
    return {"hour": value // 60, "minute": value % 60}


def _busy_intervals(member: dict[str, Any], day: str) -> list[tuple[int, int, dict[str, Any]]]:
    intervals = []
    for entry in member.get("busy") or []:
        if not isinstance(entry, dict) or str(entry.get("day") or day) != day:
            continue
        start = _minutes(entry.get("time"))
        duration = max(1, round(float(entry.get("height") or 60) / 80 * 60))
        intervals.append((start, min(1440, start + duration), entry))
    return intervals


def conflicts(members: list[dict[str, Any]], day: str, start: int, minutes: int) -> list[dict[str, Any]]:
    end = start + minutes
    result = []
    for member in members:
        for busy_start, busy_end, entry in _busy_intervals(member, day):
            if start < busy_end and busy_start < end:
                result.append({"memberId": member["memberId"], "entryId": entry.get("id"), "start": _time(max(start, busy_start)), "end": _time(min(end, busy_end))})
    return result


def golden_windows(members: list[dict[str, Any]], day: str, windows: list[dict[str, Any]], minutes: int) -> list[dict[str, Any]]:
    busy = []
    for member in members:
        busy.extend((start, end) for start, end, _ in _busy_intervals(member, day))
    merged: list[tuple[int, int]] = []
    for start, end in sorted(busy):
        if merged and start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    result = []
    for window in windows:
        cursor = _minutes(window.get("start"))
        end = _minutes(window.get("end"))
        for busy_start, busy_end in merged:
            if busy_end <= cursor:
                continue
            if busy_start >= end:
                break
            if busy_start - cursor >= minutes:
                result.append({"start": _time(cursor), "end": _time(busy_start), "minutes": busy_start - cursor})
            cursor = max(cursor, busy_end)
        if end - cursor >= minutes:
            result.append({"start": _time(cursor), "end": _time(end), "minutes": end - cursor})
    return result
