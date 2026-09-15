from backend.services_microtask import recommend_crystals
from backend.services_scheduling import plan_schedule


def test_plan_schedule_places_urgent_before_due():
    plan = plan_schedule(
        {
            "day": "2026-06-14",
            "energy": "high",
            "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 12, "minute": 0}}],
            "fixed": [],
            "tasks": [
                {
                    "id": "a",
                    "title": "Deep",
                    "durationMinutes": 90,
                    "priority": 3,
                    "load": "high",
                    "tag": "Deep Work",
                },
                {
                    "id": "u",
                    "title": "Urgent",
                    "durationMinutes": 30,
                    "priority": 5,
                    "load": "medium",
                    "tag": "Urgent",
                    "due": "2026-06-14T10:00:00",
                },
            ],
        }
    )
    assert plan["entries"][0]["id"] == "u"
    urgent = next(e for e in plan["entries"] if e["id"] == "u")
    end = urgent["time"]["hour"] * 60 + urgent["time"]["minute"] + 30
    assert end <= 10 * 60


def test_recommend_crystals_fits_microtask_into_gap():
    recs = recommend_crystals(
        {
            "schedule": [
                {"title": "Busy", "tag": "Work", "height": 80.0, "time": {"hour": 9, "minute": 0}},
            ],
            "microTasks": [
                {"id": "m1", "title": "整理笔记", "tag": "低脑力", "minutes": 10, "priority": 3, "done": False},
            ],
            "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 10, "minute": 0}}],
            "energy": "low",
            "now": {"hour": 8, "minute": 0},
            "maxRecommendations": 3,
        }
    )
    assert len(recs) == 1
    assert recs[0]["task"]["id"] == "m1"


def test_plan_schedule_uses_contract_order_for_due_priority_duration_and_id():
    plan = plan_schedule(
        {
            "day": "2026-06-14",
            "energy": "high",
            "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 18, "minute": 0}}],
            "fixed": [],
            "tasks": [
                {"id": "no-due-short", "title": "Short", "durationMinutes": 20, "priority": 3, "load": "low", "tag": "Task"},
                {"id": "due-late", "title": "Late due", "durationMinutes": 20, "priority": 1, "due": "2026-06-14T12:00:00", "load": "low", "tag": "Task"},
                {"id": "no-due-long", "title": "Long", "durationMinutes": 30, "priority": 3, "load": "low", "tag": "Task"},
                {"id": "due-early", "title": "Early due", "durationMinutes": 20, "priority": 1, "due": "2026-06-14T10:00:00", "load": "low", "tag": "Task"},
                {"id": "no-due-high", "title": "High", "durationMinutes": 20, "priority": 5, "load": "low", "tag": "Task"},
                {"id": "no-due-a", "title": "A", "durationMinutes": 20, "priority": 3, "load": "low", "tag": "Task"},
            ],
        }
    )

    assert [entry["id"] for entry in plan["entries"]] == [
        "due-early",
        "due-late",
        "no-due-high",
        "no-due-long",
        "no-due-a",
        "no-due-short",
    ]


def test_plan_schedule_blocks_missing_dependency_with_ids_and_metadata():
    plan = plan_schedule(
        {
            "day": "2026-06-14",
            "energy": "high",
            "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 12, "minute": 0}}],
            "fixed": [],
            "tasks": [
                {"id": "dependent", "title": "Dependent", "durationMinutes": 30, "priority": 5, "load": "high", "tag": "Task", "dependsOn": ["missing"]},
            ],
        }
    )

    assert plan["entries"] == []
    assert plan["issues"] == [
        {
            "code": "dependency_blocked",
            "message": "Task cannot be scheduled until its dependency is placed",
            "taskId": "dependent",
            "blockedBy": ["missing"],
            "explanationCodes": [],
        }
    ]


def test_plan_schedule_applies_earliest_start_and_hard_deadline_without_fallback():
    plan = plan_schedule(
        {
            "day": "2026-06-14",
            "energy": "medium",
            "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 10, "minute": 0}}],
            "fixed": [],
            "tasks": [
                {"id": "late", "title": "Late", "durationMinutes": 30, "priority": 2, "load": "low", "tag": "Task", "earliestStart": "2026-06-14T09:00:00"},
                {"id": "hard", "title": "Hard", "durationMinutes": 90, "priority": 5, "load": "high", "tag": "Task", "due": "2026-06-14T09:00:00", "hardDeadline": True},
            ],
        }
    )

    late = next(entry for entry in plan["entries"] if entry["id"] == "late")
    assert late["time"] == {"hour": 9, "minute": 0}
    assert not any(entry["id"] == "hard" for entry in plan["entries"])
    hard_issue = next(issue for issue in plan["issues"] if issue["taskId"] == "hard")
    assert hard_issue["code"] == "no_slot"
    assert hard_issue["explanationCodes"] == ["deadline_proximity"]
