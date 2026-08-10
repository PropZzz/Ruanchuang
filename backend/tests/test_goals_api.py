from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _headers(client: TestClient, account: str) -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={
            "contactAddress": account,
            "displayName": account.split("@")[0],
            "password": "secret123",
        },
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def _goal(goal_id: str = "goal-1", **overrides):
    return {
        "id": goal_id,
        "title": "Ship review loop",
        "due": "2026-08-30T18:00:00",
        "priority": 5,
        "tasks": [
            {
                "id": "goal-task-1",
                "title": "Write acceptance tests",
                "durationMinutes": 45,
                "load": "medium",
                "tag": "Goal",
                "done": False,
                "dependsOn": [],
            }
        ],
        **overrides,
    }


def test_goals_require_authentication(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "goals.sqlite3")) as client:
        response = client.get("/goals")

    assert response.status_code == 401


def test_goal_crud_and_goal_task_endpoints_roundtrip(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "goals.sqlite3")) as client:
        headers = _headers(client, "goals@example.com")

        created = client.post("/goals", json=_goal(), headers=headers)
        assert created.status_code == 200
        assert created.json()["id"] == "goal-1"
        assert created.json()["tasks"][0]["id"] == "goal-task-1"

        listed = client.get("/goals", headers=headers)
        assert listed.status_code == 200
        assert [goal["id"] for goal in listed.json()] == ["goal-1"]

        updated = client.put(
            "/goals/goal-1",
            json={**created.json(), "title": "Ship polished review loop", "priority": 4},
            headers=headers,
        )
        assert updated.status_code == 200
        assert updated.json()["title"] == "Ship polished review loop"
        assert updated.json()["priority"] == 4

        new_task = {
            "id": "goal-task-2",
            "title": "Connect remote API",
            "durationMinutes": 30,
            "load": "high",
            "tag": "Backend",
            "done": False,
            "dependsOn": ["goal-task-1"],
        }
        added_task = client.post(
            "/goals/goal-1/tasks",
            json=new_task,
            headers=headers,
        )
        assert added_task.status_code == 200
        assert [task["id"] for task in added_task.json()["tasks"]] == [
            "goal-task-1",
            "goal-task-2",
        ]

        task_updated = client.put(
            "/goals/goal-1/tasks/goal-task-2",
            json={**new_task, "done": True},
            headers=headers,
        )
        assert task_updated.status_code == 200
        assert task_updated.json()["tasks"][1]["done"] is True

        deleted = client.delete("/goals/goal-1", headers=headers)
        assert deleted.status_code == 204
        assert client.get("/goals", headers=headers).json() == []


def test_goal_ids_are_isolated_and_cross_user_conflicts_are_rejected(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "goals.sqlite3")) as client:
        alice_headers = _headers(client, "alice-goals@example.com")
        bob_headers = _headers(client, "bob-goals@example.com")

        assert client.post("/goals", json=_goal("shared-goal"), headers=alice_headers).status_code == 200

        bob_conflict = client.post("/goals", json=_goal("shared-goal"), headers=bob_headers)
        assert bob_conflict.status_code == 409

        bob_list = client.get("/goals", headers=bob_headers)
        assert bob_list.status_code == 200
        assert bob_list.json() == []


def test_goal_task_duplicate_and_missing_goal_are_rejected(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "goals.sqlite3")) as client:
        headers = _headers(client, "goal-task-errors@example.com")
        assert client.post("/goals", json=_goal(), headers=headers).status_code == 200

        duplicate = client.post(
            "/goals/goal-1/tasks",
            json=_goal()["tasks"][0],
            headers=headers,
        )
        assert duplicate.status_code == 409

        missing = client.post(
            "/goals/missing-goal/tasks",
            json={
                "id": "task-x",
                "title": "Missing parent",
                "durationMinutes": 10,
                "load": "low",
                "tag": "Goal",
                "done": False,
                "dependsOn": [],
            },
            headers=headers,
        )
        assert missing.status_code == 404
