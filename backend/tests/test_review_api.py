from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={
            "contactAddress": "review@example.com",
            "displayName": "Review",
            "password": "secret123",
        },
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def _event(event_id: str, **overrides):
    return {
        "id": event_id,
        "taskId": "task-1",
        "title": "Focus block",
        "tag": "Focus",
        "load": "medium",
        "at": "2026-08-03T09:00:00",
        "type": "start",
        "plannedMinutes": 30,
        "energy": "medium",
        "actualMinutes": None,
        "interruptions": None,
        "reason": None,
        **overrides,
    }


def test_weekly_review_generates_report_and_updates_tuning(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "review.sqlite3")) as client:
        headers = _headers(client)
        events = [
            _event("start-1", taskId="task-1", title="Focus one", tag="Focus"),
            _event(
                "complete-1",
                taskId="task-1",
                title="Focus one",
                tag="Focus",
                type="complete",
                actualMinutes=50,
            ),
            _event("start-2", taskId="task-2", title="Focus two", tag="Focus"),
            _event(
                "complete-2",
                taskId="task-2",
                title="Focus two",
                tag="Focus",
                type="complete",
                actualMinutes=45,
            ),
        ]
        assert client.post("/events/batch", json=events, headers=headers).status_code == 200

        response = client.get(
            "/review/weekly",
            params={"week_start": "2026-08-03"},
            headers=headers,
        )

        assert response.status_code == 200
        body = response.json()
        assert body["startedCount"] == 2
        assert body["completedCount"] == 2
        assert body["completionRate"] == 1.0
        assert body["plannedMinutesTotal"] == 60
        assert body["actualMinutesTotal"] == 95
        assert body["actualDurationBuckets"]["31-60"] == 2
        assert body["delayAttribution"]["underestimated"] == 2
        assert body["tuning"]["tagDurationMultiplier"]["Focus"] == 1.15

        tuning = client.get("/review/tuning", headers=headers)
        assert tuning.status_code == 200
        assert tuning.json()["tagDurationMultiplier"]["Focus"] == 1.15


def test_review_tuning_can_be_read_written_and_applied(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "review.sqlite3")) as client:
        headers = _headers(client)
        payload = {
            "defaultDurationMultiplier": 1.1,
            "tagDurationMultiplier": {"Writing": 1.25},
            "highLoadPenaltyWhenLowEnergy": 1.4,
        }

        saved = client.put("/review/tuning", json=payload, headers=headers)
        assert saved.status_code == 200
        assert saved.json() == payload

        loaded = client.get("/review/tuning", headers=headers)
        assert loaded.status_code == 200
        assert loaded.json() == payload

        applied = client.post(
            "/review/tuning/apply",
            json={
                "tuning": {
                    "defaultDurationMultiplier": 1.0,
                    "tagDurationMultiplier": {"Writing": 1.3, "Review": 1.15},
                    "highLoadPenaltyWhenLowEnergy": 1.6,
                }
            },
            headers=headers,
        )
        assert applied.status_code == 200
        assert applied.json()["tagDurationMultiplier"]["Review"] == 1.15
        assert applied.json()["highLoadPenaltyWhenLowEnergy"] == 1.6


def test_review_rescue_history_filters_accept_and_undo_events(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "review.sqlite3")) as client:
        headers = _headers(client)
        events = [
            _event(
                "accept",
                taskId="urgent-1",
                title="客户紧急问题",
                tag="Urgent",
                type="interrupt",
                at="2026-08-06T09:00:00",
                reason="rescue_accept:protectRecovery",
            ),
            _event(
                "undo",
                taskId="urgent-1",
                title="客户紧急问题",
                tag="Urgent",
                type="interrupt",
                at="2026-08-06T10:00:00",
                reason="rescue_undo:protectRecovery",
            ),
            _event(
                "normal",
                taskId="task-2",
                title="普通打断",
                tag="Focus",
                type="interrupt",
                at="2026-08-06T11:00:00",
                reason="meeting",
            ),
        ]
        assert client.post("/events/batch", json=events, headers=headers).status_code == 200

        response = client.get(
            "/review/rescue-history",
            params={
                "from": "2026-08-06T00:00:00",
                "to": "2026-08-07T00:00:00",
            },
            headers=headers,
        )

        assert response.status_code == 200
        body = response.json()
        assert [event["id"] for event in body] == ["undo", "accept"]
        assert {event["reason"] for event in body} == {
            "rescue_accept:protectRecovery",
            "rescue_undo:protectRecovery",
        }
