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
