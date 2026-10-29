from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _register(client: TestClient, address: str) -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={"contactAddress": address, "displayName": address, "password": "secret123"},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def _schedule(entry_id: str, title: str = "Deep work") -> dict[str, object]:
    return {
        "id": entry_id,
        "day": "2026-10-29",
        "title": title,
        "tag": "Focus",
        "load": "medium",
        "height": 80,
        "color": 1,
        "time": {"hour": 9, "minute": 0},
    }


def _microtask(task_id: str, title: str = "Reply mail") -> dict[str, object]:
    return {
        "id": task_id,
        "title": title,
        "tag": "Mail",
        "minutes": 10,
        "priority": 2,
        "done": False,
    }


def test_schedule_id_conflict_across_users_returns_409(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "schedule-isolation.sqlite3")) as client:
        alice = _register(client, "alice-schedule@example.com")
        bob = _register(client, "bob-schedule@example.com")

        created = client.post("/schedule", json=_schedule("shared-entry", "Alice entry"), headers=alice)
        assert created.status_code == 200, created.text

        single = client.post("/schedule", json=_schedule("shared-entry", "Bob overwrite"), headers=bob)
        assert single.status_code == 409, single.text
        assert "shared-entry" in single.json()["detail"]

        batch = client.post("/schedule/batch", json=[_schedule("shared-entry", "Bob batch")], headers=bob)
        assert batch.status_code == 409, batch.text

        update = client.put("/schedule/shared-entry", json=_schedule("shared-entry", "Bob put"), headers=bob)
        assert update.status_code == 409, update.text

        # 冲突不得修改原用户数据，也不得在对方账号下产生副本。
        assert [item["title"] for item in client.get("/schedule", headers=alice).json()] == ["Alice entry"]
        assert client.get("/schedule", headers=bob).json() == []

        # 同一用户自己的更新仍然是幂等 upsert，不能被误判为冲突。
        owned = client.put("/schedule/shared-entry", json=_schedule("shared-entry", "Alice updated"), headers=alice)
        assert owned.status_code == 200, owned.text
        assert owned.json()["title"] == "Alice updated"


def test_microtask_id_conflict_across_users_returns_409(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "microtask-isolation.sqlite3")) as client:
        alice = _register(client, "alice-micro@example.com")
        bob = _register(client, "bob-micro@example.com")

        created = client.post("/microtasks", json=_microtask("shared-task", "Alice task"), headers=alice)
        assert created.status_code == 200, created.text

        single = client.post("/microtasks", json=_microtask("shared-task", "Bob create"), headers=bob)
        assert single.status_code == 409, single.text

        update = client.put("/microtasks/shared-task", json=_microtask("shared-task", "Bob put"), headers=bob)
        assert update.status_code == 409, update.text

        assert [item["title"] for item in client.get("/microtasks", headers=alice).json()] == ["Alice task"]
        assert client.get("/microtasks", headers=bob).json() == []

        owned = client.put("/microtasks/shared-task", json=_microtask("shared-task", "Alice updated"), headers=alice)
        assert owned.status_code == 200, owned.text
        assert owned.json()["title"] == "Alice updated"
