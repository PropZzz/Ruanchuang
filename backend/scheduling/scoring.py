"""Pure placement scoring and task duration calculations."""

from __future__ import annotations

from typing import Any


def load_penalty(load: object, energy: object, tuning: dict[str, Any]) -> float:
    if energy not in {"low", "veryLow"}:
        return 1.0
    if load == "high":
        return float(tuning.get("highLoadPenaltyWhenLowEnergy") or 1.2)
    if load == "medium":
        return 1.05
    return 1.0


def task_duration(
    task: dict[str, Any],
    energy: object,
    tuning: dict[str, Any],
) -> int:
    duration = int(task.get("durationMinutes") or 0)
    if duration <= 0:
        duration = 15

    multipliers = tuning.get("tagDurationMultiplier") if isinstance(tuning, dict) else {}
    tag_multiplier = 1.0
    if isinstance(multipliers, dict):
        raw = multipliers.get(str(task.get("tag") or ""))
        if isinstance(raw, (int, float)):
            tag_multiplier = float(raw)

    base = duration * float(tuning.get("defaultDurationMultiplier") or 1.0)
    base *= tag_multiplier
    base *= load_penalty(task.get("load"), energy, tuning)
    return max(1, round(base))


def score_placement(
    start_minutes: int,
    energy: object,
    load: object,
    tuning: dict[str, Any],
) -> float:
    hour = start_minutes // 60
    is_morning = hour < 12
    is_afternoon = 12 <= hour < 17
    score = -start_minutes / 1000.0
    if energy in {"high", "veryHigh"}:
        if load == "high" and is_morning:
            score += 5
        if load == "medium" and is_afternoon:
            score += 2
        if load == "low":
            score += 0.5
    elif energy == "medium":
        if load == "high" and is_morning:
            score += 2
        if load == "medium":
            score += 2
        if load == "low":
            score += 1
    else:
        penalty = min(3.0, max(1.0, float(tuning.get("highLoadPenaltyWhenLowEnergy") or 1.0)))
        extra = max(0.0, penalty - 1.0)
        if load == "high":
            score -= 5 * penalty
            if is_morning:
                score -= 2.0 * (1.0 + extra)
        if load == "medium":
            score -= 1
        if load == "low":
            score += 3
    return score


def palette(load: object) -> int:
    values = {
        "high": 0xFFB42318,
        "medium": 0xFF0F766E,
        "low": 0xFF2563EB,
    }
    return values.get(str(load or ""), 0xFF334155)


class PlacementScorer:
    """Select legal slots using the soft energy/load preference."""

    def task_duration(
        self,
        task: dict[str, Any],
        energy: object,
        tuning: dict[str, Any],
    ) -> int:
        return task_duration(task, energy, tuning)

    def score(
        self,
        start_minutes: int,
        energy: object,
        load: object,
        tuning: dict[str, Any],
    ) -> float:
        return score_placement(start_minutes, energy, load, tuning)

    def pick_slot(
        self,
        free: list[tuple[int, int]],
        duration: int,
        earliest_start: int | None,
        due_minutes: int | None,
        hard_deadline: bool,
        energy: object,
        load: object,
        tuning: dict[str, Any],
    ) -> int | None:
        def candidate_for(interval: tuple[int, int]) -> int:
            start, _ = interval
            return max(start, earliest_start if earliest_start is not None else start)

        best_start: int | None = None
        best_score = float("-inf")
        for interval in free:
            start, end = interval
            candidate = candidate_for(interval)
            if candidate + duration > end:
                continue
            if due_minutes is not None and (
                due_minutes < 0 or candidate + duration > due_minutes
            ):
                continue
            score = self.score(candidate, energy, load, tuning)
            if score > best_score:
                best_score = score
                best_start = candidate
        if best_start is not None:
            return best_start
        if hard_deadline and due_minutes is not None:
            return None

        best_start = None
        best_score = float("-inf")
        for interval in free:
            _, end = interval
            candidate = candidate_for(interval)
            if candidate + duration > end:
                continue
            score = self.score(candidate, energy, load, tuning)
            if score > best_score:
                best_score = score
                best_start = candidate
        if best_start is not None:
            return best_start

        for interval in free:
            start, end = interval
            candidate = candidate_for(interval)
            if candidate + duration <= end:
                return candidate
        return None

    def palette(self, load: object) -> int:
        return palette(load)


_load_penalty = load_penalty
_task_duration = task_duration
_score_placement = score_placement
_palette = palette
