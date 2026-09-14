from __future__ import annotations

from pathlib import Path

from backend.scheduling.core import SchedulerCore


def _request() -> dict[str, object]:
    return {
        "day": "2026-09-14",
        "energy": "medium",
        "windows": [{"start": {"hour": 9, "minute": 0}, "end": {"hour": 11, "minute": 0}}],
        "fixed": [],
        "tasks": [
            {"id": "b", "title": "B", "durationMinutes": 20, "priority": 3, "load": "low", "tag": "Task"},
            {"id": "a", "title": "A", "durationMinutes": 20, "priority": 3, "load": "low", "tag": "Task"},
        ],
    }


def test_scheduler_core_returns_internal_plan() -> None:
    result = SchedulerCore().plan(_request())
    assert [entry["id"] for entry in result["entries"]] == ["a", "b"]
    assert result["entries"][0]["source"] == "planned"


def test_scheduler_core_has_no_persistence_imports() -> None:
    source = Path("backend/scheduling/core.py").read_text(encoding="utf-8")
    assert "repositories" not in source
    assert "sqlite" not in source.lower()


def test_empty_windows_do_not_create_default_slot() -> None:
    request = _request()
    request["windows"] = []
    result = SchedulerCore().plan(request)

    assert result["entries"] == []
    assert [issue["code"] for issue in result["issues"]] == ["no_slot", "no_slot"]


def test_earliest_start_after_window_end_cannot_place_outside_window() -> None:
    request = _request()
    request["tasks"] = [
        {
            "id": "late-start",
            "title": "Late start",
            "durationMinutes": 15,
            "priority": 5,
            "earliestStart": "2026-09-14T11:00:00+08:00",
        }
    ]
    result = SchedulerCore().plan(request)

    assert result["entries"] == []
    assert result["issues"][0]["code"] == "no_slot"


def test_fixed_conflicts_are_diagnosed_and_fixed_entries_preserved() -> None:
    request = _request()
    request["tasks"] = []
    request["windows"] = [
        {"start": {"hour": 9, "minute": 0}, "end": {"hour": 11, "minute": 0}}
    ]
    request["fixed"] = [
        {"id": "fixed-a", "title": "A", "time": {"hour": 9, "minute": 0}, "height": 80},
        {"id": "fixed-b", "title": "B", "time": {"hour": 9, "minute": 30}, "height": 40},
        {"id": "fixed-c", "title": "C", "time": {"hour": 12, "minute": 0}, "height": 40},
    ]
    result = SchedulerCore().plan(request)

    assert {entry["id"] for entry in result["entries"]} == {"fixed-a", "fixed-b", "fixed-c"}
    conflicts = [issue for issue in result["issues"] if issue["code"] == "fixed_conflict"]
    assert {issue["taskId"] for issue in conflicts} == {"fixed-a", "fixed-b", "fixed-c"}


def test_hard_deadline_has_no_late_fallback() -> None:
    request = _request()
    request["windows"] = [
        {"start": {"hour": 10, "minute": 0}, "end": {"hour": 11, "minute": 0}}
    ]
    request["tasks"] = [
        {
            "id": "hard",
            "title": "Hard",
            "durationMinutes": 30,
            "priority": 5,
            "due": "2026-09-14T09:30:00+08:00",
            "hardDeadline": True,
        }
    ]
    result = SchedulerCore().plan(request)

    assert result["entries"] == []
    assert result["issues"][0]["code"] == "no_slot"
    assert "deadline_proximity" in result["issues"][0]["explanationCodes"]


def test_soft_due_falls_back_to_earliest_legal_slot_and_reports_miss_due() -> None:
    request = _request()
    request["windows"] = [
        {"start": {"hour": 10, "minute": 0}, "end": {"hour": 11, "minute": 0}}
    ]
    request["tasks"] = [
        {
            "id": "soft",
            "title": "Soft",
            "durationMinutes": 30,
            "priority": 5,
            "due": "2026-09-14T09:30:00+08:00",
        }
    ]
    result = SchedulerCore().plan(request)

    assert result["entries"][0]["time"] == {"hour": 10, "minute": 0}
    assert result["issues"][0]["code"] == "miss_due"


def test_unresolved_dependency_blocks_task() -> None:
    request = _request()
    request["tasks"] = [
        {
            "id": "dependent",
            "title": "Dependent",
            "durationMinutes": 15,
            "priority": 5,
            "dependsOn": ["missing"],
        }
    ]
    result = SchedulerCore().plan(request)

    assert result["entries"] == []
    assert result["issues"][0]["code"] == "dependency_blocked"


def test_soft_deadline_fallback_still_uses_low_energy_slot_score() -> None:
    request = _request()
    request["energy"] = "veryLow"
    request["tuning"] = {
        "defaultDurationMultiplier": 1.0,
        "tagDurationMultiplier": {},
        "highLoadPenaltyWhenLowEnergy": 2.0,
    }
    request["windows"] = [
        {"start": {"hour": 8, "minute": 0}, "end": {"hour": 10, "minute": 0}},
        {"start": {"hour": 14, "minute": 0}, "end": {"hour": 16, "minute": 0}},
    ]
    request["tasks"] = [
        {
            "id": "high",
            "title": "High",
            "durationMinutes": 60,
            "priority": 3,
            "load": "high",
            "tag": "Task",
            "due": "2026-09-14T07:00:00+08:00",
        }
    ]

    result = SchedulerCore().plan(request)

    assert result["entries"][0]["time"] == {"hour": 14, "minute": 0}
    assert result["entries"][0]["height"] == 160.0
    assert result["issues"][0]["code"] == "miss_due"


def test_task_with_fixed_id_is_not_scheduled_twice() -> None:
    request = _request()
    request["tasks"] = [
        {
            "id": "fixed-task",
            "title": "Duplicate task",
            "durationMinutes": 20,
            "priority": 5,
        }
    ]
    request["fixed"] = [
        {
            "id": "fixed-task",
            "title": "Already fixed",
            "time": {"hour": 9, "minute": 0},
            "height": 20.0,
        }
    ]
    result = SchedulerCore().plan(request)

    assert [entry["id"] for entry in result["entries"]] == ["fixed-task"]
    assert not [issue for issue in result["issues"] if issue["code"] == "no_slot"]


def test_split_chunks_never_start_before_earliest_start() -> None:
    request = _request()
    request["windows"] = [
        {"start": {"hour": 9, "minute": 0}, "end": {"hour": 10, "minute": 0}},
        {"start": {"hour": 11, "minute": 0}, "end": {"hour": 12, "minute": 0}},
    ]
    request["tasks"] = [
        {
            "id": "split-late",
            "title": "Split late",
            "durationMinutes": 60,
            "priority": 5,
            "splittable": True,
            "minimumChunkMinutes": 30,
            "earliestStart": "2026-09-14T10:30:00+08:00",
        }
    ]
    result = SchedulerCore().plan(request)

    assert result["entries"]
    assert all(
        entry["time"]["hour"] * 60 + entry["time"]["minute"] >= 10 * 60 + 30
        for entry in result["entries"]
    )


def test_conflicted_fixed_entries_still_block_ordinary_tasks() -> None:
    request = _request()
    request["windows"] = [
        {"start": {"hour": 9, "minute": 0}, "end": {"hour": 10, "minute": 0}}
    ]
    request["fixed"] = [
        {"id": "fixed-a", "title": "A", "time": {"hour": 9, "minute": 0}, "height": 80},
        {"id": "fixed-b", "title": "B", "time": {"hour": 9, "minute": 30}, "height": 40},
    ]
    request["tasks"] = [
        {"id": "task", "title": "Task", "durationMinutes": 30, "priority": 5}
    ]
    result = SchedulerCore().plan(request)

    assert not [entry for entry in result["entries"] if entry["id"] == "task"]
    assert any(issue["code"] == "no_slot" for issue in result["issues"])


def test_explanation_codes_are_deterministic_and_deduplicated() -> None:
    request = _request()
    request["tasks"] = []
    request["fixed"] = [
        {
            "id": "baseline",
            "title": "Baseline",
            "time": {"hour": 9, "minute": 0},
            "height": 20.0,
            "explanationCodes": ["kept_baseline", "priority", "kept_baseline", "unknown"],
        }
    ]
    result = SchedulerCore().plan(request)

    assert result["entries"][0]["explanationCodes"] == ["priority", "kept_baseline"]


def test_hard_overdue_task_reports_overdue_even_when_no_slot_exists() -> None:
    request = _request()
    request["windows"] = [
        {"start": {"hour": 10, "minute": 0}, "end": {"hour": 10, "minute": 15}}
    ]
    request["tasks"] = [
        {
            "id": "hard-overdue",
            "title": "Hard overdue",
            "durationMinutes": 30,
            "priority": 5,
            "due": "2026-09-13T09:30:00+08:00",
            "hardDeadline": True,
        }
    ]
    result = SchedulerCore().plan(request)

    assert {issue["code"] for issue in result["issues"]} >= {"no_slot", "overdue"}
