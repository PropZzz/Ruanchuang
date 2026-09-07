from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={"contactAddress": "schedule@example.com", "displayName": "Schedule", "password": "secret123"},
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def _entry(entry_id: str, title: str, hour: int, minutes: int = 60) -> dict[str, object]:
    return {
        "id": entry_id,
        "day": "2026-09-07",
        "title": title,
        "tag": "work",
        "load": "medium",
        "height": minutes * 80 / 60,
        "color": 1,
        "time": {"hour": hour, "minute": 0},
    }


def test_schedule_batch_is_atomic_and_conflicts_are_reported(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "batch.sqlite3")) as client:
        headers = _headers(client)
        response = client.post("/schedule/batch", headers=headers, json=[_entry("a", "A", 9), _entry("b", "B", 9)])
        assert response.status_code == 200, response.text
        assert len(response.json()) == 2

        conflicts = client.get("/schedule/conflicts?day=2026-09-07", headers=headers)
        assert conflicts.status_code == 200, conflicts.text
        assert len(conflicts.json()["conflicts"]) == 1
        assert conflicts.json()["baselineHash"]

        invalid = client.post("/schedule/batch", headers=headers, json=[_entry("c", "C", 10), {"title": "missing tag"}])
        assert invalid.status_code == 422
        assert {entry["id"] for entry in client.get("/schedule", headers=headers).json()} == {"a", "b"}


def test_ics_import_and_export_round_trip(tmp_path):
    reset_token_store()
    ics = "\r\n".join(
        [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "BEGIN:VEVENT",
            "UID:ics-1",
            "DTSTART:20260907T090000",
            "DTEND:20260907T100000",
            "SUMMARY:Imported\, task",
            "CATEGORIES:Focus",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ]
    )
    with TestClient(create_app(tmp_path / "ics.sqlite3")) as client:
        headers = _headers(client)
        imported = client.post("/schedule/import-ics", headers=headers, json={"ics": ics})
        assert imported.status_code == 200, imported.text
        assert imported.json()[0]["title"] == "Imported, task"
        exported = client.get("/schedule/export-ics?from=2026-09-07&to=2026-09-07", headers=headers)
        assert exported.status_code == 200
        assert "BEGIN:VCALENDAR" in exported.text
        assert "SUMMARY:Imported\\, task" in exported.text


def test_rescue_apply_undo_and_stale_baseline_are_transactional(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "rescue.sqlite3")) as client:
        headers = _headers(client)
        client.post("/schedule", headers=headers, json=_entry("baseline", "Baseline", 9))
        options_response = client.post(
            "/schedule/rescue/options",
            headers=headers,
            json={
                "day": "2026-09-07",
                "urgentTask": {
                    "id": "urgent",
                    "title": "Urgent",
                    "durationMinutes": 30,
                    "priority": 5,
                    "load": "high",
                    "tag": "Urgent",
                    "due": "2026-09-07T15:30:00",
                },
                "currentEntries": [_entry("baseline", "Baseline", 9)],
                "energy": "medium",
            },
        )
        assert options_response.status_code == 200, options_response.text
        option = options_response.json()["options"][0]
        apply_response = client.post(
            "/schedule/rescue/apply",
            headers=headers,
            json={
                "strategy": option["strategy"],
                "baselineHash": options_response.json()["baselineHash"],
                "before": [_entry("baseline", "Baseline", 9)],
                "after": option["plannedEntries"],
            },
        )
        assert apply_response.status_code == 200, apply_response.text
        snapshot_id = apply_response.json()["snapshotId"]
        assert any(event["reason"].startswith("rescue_accept:") for event in client.get("/events", headers=headers).json())

        stale = client.post(
            "/schedule/rescue/apply",
            headers=headers,
            json={"strategy": "protectDeadline", "baselineHash": "stale", "before": [], "after": []},
        )
        assert stale.status_code == 409

        undo = client.post("/schedule/rescue/undo", headers=headers, json={"snapshotId": snapshot_id})
        assert undo.status_code == 200, undo.text
        assert [entry["id"] for entry in client.get("/schedule", headers=headers).json()] == ["baseline"]
        assert any(event["reason"].startswith("rescue_undo:") for event in client.get("/events", headers=headers).json())
