from __future__ import annotations

import copy
from pathlib import Path

from backend.scheduling.constraints import ConstraintEngine
from backend.scheduling.explanations import ExplanationBuilder
from backend.scheduling.normalization import InputNormalizer
from backend.scheduling.ranking import TaskRanker
from backend.scheduling.rescue import RescueStrategy
from backend.scheduling.scoring import PlacementScorer


def test_input_normalizer_returns_independent_canonical_parts() -> None:
    request = {
        "day": "2026-09-14",
        "energy": "low",
        "tuning": {"defaultDurationMultiplier": 1.0},
        "windows": [{"start": {"hour": 9, "minute": 0}, "end": {"hour": 11, "minute": 0}}],
        "fixed": [
            {
                "id": "fixed",
                "title": "Fixed",
                "time": {"hour": 9, "minute": 0},
                "height": 80,
            }
        ],
        "tasks": [{"id": "task", "title": "Task", "durationMinutes": 30}],
    }

    normalized = InputNormalizer().normalize(request)

    assert normalized.day == "2026-09-14"
    assert normalized.windows == ((540, 660),)
    assert normalized.fixed_blocks == ((540, 600),)
    normalized.tasks[0]["title"] = "Changed"
    assert request["tasks"][0]["title"] == "Task"


def test_task_ranker_uses_contract_order_without_mutating_input() -> None:
    tasks = [
        {"id": "long", "durationMinutes": 40, "priority": 3},
        {"id": "urgent", "durationMinutes": 10, "priority": 1, "due": "2026-09-14T10:00:00"},
        {"id": "early", "durationMinutes": 10, "priority": 5, "due": "2026-09-14T09:00:00"},
    ]
    original = copy.deepcopy(tasks)

    ranked = TaskRanker().rank(tasks, "2026-09-14")

    assert [task["id"] for task in ranked] == ["early", "urgent", "long"]
    assert tasks == original


def test_constraint_engine_keeps_fixed_blocks_hard_and_reports_conflicts() -> None:
    engine = ConstraintEngine()
    windows = [(540, 660)]
    fixed_blocks = [(540, 600), (570, 630), (720, 750)]

    assert engine.fixed_conflicts(fixed_blocks, windows) == {0, 1, 2}
    assert engine.free_slots(windows, fixed_blocks) == [(630, 660)]


def test_placement_scorer_prefers_low_energy_afternoon_fallback() -> None:
    scorer = PlacementScorer()
    free = [(480, 600), (840, 960)]

    start = scorer.pick_slot(
        free,
        duration=60,
        earliest_start=None,
        due_minutes=420,
        hard_deadline=False,
        energy="veryLow",
        load="high",
        tuning={"highLoadPenaltyWhenLowEnergy": 2.0},
    )

    assert start == 840


def test_explanation_builder_orders_and_deduplicates_codes() -> None:
    builder = ExplanationBuilder()

    assert builder.ordered_codes(
        ["priority", "unknown", "kept_baseline", "priority", "deadline_proximity"]
    ) == ["deadline_proximity", "priority", "kept_baseline"]


def test_rescue_strategy_prefers_fewer_hard_issues_then_score() -> None:
    options = [
        {"strategy": "protectDeadline", "hardIssueCount": 1, "score": 0.99},
        {"strategy": "protectRecovery", "hardIssueCount": 0, "score": 0.20},
        {"strategy": "minimizeChanges", "hardIssueCount": 0, "score": 0.20},
    ]

    assert RescueStrategy.hard_issue_count(
        [{"code": "no_slot"}, {"code": "miss_due"}, {"code": "fixed_conflict"}]
    ) == 2
    assert RescueStrategy.recommended_index(options) == 1


def test_scheduling_component_modules_have_no_persistence_imports() -> None:
    module_dir = Path("backend/scheduling")
    source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in module_dir.glob("*.py")
        if path.name != "__init__.py"
    ).lower()

    for forbidden in ("fastapi", "repositories", "sqlite", "httpx", "requests"):
        assert forbidden not in source
