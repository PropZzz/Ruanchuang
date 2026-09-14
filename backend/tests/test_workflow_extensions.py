from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={"contactAddress": "workflow@example.com", "displayName": "Workflow", "password": "secret123"},
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def _microtask(task_id: str, title: str = "Task") -> dict[str, object]:
    return {"id": task_id, "title": title, "tag": "Work", "minutes": 30, "priority": 3, "done": False}


def _busy(member_id: str, title: str, hour: int) -> dict[str, object]:
    return {
        "memberId": member_id,
        "displayName": member_id,
        "role": "Engineer",
        "energy": "high",
        "permission": "details",
        "busy": [{"id": f"{member_id}-busy", "day": "2026-09-07", "title": title, "tag": "Meeting", "height": 80, "color": 1, "time": {"hour": hour, "minute": 0}}],
    }


def test_microtask_batch_completion_schedule_and_import(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "microtasks.sqlite3")) as client:
        headers = _headers(client)
        client.post("/microtasks", headers=headers, json=_microtask("m1"))
        client.post("/microtasks", headers=headers, json=_microtask("m2"))

        complete = client.post("/microtasks/batch-complete", headers=headers, json={"taskIds": ["m1"]})
        assert complete.status_code == 200, complete.text
        assert complete.json()[0]["done"] is True

        scheduled = client.post("/microtasks/batch-schedule", headers=headers, json={"taskIds": ["m2"], "day": "2026-09-07", "start": {"hour": 10, "minute": 0}})
        assert scheduled.status_code == 200, scheduled.text
        assert scheduled.json()[0]["goalTaskId"] == "m2"

        imported = client.post("/microtasks/import", headers=headers, json={"text": "Inbox one #Email\nInbox two"})
        assert imported.status_code == 200, imported.text
        assert len(imported.json()) == 2


def test_goal_schedule_next_respects_dependencies(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "goals.sqlite3")) as client:
        headers = _headers(client)
        goal = client.post(
            "/goals",
            headers=headers,
            json={
                "id": "goal-1",
                "title": "Ship",
                "due": "2026-09-08T18:00:00",
                "priority": 5,
                "tasks": [
                    {"id": "first", "title": "First", "durationMinutes": 20, "load": "low", "tag": "Goal", "done": True},
                    {"id": "next", "title": "Next", "durationMinutes": 30, "load": "medium", "tag": "Goal", "dependsOn": ["first"]},
                ],
            },
        )
        assert goal.status_code == 200, goal.text
        response = client.post("/goals/goal-1/schedule-next", headers=headers, json={"day": "2026-09-07", "start": {"hour": 11, "minute": 0}})
        assert response.status_code == 200, response.text
        assert response.json()["goalTaskId"] == "next"


def test_team_conflicts_windows_and_meeting_booking(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "team.sqlite3")) as client:
        headers = _headers(client)
        client.post("/team/members", headers=headers, json=_busy("a", "A busy", 9))
        client.post("/team/members", headers=headers, json=_busy("b", "B busy", 10))

        conflicts = client.post("/team/conflicts", headers=headers, json={"memberIds": ["a", "b"], "day": "2026-09-07", "start": {"hour": 9, "minute": 0}, "minutes": 120})
        assert conflicts.status_code == 200, conflicts.text
        assert conflicts.json()["conflicts"]

        windows = client.post("/team/golden-windows", headers=headers, json={"memberIds": ["a", "b"], "day": "2026-09-07", "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 13, "minute": 0}}], "minutes": 30})
        assert windows.status_code == 200, windows.text
        assert windows.json()["windows"]

        meeting = client.post("/team/book-meeting", headers=headers, json={"day": "2026-09-07", "title": "Planning", "start": {"hour": 14, "minute": 0}, "minutes": 30, "participantIds": ["a", "b"]})
        assert meeting.status_code == 200, meeting.text
        assert meeting.json()["title"] == "Planning"
