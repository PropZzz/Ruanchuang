from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _event(event_id: str, **overrides):
    return {
        "id": event_id,
        "taskId": "task-1",
        "title": "Event",
        "tag": "Focus",
        "load": "medium",
        "at": "2026-08-06T09:00:00",
        "type": "start",
        "plannedMinutes": 25,
        "energy": "high",
        "actualMinutes": None,
        "interruptions": None,
        "reason": None,
        **overrides,
    }


def test_task_event_log_and_query_roundtrip(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "events.sqlite3")) as client:
        register = client.post(
            "/auth/register",
            json={
                "contactAddress": "events@example.com",
                "displayName": "Events",
                "password": "secret123",
            },
        )
        assert register.status_code == 200
        token = register.json()["accessToken"]
        headers = {"Authorization": f"Bearer {token}"}

        event = {
            "id": "rescue-1",
            "taskId": "urgent-1",
            "title": "客户紧急问题",
            "tag": "Urgent",
            "load": "medium",
            "at": "2026-08-06T09:00:00",
            "type": "interrupt",
            "plannedMinutes": 30,
            "energy": "low",
            "actualMinutes": None,
            "interruptions": None,
            "reason": "rescue_accept:protectRecovery",
        }

        saved = client.post("/events", json=event, headers=headers)
        assert saved.status_code == 200
        assert saved.json()["id"] == "rescue-1"

        listed = client.get(
            "/events",
            params={
                "from": "2026-08-06T00:00:00",
                "to": "2026-08-07T00:00:00",
            },
            headers=headers,
        )
        assert listed.status_code == 200
        assert listed.json() == [event]


def test_task_event_batch_upsert_replaces_by_id(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "events.sqlite3")) as client:
        register = client.post(
            "/auth/register",
            json={
                "contactAddress": "batch-events@example.com",
                "displayName": "Batch Events",
                "password": "secret123",
            },
        )
        assert register.status_code == 200
        headers = {"Authorization": f"Bearer {register.json()['accessToken']}"}

        first = {
            "id": "batch-1",
            "taskId": "task-1",
            "title": "First",
            "tag": "Focus",
            "load": "medium",
            "at": "2026-08-06T09:00:00",
            "type": "start",
            "plannedMinutes": 25,
            "energy": "high",
            "actualMinutes": None,
            "interruptions": None,
            "reason": None,
        }
        second = {
            "id": "batch-2",
            "taskId": "task-2",
            "title": "Second",
            "tag": "Study",
            "load": "low",
            "at": "2026-08-06T10:00:00",
            "type": "complete",
            "plannedMinutes": 15,
            "energy": "medium",
            "actualMinutes": 12,
            "interruptions": 1,
            "reason": "finished",
        }

        saved = client.post(
            "/events/batch",
            json=[first, second],
            headers=headers,
        )
        assert saved.status_code == 200
        assert [event["id"] for event in saved.json()] == ["batch-1", "batch-2"]

        updated_first = {**first, "title": "First updated", "actualMinutes": 30}
        updated = client.post(
            "/events/batch",
            json=[updated_first],
            headers=headers,
        )
        assert updated.status_code == 200
        assert updated.json()[0]["title"] == "First updated"

        listed = client.get(
            "/events",
            params={
                "from": "2026-08-06T00:00:00",
                "to": "2026-08-07T00:00:00",
            },
            headers=headers,
        )
        assert listed.status_code == 200
        assert len(listed.json()) == 2
        by_id = {event["id"]: event for event in listed.json()}
        assert by_id["batch-1"]["title"] == "First updated"
        assert by_id["batch-1"]["actualMinutes"] == 30


def test_task_event_id_conflict_is_rejected_across_users_for_single_and_batch(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "events.sqlite3")) as client:
        alice = client.post(
            "/auth/register",
            json={
                "contactAddress": "alice-events@example.com",
                "displayName": "Alice Events",
                "password": "secret123",
            },
        )
        bob = client.post(
            "/auth/register",
            json={
                "contactAddress": "bob-events@example.com",
                "displayName": "Bob Events",
                "password": "secret123",
            },
        )
        assert alice.status_code == 200
        assert bob.status_code == 200
        alice_headers = {"Authorization": f"Bearer {alice.json()['accessToken']}"}
        bob_headers = {"Authorization": f"Bearer {bob.json()['accessToken']}"}

        original = _event("shared-event", title="Alice's event")
        saved = client.post("/events", json=original, headers=alice_headers)
        assert saved.status_code == 200

        single_conflict = client.post(
            "/events",
            json=_event("shared-event", title="Bob's single-event overwrite"),
            headers=bob_headers,
        )
        assert single_conflict.status_code == 409

        batch_conflict = client.post(
            "/events/batch",
            json=[_event("shared-event", title="Bob's batch overwrite")],
            headers=bob_headers,
        )
        assert batch_conflict.status_code == 409

        unchanged = client.get("/events", headers=alice_headers)
        assert unchanged.status_code == 200
        assert unchanged.json() == [original]


def test_task_event_batch_rejects_duplicate_ids_before_writing(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "events.sqlite3")) as client:
        register = client.post(
            "/auth/register",
            json={
                "contactAddress": "duplicate-events@example.com",
                "displayName": "Duplicate Events",
                "password": "secret123",
            },
        )
        assert register.status_code == 200
        headers = {"Authorization": f"Bearer {register.json()['accessToken']}"}

        response = client.post(
            "/events/batch",
            json=[
                _event("duplicate-event", title="First"),
                _event("duplicate-event", title="Second"),
            ],
            headers=headers,
        )

        assert response.status_code == 422
        assert client.get("/events", headers=headers).json() == []


def test_task_event_batch_rejects_blank_ids_before_writing(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "events.sqlite3")) as client:
        register = client.post(
            "/auth/register",
            json={
                "contactAddress": "blank-events@example.com",
                "displayName": "Blank Events",
                "password": "secret123",
            },
        )
        assert register.status_code == 200
        headers = {"Authorization": f"Bearer {register.json()['accessToken']}"}

        response = client.post(
            "/events/batch",
            json=[_event("   "), _event("valid-event")],
            headers=headers,
        )

        assert response.status_code == 422
        assert client.get("/events", headers=headers).json() == []
