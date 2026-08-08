from __future__ import annotations

from typing import Any


def _m(t: dict[str, int]) -> int:
    return int(t.get("hour", 0)) * 60 + int(t.get("minute", 0))


def _tod(minutes: int) -> dict[str, int]:
    minutes = max(0, min(24 * 60 - 1, minutes))
    return {"hour": minutes // 60, "minute": minutes % 60}


def _duration_from_height(height: float) -> int:
    return max(1, min(24 * 60, round((height / 80.0) * 60.0)))


def _bucket(minutes: int) -> str:
    if minutes <= 15:
        return "short"
    if minutes <= 30:
        return "medium"
    return "long"


def _subtract(window: tuple[int, int], busy: list[tuple[int, int]]) -> list[tuple[int, int]]:
    free: list[tuple[int, int]] = []
    cursor = window[0]
    for s, e in sorted(busy):
        if e <= cursor:
            continue
        if s >= window[1]:
            break
        s = max(s, window[0])
        e = min(e, window[1])
        if s > cursor:
            free.append((cursor, s))
        cursor = max(cursor, e)
    if cursor < window[1]:
        free.append((cursor, window[1]))
    return free


def recommend_crystals(request: dict[str, Any]) -> list[dict[str, Any]]:
    busy = []
    for entry in request.get("schedule", []):
        if not isinstance(entry, dict):
            continue
        s = _m(entry["time"])
        busy.append((s, s + _duration_from_height(float(entry.get("height") or 80.0))))

    now = _m(request["now"])
    crystals = []
    for window in request.get("windows", []):
        if not isinstance(window, dict):
            continue
        ws = _m(window["start"])
        we = _m(window["end"])
        if we <= ws:
            continue
        for s, e in _subtract((ws, we), busy):
            s = max(s, now)
            if e > s:
                crystals.append({"start": _tod(s), "minutes": e - s, "bucket": _bucket(e - s)})

    crystals.sort(key=lambda c: (c["minutes"], c["start"]["hour"], c["start"]["minute"]))
    tasks = [task for task in request.get("microTasks", []) if isinstance(task, dict) and not task.get("done")]
    energy = str(request.get("energy", "medium"))
    max_recs = int(request.get("maxRecommendations") or 5)
    recs = []

    for crystal in crystals:
        if len(recs) >= max_recs:
            break
        best = None
        best_score = float("-inf")
        for task in tasks:
            minutes = int(task["minutes"])
            if minutes <= 0 or minutes > crystal["minutes"]:
                continue
            waste = crystal["minutes"] - minutes
            score = (1.0 - waste / crystal["minutes"]) * 10.0 - waste * 0.05
            score += (max(1, min(5, int(task.get("priority") or 3))) - 3) * 0.6
            if energy in ("veryLow", "low") and minutes <= 15:
                score += 2.0
            if energy in ("high", "veryHigh") and minutes >= 30:
                score += 1.0
            if score > best_score:
                best_score = score
                best = task
        if best is None:
            continue
        tasks.remove(best)
        recs.append({"crystal": crystal, "task": best, "score": round(best_score, 3)})

    recs.sort(key=lambda rec: _m(rec["crystal"]["start"]))
    return recs
