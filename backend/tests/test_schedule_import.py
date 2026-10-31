import sqlite3

from starlette.testclient import TestClient

from backend.main import create_app
from backend.repositories import init_db


def register(client, contact="import@example.com"):
    response = client.post("/auth/register", json={
        "contactAddress": contact, "displayName": "导入验证", "password": "test-import-only",
    })
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def entry(identifier="import-1", **extra):
    return {"id": identifier, "title": "数据库课程", "tag": "上课学习", "day": "2026-09-07",
            "time": {"hour": 10, "minute": 0}, "height": 120, **extra}


def test_notes_survive_old_database_create_edit_batch_and_omitted_field(tmp_path):
    database = tmp_path / "old.sqlite3"
    init_db(database)
    with sqlite3.connect(database) as connection:
        connection.execute("ALTER TABLE schedules DROP COLUMN description")
    with TestClient(create_app(database)) as client:
        headers = register(client)
        created = client.post("/schedule", headers=headers, json=entry(description="王老师 · B座507"))
        assert created.status_code == 200, created.text
        assert created.json()["description"] == "王老师 · B座507"
        edited = client.put("/schedule/import-1", headers=headers, json=entry(description="新教室"))
        assert edited.status_code == 200
        assert edited.json()["description"] == "新教室"
        legacy = client.put("/schedule/import-1", headers=headers, json=entry())
        assert legacy.json()["description"] == "新教室"
        batch = client.post("/schedule/batch", headers=headers, json=[entry(description=""), entry("import-2", description="李老师")])
        assert batch.status_code == 200, batch.text
        assert [row["description"] for row in batch.json()] == ["", "李老师"]
        stored = {row["id"]: row for row in client.get("/schedule", headers=headers).json()}
        assert stored["import-1"]["description"] == ""
        assert stored["import-2"]["description"] == "李老师"
        cleared = client.put("/schedule/import-2", headers=headers, json=entry("import-2", description=None))
        assert cleared.json()["description"] is None


def test_create_only_import_never_overwrites_an_existing_edit(tmp_path):
    with TestClient(create_app(tmp_path / "repeat.sqlite3")) as client:
        headers = register(client)
        client.post("/schedule", headers=headers, json=entry(title="用户改过的标题", description="用户备注"))
        response = client.post("/schedule/batch?createOnly=true", headers=headers,
                               json=[entry(description="原始导入"), entry("new", description="新课程")])
        assert response.status_code == 200, response.text
        assert [row["id"] for row in response.json()] == ["new"]
        stored = {row["id"]: row for row in client.get("/schedule", headers=headers).json()}
        assert stored["import-1"]["title"] == "用户改过的标题"
        assert stored["import-1"]["description"] == "用户备注"


def test_batch_conflict_rolls_back_all_writes_and_keeps_accounts_isolated(tmp_path):
    with TestClient(create_app(tmp_path / "atomic.sqlite3")) as client:
        first = register(client)
        second = register(client, "other@example.com")
        assert client.post("/schedule", headers=first, json=entry()).status_code == 200
        conflict = client.post("/schedule/batch", headers=second, json=[entry("new-entry"), entry()])
        assert conflict.status_code == 409
        assert client.get("/schedule", headers=second).json() == []
        assert client.get("/schedule", headers=first).json()[0]["title"] == "数据库课程"


def test_import_notes_survive_rescue_options_apply_undo_and_legacy_client(tmp_path):
    from backend.tests.test_rescue_api import _entry, _options_request, DAY

    with TestClient(create_app(tmp_path / "notes-rescue.sqlite3")) as client:
        headers = register(client)
        created = client.post("/schedule", headers=headers, json=_entry("import-course", description="王老师 · B座507")).json()
        # Old native clients omit this optional field when serializing schedules.
        legacy = {key: value for key, value in created.items() if key != "description"}
        options = client.post("/schedule/rescue/options", headers=headers, json=_options_request([legacy])).json()
        chosen = next(option for option in options["options"] if option["strategy"] == "minimizeChanges")
        assert next(row for row in chosen["plannedEntries"] if row["id"] == created["id"])["description"] == "王老师 · B座507"
        apply_body = {"day": DAY, "strategy": "minimizeChanges", "baselineHash": options["baselineHash"],
                      "before": [legacy], "after": [{key: value for key, value in row.items() if key != "description"} for row in chosen["plannedEntries"]],
                      "eventId": "notes-rescue", "energy": "medium"}
        applied = client.post("/schedule/rescue/apply", headers=headers, json=apply_body)
        assert applied.status_code == 200, applied.text
        assert next(row for row in applied.json()["entries"] if row["id"] == created["id"])["description"] == "王老师 · B座507"
        undone = client.post("/schedule/rescue/undo", headers=headers, json={"snapshotId": applied.json()["snapshotId"]})
        assert undone.status_code == 200, undone.text
        assert client.get("/schedule", headers=headers).json()[0]["description"] == "王老师 · B座507"
        client.put("/schedule/import-course", headers=headers, json={**created, "description": "已换教室"})
        assert client.post("/schedule/rescue/apply", headers=headers, json=apply_body).status_code == 409
