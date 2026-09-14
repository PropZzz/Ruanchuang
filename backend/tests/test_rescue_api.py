"""API tests for the remote schedule-rescue transaction (/schedule/rescue/*)."""

import sqlite3

from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


DAY = "2026-08-09"


def _entry(entry_id, hour=9, minute=0, height=80.0, day=DAY, **over):
    entry = {
        "id": entry_id,
        "day": day,
        "title": f"任务 {entry_id}",
        "tag": "Work",
        "load": "medium",
        "height": height,
        "color": 0,
        "time": {"hour": hour, "minute": minute},
        "reminderMinutesBefore": 10,
        "repeat": "none",
    }
    entry.update(over)
    return entry


def _urgent(**over):
    urgent = {
        "id": "urgent_1",
        "title": "客户紧急问题",
        "durationMinutes": 60,
        "priority": 5,
        "load": "high",
        "tag": "Urgent",
        "due": f"{DAY}T15:30:00+08:00",
    }
    urgent.update(over)
    return urgent


def _options_request(current_entries=None, **over):
    payload = {
        "day": DAY,
        "urgentTask": _urgent(),
        "currentEntries": current_entries or [],
        "energy": "medium",
        "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 18, "minute": 0}}],
    }
    payload.update(over)
    return payload


def _register(client, suffix="user1"):
    response = client.post(
        "/auth/register",
        json={
            "contactAddress": f"{suffix}@example.com",
            "displayName": "Rescue",
            "password": "secret123",
        },
    )
    assert response.status_code == 200
    return response.json()["accessToken"]


def _headers(token):
    return {"Authorization": f"Bearer {token}"}


def _snapshot_rows(db_path):
    with sqlite3.connect(str(db_path)) as connection:
        return connection.execute(
            "SELECT id, user_id, status FROM rescue_snapshots"
        ).fetchall()


def _day_schedules(client, headers):
    response = client.get(f"/schedule?from={DAY}&to={DAY}", headers=headers)
    assert response.status_code == 200
    return sorted(response.json(), key=lambda entry: entry["id"])


def _rescue_reasons(client, headers):
    response = client.get("/events", headers=headers)
    assert response.status_code == 200
    return [
        event["reason"]
        for event in response.json()
        if (event.get("reason") or "").startswith("rescue_")
    ]


def _client_and_token(tmp_path, suffix="user1"):
    reset_token_store()
    client = TestClient(create_app(tmp_path / "rescue.sqlite3"))
    token = _register(client, suffix)
    return client, _headers(token)


# --- options ---


def test_rescue_options_requires_auth(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "rescue.sqlite3")) as client:
        response = client.post("/schedule/rescue/options", json=_options_request())
    assert response.status_code == 401


def test_rescue_options_returns_three_options_with_metadata(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        response = client.post("/schedule/rescue/options", json=_options_request(), headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert [option["strategy"] for option in body["options"]] == [
        "protectDeadline",
        "protectRecovery",
        "minimizeChanges",
    ]
    assert len(body["baselineHash"]) == 64
    for option in body["options"]:
        assert option["id"]
        assert option["title"]
        assert option["rationale"]
        assert option["tradeoff"]
        assert isinstance(option["recommended"], bool)
        assert isinstance(option["movedEntryCount"], int)
        assert isinstance(option["recoveryMinutes"], int)
        assert isinstance(option["issueCount"], int)
        assert isinstance(option["affectedEntries"], list)
        assert isinstance(option["plannedEntries"], list)
    assert sum(1 for option in body["options"] if option["recommended"]) == 1
    assert [option["recoveryMinutes"] for option in body["options"]] == [0, 15, 0]


def test_rescue_options_invalid_strategy_422(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        response = client.post(
            "/schedule/rescue/options",
            json=_options_request(strategies=["nope"]),
            headers=headers,
        )
    assert response.status_code == 422


def test_rescue_options_missing_urgent_due_422(tmp_path):
    client, headers = _client_and_token(tmp_path)
    urgent = _urgent()
    del urgent["due"]
    with client:
        response = client.post(
            "/schedule/rescue/options",
            json=_options_request(urgentTask=urgent),
            headers=headers,
        )
    assert response.status_code == 422


def test_rescue_options_unknown_energy_422(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        response = client.post(
            "/schedule/rescue/options",
            json=_options_request(energy="super"),
            headers=headers,
        )
    assert response.status_code == 422


# --- apply ---


def _seed_and_hash(client, headers):
    seeded = _entry("base_1", hour=9)
    response = client.post("/schedule", json=seeded, headers=headers)
    assert response.status_code == 200
    options = client.post(
        "/schedule/rescue/options",
        json=_options_request(current_entries=[seeded]),
        headers=headers,
    )
    assert options.status_code == 200
    return seeded, options.json()["baselineHash"]


def test_rescue_apply_happy_path(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        seeded, baseline_hash = _seed_and_hash(client, headers)
        after = _entry("new_1", hour=8)
        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "baselineHash": baseline_hash,
                "strategy": "protectDeadline",
                "before": [seeded],
                "after": [after],
                "urgentTask": _urgent(),
                "eventId": "e-acc-1",
                "energy": "medium",
            },
            headers=headers,
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["snapshotId"]
        assert body["eventId"] == "e-acc-1"
        assert [entry["id"] for entry in body["entries"]] == ["new_1"]

        assert [entry["id"] for entry in _day_schedules(client, headers)] == ["new_1"]
        assert "rescue_accept:protectDeadline" in _rescue_reasons(client, headers)
        history = client.get("/schedule/rescue/history", headers=headers)
        assert history.status_code == 200
        assert len(history.json()) == 1
        assert history.json()[0]["reason"] == "rescue_accept:protectDeadline"
    assert _snapshot_rows(tmp_path / "rescue.sqlite3")[0][2] == "active"


def test_rescue_apply_stale_baseline_409(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        seeded, baseline_hash = _seed_and_hash(client, headers)
        modified = _entry("base_1", hour=10)
        response = client.put("/schedule/base_1", json=modified, headers=headers)
        assert response.status_code == 200

        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "baselineHash": baseline_hash,
                "strategy": "protectDeadline",
                "before": [seeded],
                "after": [_entry("new_1", hour=8)],
                "eventId": "e-acc-1",
            },
            headers=headers,
        )
        assert response.status_code == 409
        assert response.json()["detail"]["code"] == "CONFLICT"
        # The modified state survives: apply wrote nothing.
        entries = _day_schedules(client, headers)
        assert [entry["id"] for entry in entries] == ["base_1"]
        assert entries[0]["time"] == {"hour": 10, "minute": 0}
        assert "rescue_accept:protectDeadline" not in _rescue_reasons(client, headers)
    assert _snapshot_rows(tmp_path / "rescue.sqlite3") == []


def test_rescue_apply_cross_user_event_conflict_full_rollback(tmp_path):
    reset_token_store()
    db_path = tmp_path / "rescue.sqlite3"
    with TestClient(create_app(db_path)) as client:
        token1 = _register(client, "user1")
        token2 = _register(client, "user2")
        headers1 = _headers(token1)
        headers2 = _headers(token2)

        seeded, baseline_hash = _seed_and_hash(client, headers1)

        response = client.post(
            "/events",
            json={
                "id": "e-x",
                "taskId": "t2",
                "title": "别人的事件",
                "tag": "Work",
                "at": f"{DAY}T09:00:00",
                "type": "start",
            },
            headers=headers2,
        )
        assert response.status_code == 200

        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "baselineHash": baseline_hash,
                "strategy": "protectDeadline",
                "before": [seeded],
                "after": [_entry("new_1", hour=8)],
                "eventId": "e-x",
            },
            headers=headers1,
        )
        assert response.status_code == 409
        # Full rollback: schedules untouched, no snapshot, no accept event.
        assert [entry["id"] for entry in _day_schedules(client, headers1)] == ["base_1"]
        assert "rescue_accept:protectDeadline" not in _rescue_reasons(client, headers1)
    assert _snapshot_rows(db_path) == []


def test_rescue_apply_duplicate_ids_in_after_422(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        seeded, baseline_hash = _seed_and_hash(client, headers)
        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "baselineHash": baseline_hash,
                "strategy": "protectDeadline",
                "before": [seeded],
                "after": [_entry("new_1", hour=8), _entry("new_1", hour=9)],
            },
            headers=headers,
        )
    assert response.status_code == 422


def test_rescue_apply_blank_id_in_after_422(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        seeded, baseline_hash = _seed_and_hash(client, headers)
        blank = _entry("new_1", hour=8)
        blank["id"] = ""
        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "baselineHash": baseline_hash,
                "strategy": "protectDeadline",
                "before": [seeded],
                "after": [blank],
            },
            headers=headers,
        )
    assert response.status_code == 422


def test_rescue_apply_invalid_strategy_422(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        seeded, baseline_hash = _seed_and_hash(client, headers)
        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "baselineHash": baseline_hash,
                "strategy": "nope",
                "before": [seeded],
                "after": [_entry("new_1", hour=8)],
            },
            headers=headers,
        )
    assert response.status_code == 422


def test_rescue_apply_missing_baseline_hash_422(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "strategy": "protectDeadline",
                "before": [],
                "after": [_entry("new_1", hour=8)],
            },
            headers=headers,
        )
    assert response.status_code == 422


def test_rescue_apply_requires_auth(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "rescue.sqlite3")) as client:
        response = client.post(
            "/schedule/rescue/apply",
            json={
                "day": DAY,
                "baselineHash": "0" * 64,
                "strategy": "protectDeadline",
                "before": [],
                "after": [_entry("new_1", hour=8)],
            },
        )
    assert response.status_code == 401


# --- undo ---


def _apply_rescue(client, headers, baseline, baseline_hash, event_id="e-acc-1"):
    response = client.post(
        "/schedule/rescue/apply",
        json={
            "day": DAY,
            "baselineHash": baseline_hash,
            "strategy": "protectDeadline",
            "before": baseline,
            "after": [_entry("new_1", hour=8), _entry("new_2", hour=11)],
            "urgentTask": _urgent(),
            "eventId": event_id,
            "energy": "medium",
        },
        headers=headers,
    )
    assert response.status_code == 200
    return response.json()["snapshotId"]


def test_rescue_undo_restores_baseline_exactly(tmp_path):
    client, headers = _client_and_token(tmp_path)
    db_path = tmp_path / "rescue.sqlite3"
    with client:
        baseline = [_entry("base_1", hour=9), _entry("base_2", hour=14)]
        for entry in baseline:
            response = client.post("/schedule", json=entry, headers=headers)
            assert response.status_code == 200
        options = client.post(
            "/schedule/rescue/options",
            json=_options_request(current_entries=baseline),
            headers=headers,
        )
        baseline_hash = options.json()["baselineHash"]
        snapshot_id = _apply_rescue(client, headers, baseline, baseline_hash)

        response = client.post(
            "/schedule/rescue/undo",
            json={"snapshotId": snapshot_id, "eventId": "e-und-1"},
            headers=headers,
        )
        assert response.status_code == 200, response.text
        assert response.json()["eventId"] == "e-und-1"

        def _strip_nones(entries):
            return [
                {key: value for key, value in entry.items() if value is not None}
                for entry in entries
            ]

        restored = _strip_nones(_day_schedules(client, headers))
        assert restored == sorted(baseline, key=lambda entry: entry["id"])
        assert "rescue_accept:protectDeadline" in _rescue_reasons(client, headers)
        assert "rescue_undo:protectDeadline" in _rescue_reasons(client, headers)

        # Second undo on the same snapshot is a conflict and changes nothing.
        response = client.post(
            "/schedule/rescue/undo",
            json={"snapshotId": snapshot_id},
            headers=headers,
        )
        assert response.status_code == 409
        assert _strip_nones(_day_schedules(client, headers)) == sorted(
            baseline, key=lambda entry: entry["id"]
        )
    assert _snapshot_rows(db_path)[0][2] == "undone"


def test_rescue_undo_foreign_user_snapshot_404(tmp_path):
    reset_token_store()
    db_path = tmp_path / "rescue.sqlite3"
    with TestClient(create_app(db_path)) as client:
        token1 = _register(client, "user1")
        token2 = _register(client, "user2")
        headers1 = _headers(token1)
        headers2 = _headers(token2)

        baseline = [_entry("base_1", hour=9)]
        response = client.post("/schedule", json=baseline[0], headers=headers1)
        assert response.status_code == 200
        options = client.post(
            "/schedule/rescue/options",
            json=_options_request(current_entries=baseline),
            headers=headers1,
        )
        snapshot_id = _apply_rescue(
            client, headers1, baseline, options.json()["baselineHash"]
        )

        response = client.post(
            "/schedule/rescue/undo",
            json={"snapshotId": snapshot_id},
            headers=headers2,
        )
        assert response.status_code == 404
        assert response.json()["detail"]["code"] == "NOT_FOUND"
    assert _snapshot_rows(db_path)[0][2] == "active"


def test_rescue_undo_unknown_snapshot_404(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        response = client.post(
            "/schedule/rescue/undo",
            json={"snapshotId": "missing"},
            headers=headers,
        )
    assert response.status_code == 404


def test_rescue_undo_requires_auth(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "rescue.sqlite3")) as client:
        response = client.post("/schedule/rescue/undo", json={"snapshotId": "x"})
    assert response.status_code == 401


# --- history ---


def test_rescue_history_filters_and_sorts(tmp_path):
    client, headers = _client_and_token(tmp_path)
    with client:
        events = [
            {
                "id": "h-1",
                "taskId": "t1",
                "title": "接受",
                "tag": "Urgent",
                "at": f"{DAY}T10:00:00",
                "type": "interrupt",
                "reason": "rescue_accept:protectDeadline",
            },
            {
                "id": "h-2",
                "taskId": "t1",
                "title": "普通事件",
                "tag": "Work",
                "at": f"{DAY}T11:00:00",
                "type": "start",
                "reason": "meeting",
            },
            {
                "id": "h-3",
                "taskId": "t1",
                "title": "撤销",
                "tag": "Urgent",
                "at": f"{DAY}T12:00:00",
                "type": "interrupt",
                "reason": "rescue_undo:protectDeadline",
            },
        ]
        response = client.post("/events/batch", json=events, headers=headers)
        assert response.status_code == 200

        response = client.get("/schedule/rescue/history", headers=headers)
        assert response.status_code == 200
        reasons = [event["reason"] for event in response.json()]
        assert reasons == ["rescue_undo:protectDeadline", "rescue_accept:protectDeadline"]

        response = client.get(
            f"/schedule/rescue/history?from={DAY}T09:00:00&to={DAY}T11:30:00",
            headers=headers,
        )
        assert response.status_code == 200
        assert [event["reason"] for event in response.json()] == ["rescue_accept:protectDeadline"]
