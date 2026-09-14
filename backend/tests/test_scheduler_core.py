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
