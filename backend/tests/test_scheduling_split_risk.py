from __future__ import annotations

from backend.scheduling.core import SchedulerCore
from backend.scheduling_contract import SchedulingRequest, to_contract_response


def _request() -> dict[str, object]:
    return {
        "schemaVersion": "1",
        "day": "2026-09-14",
        "tasks": [
            {
                "id": "split-task",
                "title": "Split task",
                "durationMinutes": 90,
                "priority": 3,
                "load": "medium",
                "tag": "Task",
                "splittable": True,
                "minimumChunkMinutes": 30,
            }
        ],
        "windows": [
            {"start": {"hour": 9, "minute": 0}, "end": {"hour": 10, "minute": 0}},
            {"start": {"hour": 11, "minute": 0}, "end": {"hour": 12, "minute": 0}},
        ],
        "energy": "medium",
        "tuning": {
            "defaultDurationMultiplier": 1.0,
            "tagDurationMultiplier": {},
            "highLoadPenaltyWhenLowEnergy": 1.0,
        },
        "fixed": [],
    }


def test_splittable_task_uses_multiple_entries_and_preserves_total_duration() -> None:
    request = SchedulingRequest.model_validate(_request())
    result = SchedulerCore().plan(request.to_engine_request())
    chunks = [entry for entry in result["entries"] if entry["id"].startswith("split-task#")]
    assert [entry["id"] for entry in chunks] == ["split-task#1", "split-task#2"]
    assert sum(round(entry["height"] / 80 * 60) for entry in chunks) == 90


def test_contract_response_includes_risk_object() -> None:
    request = SchedulingRequest.model_validate(_request())
    response = to_contract_response(
        {"entries": [], "issues": [{"code": "no_slot", "message": "No slot", "taskId": "split-task"}]},
        request,
    ).model_dump(mode="json", by_alias=True, exclude_none=True)
    assert response["risk"] == {"level": "high", "issueCount": 1, "hardIssueCount": 1}
