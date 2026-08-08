from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def test_auth_and_repository_flow(tmp_path):
    db_path = tmp_path / "api-flow.sqlite3"
    reset_token_store()
    with TestClient(create_app(db_path)) as client:
        register_payload = {
            "contactAddress": "alice@example.com",
            "displayName": "Alice",
            "password": "secret123",
        }

        register_response = client.post("/auth/register", json=register_payload)
        assert register_response.status_code == 200
        register_body = register_response.json()
        assert register_body["tokenType"] == "Bearer"
        assert register_body["accessToken"]
        assert register_body["user"]["contactAddress"] == "alice@example.com"
        assert register_body["user"]["displayName"] == "Alice"

        token = register_body["accessToken"]

        me_response = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
        assert me_response.status_code == 200
        me_body = me_response.json()
        assert me_body["contactAddress"] == "alice@example.com"
        assert me_body["displayName"] == "Alice"

        login_response = client.post(
            "/auth/login",
            json={"contactAddress": "alice@example.com", "password": "secret123"},
        )
        assert login_response.status_code == 200
        login_body = login_response.json()
        assert login_body["accessToken"]
        assert login_body["user"]["contactAddress"] == "alice@example.com"

        headers = {"Authorization": f"Bearer {token}"}

        schedule_input = {
            "id": "sch-1",
            "title": "Deep Work",
            "tag": "Focus",
            "load": "high",
            "goalId": "goal-1",
            "goalTaskId": "task-1",
            "height": 72.5,
            "color": 4278255360,
            "time": {"hour": 9, "minute": 30},
            "reminderMinutesBefore": 15,
            "repeat": "daily",
            "repeatUntil": "2026-06-20",
        }
        saved_schedule = client.post("/schedule", json=schedule_input, headers=headers)
        assert saved_schedule.status_code == 200
        saved_schedule_body = saved_schedule.json()
        assert saved_schedule_body["goalId"] == "goal-1"
        assert saved_schedule_body["goalTaskId"] == "task-1"
        assert saved_schedule_body["reminderMinutesBefore"] == 15

        schedules = client.get("/schedule", headers=headers)
        assert schedules.status_code == 200
        assert len(schedules.json()) == 1
        assert schedules.json()[0]["title"] == "Deep Work"

        updated_schedule = client.put(
            "/schedule/sch-1",
            json={**saved_schedule_body, "title": "Deep Work Updated"},
            headers=headers,
        )
        assert updated_schedule.status_code == 200
        assert updated_schedule.json()["title"] == "Deep Work Updated"
        assert len(client.get("/schedule", headers=headers).json()) == 1

        microtask_input = {
            "id": "mt-1",
            "title": "Write notes",
            "tag": "Study",
            "minutes": 25,
            "priority": 4,
            "requirement": "Finish the summary",
            "done": False,
        }
        saved_microtask = client.post("/microtasks", json=microtask_input, headers=headers)
        assert saved_microtask.status_code == 200
        assert saved_microtask.json()["title"] == "Write notes"
        assert saved_microtask.json()["priority"] == 4
        assert saved_microtask.json()["done"] is False

        microtasks = client.get("/microtasks", headers=headers)
        assert microtasks.status_code == 200
        assert len(microtasks.json()) == 1
        assert microtasks.json()[0]["tag"] == "Study"

        plan_response = client.post(
            "/schedule/replan",
            json={
                "day": "2026-06-14",
                "energy": "high",
                "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 12, "minute": 0}}],
                "fixed": [],
                "tasks": [
                    {
                        "id": "u",
                        "title": "Urgent",
                        "durationMinutes": 30,
                        "priority": 5,
                        "load": "medium",
                        "tag": "Urgent",
                        "due": "2026-06-14T10:00:00",
                    }
                ],
            },
            headers=headers,
        )
        assert plan_response.status_code == 200
        assert plan_response.json()["entries"][0]["id"] == "u"

        crystal_response = client.post(
            "/microtasks/recommend-crystals",
            json={
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
            },
            headers=headers,
        )
        assert crystal_response.status_code == 200
        assert crystal_response.json()[0]["task"]["id"] == "m1"

        client.delete("/schedule/sch-1", headers=headers)
        client.delete("/microtasks/mt-1", headers=headers)

        assert client.get("/schedule", headers=headers).json() == []
        assert client.get("/microtasks", headers=headers).json() == []
