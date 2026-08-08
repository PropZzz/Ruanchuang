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
