import sqlite3

import pytest
from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app
from backend.repositories import (
    init_db, list_schedules, replace_schedules_with_snapshot,
    schedule_baseline_hash, undo_schedule_snapshot,
)


def register(client, name="constraints"):
    response = client.post("/auth/register", json={
        "contactAddress": f"{name}@example.com", "displayName": name, "password": "secret123",
    })
    assert response.status_code == 200
    data = response.json()
    return {"Authorization": f"Bearer {data['accessToken']}"}, data["user"]["id"]


def entry(**overrides):
    return {"id": "policy", "day": "2026-11-05", "title": "课程", "tag": "上课学习",
            "height": 80, "time": {"hour": 9, "minute": 0}, **overrides}


@pytest.mark.parametrize("flexible,locked", [(False, False), (False, True), (True, False)])
def test_schedule_constraints_persist_and_old_client_updates_keep_them(tmp_path, flexible, locked):
    reset_token_store()
    path = tmp_path / "constraints.db"
    with TestClient(create_app(path)) as client:
        headers, user_id = register(client)
        payload = entry(rescheduleFlexible=flexible, hardLocked=locked)
        created = client.post("/schedule", headers=headers, json=payload)
        assert created.status_code == 200
        assert created.json()["rescheduleFlexible"] is flexible
        assert created.json()["hardLocked"] is locked
        assert client.get("/schedule", headers=headers).json()[0] == created.json()
        # Native/older clients omit the newly added fields on PUT and batch.
        updated = client.put("/schedule/policy", headers=headers, json=entry(title="仅改标题"))
        assert updated.status_code == 200
        assert updated.json()["rescheduleFlexible"] is flexible
        assert updated.json()["hardLocked"] is locked
        batch = client.post("/schedule/batch", headers=headers, json=[entry(title="批量编辑")])
        assert batch.status_code == 200
        assert batch.json()[0]["rescheduleFlexible"] is flexible
        assert batch.json()[0]["hardLocked"] is locked
        saved = list_schedules(path, user_id)[0]
        assert saved["rescheduleFlexible"] is flexible
        assert saved["hardLocked"] is locked
        other, _ = register(client, "other")
        assert client.get("/schedule", headers=other).json() == []
        # Explicit values must still be able to clear a previous setting.
        flipped = client.put("/schedule/policy", headers=headers,
                             json=entry(rescheduleFlexible=not flexible, hardLocked=flexible))
        assert flipped.json()["rescheduleFlexible"] is not flexible
        assert flipped.json()["hardLocked"] is flexible


def test_constraints_batch_sync_and_snapshot_round_trip(tmp_path):
    reset_token_store()
    path = tmp_path / "paths.db"
    with TestClient(create_app(path)) as client:
        headers, user_id = register(client)
        payload = entry(rescheduleFlexible=False, hardLocked=True)
        batch = client.post("/schedule/batch", headers=headers, json=[payload])
        assert batch.status_code == 200
        assert batch.json()[0]["hardLocked"] is True
        synced = client.post("/sync/push", headers=headers, json={"changes": [{
            "entity": "schedule", "operation": "upsert", "payload": {**payload, "id": "synced"},
        }]})
        assert synced.status_code == 200
        before = list_schedules(path, user_id)
        assert all(row["hardLocked"] and not row["rescheduleFlexible"] for row in before)
        applied = replace_schedules_with_snapshot(path, user_id, before, before, "minimizeChanges",
                                                  schedule_baseline_hash(path, user_id))
        assert list_schedules(path, user_id) == before
        undo_schedule_snapshot(path, user_id, applied["snapshotId"])
        assert list_schedules(path, user_id) == before
    # New app/connection reads the actual persisted columns.
    with TestClient(create_app(path)) as client:
        login = client.post("/auth/login", json={"contactAddress": "constraints@example.com", "password": "secret123"})
        records = client.get("/schedule", headers={"Authorization": f"Bearer {login.json()['accessToken']}"}).json()
        assert all(row["hardLocked"] and not row["rescheduleFlexible"] for row in records)


def test_existing_database_migrates_without_replacing_entries(tmp_path):
    reset_token_store()
    path = tmp_path / "old.db"
    with TestClient(create_app(path)) as client:
        headers, user_id = register(client)
        assert client.post("/schedule", headers=headers, json=entry()).status_code == 200
    with sqlite3.connect(path) as connection:
        for column in ("reschedule_flexible", "hard_locked"):
            if column in {row[1] for row in connection.execute("PRAGMA table_info(schedules)")}:
                connection.execute(f"ALTER TABLE schedules DROP COLUMN {column}")
    init_db(path)
    init_db(path)
    record = list_schedules(path, user_id)[0]
    assert record["id"] == "policy"
    assert record["rescheduleFlexible"] is True
    assert record["hardLocked"] is False


@pytest.mark.parametrize("field", ["rescheduleFlexible", "hardLocked"])
@pytest.mark.parametrize("value", [None, "false", 2, {}, []])
def test_constraint_flags_reject_non_boolean_values(tmp_path, field, value):
    reset_token_store()
    with TestClient(create_app(tmp_path / "validation.db")) as client:
        headers, _ = register(client)
        response = client.post("/schedule", headers=headers, json=entry(**{field: value}))
        assert response.status_code == 422
        assert client.get("/schedule", headers=headers).json() == []


def test_rescue_round_trip_keeps_flags_and_policy_changes_invalidate_baseline(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "rescue-flags.db")) as client:
        headers, _ = register(client)
        created = client.post("/schedule", headers=headers, json=entry(rescheduleFlexible=False, hardLocked=True)).json()
        request = {"day": created["day"], "currentEntries": [created], "energy": "medium",
                   "urgentTask": {"id": "urgent", "title": "紧急事项", "durationMinutes": 15, "priority": 5,
                                  "load": "low", "tag": "Urgent", "due": "2026-11-05T17:00:00Z"}}
        options = client.post("/schedule/rescue/options", headers=headers, json=request).json()
        option = next(row for row in options["options"] if row["strategy"] == "minimizeChanges")
        preserved = next(row for row in option["plannedEntries"] if row["id"] == created["id"])
        assert preserved["rescheduleFlexible"] is False
        assert preserved["hardLocked"] is True
        apply_request = {"day": created["day"], "strategy": option["strategy"], "baselineHash": options["baselineHash"],
                         "before": [created], "after": option["plannedEntries"]}
        applied = client.post("/schedule/rescue/apply", headers=headers, json=apply_request)
        assert applied.status_code == 200, applied.text
        saved = next(row for row in applied.json()["entries"] if row["id"] == created["id"])
        assert saved["rescheduleFlexible"] is False and saved["hardLocked"] is True
        undone = client.post("/schedule/rescue/undo", headers=headers, json={"snapshotId": applied.json()["snapshotId"]})
        assert undone.status_code == 200, undone.text
        assert client.get("/schedule", headers=headers).json() == [created]
        client.put("/schedule/policy", headers=headers, json={**created, "hardLocked": False})
        stale = client.post("/schedule/rescue/apply", headers=headers, json=apply_request)
        assert stale.status_code == 409, stale.text


def test_rescue_options_preserve_flags_when_original_entry_is_moved():
    from backend.services_rescue import build_options

    original = entry(rescheduleFlexible=False, hardLocked=True)
    result = build_options({"day": original["day"], "currentEntries": [original], "energy": "medium",
                            "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 18, "minute": 0}}],
                            "urgentTask": {"id": "urgent", "title": "Urgent", "durationMinutes": 15,
                                           "priority": 5, "load": "low", "tag": "Urgent"}})
    for option in result["options"]:
        row = next(row for row in option["plannedEntries"] if row["id"] == original["id"])
        assert row["rescheduleFlexible"] is False and row["hardLocked"] is True


def test_all_write_routes_reject_both_constraints_enabled(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "exclusive.db")) as client:
        headers, _ = register(client)
        payload = entry(rescheduleFlexible=True, hardLocked=True)
        for method, path, body in [
            ("POST", "/schedule", payload),
            ("PUT", "/schedule/policy", payload),
            ("POST", "/schedule/batch", [payload]),
            ("POST", "/sync/push", {"changes": [{"entity": "schedule", "operation": "upsert", "payload": payload}]}),
        ]:
            response = client.request(method, path, headers=headers, json=body)
            assert response.status_code == 422, (path, response.text)
            assert client.get("/schedule", headers=headers).json() == []


def test_enabling_one_constraint_alone_disables_the_other(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "partial.db")) as client:
        headers, _ = register(client)
        response = client.post("/schedule", headers=headers, json=entry(hardLocked=True))
        assert response.status_code == 200, response.text
        assert response.json()["hardLocked"] is True
        assert response.json()["rescheduleFlexible"] is False
        for field, other in [("rescheduleFlexible", "hardLocked"), ("hardLocked", "rescheduleFlexible")]:
            response = client.put("/schedule/policy", headers=headers, json=entry(**{field: True}))
            assert response.status_code == 200, response.text
            assert response.json()[field] is True
            assert response.json()[other] is False


def test_legacy_double_enabled_rows_and_snapshots_are_repaired(tmp_path):
    import json

    reset_token_store()
    path = tmp_path / "legacy-exclusive.db"
    with TestClient(create_app(path)) as client:
        headers, user_id = register(client)
        original = client.post("/schedule", headers=headers, json=entry()).json()
        with sqlite3.connect(path) as connection:
            connection.execute("UPDATE schedules SET reschedule_flexible=1, hard_locked=1")
        init_db(path)
        init_db(path)
        repaired = list_schedules(path, user_id)
        assert len(repaired) == 1
        assert repaired[0]["hardLocked"] is True and repaired[0]["rescheduleFlexible"] is False
        assert repaired[0]["title"] == original["title"]
        applied = replace_schedules_with_snapshot(path, user_id, repaired, repaired, "minimizeChanges",
                                                  schedule_baseline_hash(path, user_id))
        with sqlite3.connect(path) as connection:
            connection.execute("UPDATE rescue_snapshots SET before_json=? WHERE id=?",
                               (json.dumps([{**original, "rescheduleFlexible": True, "hardLocked": True}]), applied["snapshotId"]))
        undone = undo_schedule_snapshot(path, user_id, applied["snapshotId"])
        assert undone["entries"][0]["rescheduleFlexible"] is False
        assert undone["entries"][0]["hardLocked"] is True
        assert list_schedules(path, user_id)[0]["rescheduleFlexible"] is False
