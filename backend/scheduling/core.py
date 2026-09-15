"""Pure scheduling orchestration."""

from __future__ import annotations

from typing import Any

from .constraints import (
    ConstraintEngine,
    consume_interval,
    due_minutes_for_day,
    earliest_start_minutes,
    merge_busy,
    next_chunk_duration,
    subtract,
)
from .explanations import (
    ExplanationBuilder,
    ordered_explanation_codes,
    task_explanation_codes,
)
from .normalization import (
    InputNormalizer,
    NormalizedRequest,
    duration_from_height,
    height_from_duration,
    minutes_to_time,
    parse_day,
    parse_datetime,
    task_id,
    time_to_minutes,
)
from .ranking import TaskRanker, task_sort_key
from .scoring import (
    PlacementScorer,
    load_penalty,
    palette,
    score_placement,
    task_duration,
)


class SchedulerCore:
    """Pure scheduling facade composed from focused computation components."""

    def __init__(
        self,
        *,
        normalizer: InputNormalizer | None = None,
        constraints: ConstraintEngine | None = None,
        ranker: TaskRanker | None = None,
        scorer: PlacementScorer | None = None,
        explanations: ExplanationBuilder | None = None,
    ) -> None:
        self._normalizer = normalizer if normalizer is not None else InputNormalizer()
        self._constraints = constraints if constraints is not None else ConstraintEngine()
        self._ranker = ranker if ranker is not None else TaskRanker()
        self._scorer = scorer if scorer is not None else PlacementScorer()
        self._explanations = (
            explanations if explanations is not None else ExplanationBuilder()
        )

    def plan(self, request: dict[str, Any]) -> dict[str, Any]:
        normalized = self._normalizer.normalize(request)
        return self._plan_normalized(normalized)

    def _plan_normalized(self, request: NormalizedRequest) -> dict[str, Any]:
        day = request.day
        energy = request.energy
        tuning = request.tuning
        fixed_entries = request.fixed_entries
        fixed_blocks = request.fixed_blocks
        supplied_windows = list(request.windows)

        fixed_conflicts = self._constraints.fixed_conflicts(
            fixed_blocks,
            supplied_windows,
        )
        slots = self._constraints.free_slots(supplied_windows, fixed_blocks)
        tasks = self._ranker.rank(request.tasks, day)

        entries: list[dict[str, Any]] = []
        issues: list[dict[str, Any]] = []
        for index in sorted(fixed_conflicts):
            issues.append(
                self._explanations.fixed_conflict(task_id(fixed_entries[index], index))
            )

        fixed_ids = {
            task_id(entry, index) for index, entry in enumerate(fixed_entries)
        }
        task_by_id = {task_id(task, index): task for index, task in enumerate(tasks)}
        pending = list(enumerate(tasks))
        placed_ids = set(fixed_ids)
        failed_ids: set[str] = set()

        while pending:
            progressed = False
            next_pending: list[tuple[int, dict[str, Any]]] = []
            for index, task in pending:
                current_task_id = task_id(task, index)
                if current_task_id in fixed_ids:
                    progressed = True
                    continue

                blocked_by, unresolved = self._constraints.blocked_dependencies(
                    task,
                    placed_ids,
                    set(task_by_id),
                    failed_ids,
                )
                if unresolved:
                    issues.append(
                        self._explanations.dependency_blocked(
                            current_task_id,
                            blocked_by,
                        )
                    )
                    failed_ids.add(current_task_id)
                    progressed = True
                    continue
                if blocked_by:
                    next_pending.append((index, task))
                    continue

                duration = self._scorer.task_duration(task, energy, tuning)
                splittable = bool(task.get("splittable"))
                minimum_chunk = int(task.get("minimumChunkMinutes") or 15)
                earliest_minutes = self._constraints.earliest_start(task, day)
                due_minutes = self._constraints.due_minutes(task, day)
                slots_before_task = list(slots)
                chunks: list[tuple[int, int]] = []
                remaining = duration
                while remaining > 0:
                    chunk_duration = (
                        self._constraints.next_chunk(
                            remaining,
                            minimum_chunk,
                            slots,
                            earliest_start=earliest_minutes,
                        )
                        if splittable
                        else remaining
                    )
                    if chunk_duration is None:
                        break
                    start = self._scorer.pick_slot(
                        slots,
                        chunk_duration,
                        earliest_minutes,
                        due_minutes,
                        bool(task.get("hardDeadline")),
                        energy,
                        task.get("load"),
                        tuning,
                    )
                    if start is None:
                        break
                    chunks.append((start, chunk_duration))
                    self._constraints.consume(
                        slots,
                        (start, start + chunk_duration),
                    )
                    remaining -= chunk_duration

                if remaining > 0:
                    slots[:] = slots_before_task
                    issues.append(
                        self._explanations.no_slot(
                            current_task_id,
                            task.get("title", ""),
                            due=task.get("due"),
                            hard_deadline=bool(task.get("hardDeadline")),
                        )
                    )
                    if due_minutes is not None and due_minutes < 0:
                        issues.append(
                            self._explanations.overdue(
                                current_task_id,
                                task.get("title", ""),
                            )
                        )
                    failed_ids.add(current_task_id)
                    progressed = True
                    continue

                entry = self._explanations.planned_entry(
                    task,
                    current_task_id,
                    day,
                    duration,
                    chunks[-1][0],
                    energy,
                )
                for chunk_index, (start, chunk_duration) in enumerate(chunks, start=1):
                    chunk_entry = dict(entry)
                    chunk_entry["id"] = (
                        current_task_id
                        if not splittable
                        else f"{current_task_id}#{chunk_index}"
                    )
                    chunk_entry["height"] = height_from_duration(chunk_duration)
                    chunk_entry["time"] = minutes_to_time(start)
                    entries.append(chunk_entry)
                placed_ids.add(current_task_id)
                progressed = True

                due = parse_datetime(task.get("due"))
                if due is not None and due_minutes is not None:
                    if due_minutes < 0:
                        issues.append(
                            self._explanations.overdue(
                                current_task_id,
                                entry["title"],
                            )
                        )
                    elif chunks[-1][0] + chunks[-1][1] > due_minutes:
                        issues.append(
                            self._explanations.miss_due(
                                current_task_id,
                                entry["title"],
                            )
                        )

            if not progressed:
                for index, task in next_pending:
                    current_task_id = task_id(task, index)
                    blocked_by = [
                        str(dependency)
                        for dependency in (task.get("dependsOn") or [])
                        if str(dependency) not in placed_ids
                    ]
                    issues.append(
                        self._explanations.dependency_blocked(
                            current_task_id,
                            blocked_by,
                        )
                    )
                    failed_ids.add(current_task_id)
                break
            pending = next_pending

        entries.extend(
            self._explanations.fixed_entry(
                entry,
                index,
                day,
                index in fixed_conflicts,
            )
            for index, entry in enumerate(fixed_entries)
        )
        entries.sort(key=lambda item: time_to_minutes(item.get("time")))
        return {"entries": entries, "issues": issues}


def _plan_schedule(request: dict[str, Any]) -> dict[str, Any]:
    """Compatibility helper for code that used the old private function."""

    return SchedulerCore().plan(request)


# Private aliases preserve the old helper names for downstream adapters while the
# implementation lives in focused modules.
_time_to_minutes = time_to_minutes
_minutes_to_time = minutes_to_time
_parse_day = parse_day
_parse_datetime = parse_datetime
_duration_from_height = duration_from_height
_height_from_duration = height_from_duration
_load_penalty = load_penalty
_task_duration = task_duration
_task_priority = task_sort_key
_task_id = task_id
_explanation_codes = task_explanation_codes
_due_minutes_for_day = due_minutes_for_day
_merge_busy = merge_busy
_subtract = subtract
_consume_interval = consume_interval
_palette = palette
_next_chunk_duration = next_chunk_duration
_score_placement = score_placement


__all__ = ["SchedulerCore"]
