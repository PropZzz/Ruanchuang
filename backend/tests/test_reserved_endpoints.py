from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


RESERVED_ENDPOINTS = [
    ("GET", "/diagnostics/summary"),
    ("GET", "/version"),
    ("GET", "/server/time"),
    ("POST", "/auth/logout"),
    ("POST", "/auth/refresh"),
    ("PUT", "/auth/profile"),
    ("POST", "/auth/password/reset-request"),
    ("POST", "/auth/password/reset-confirm"),
    ("POST", "/schedule/import-ics"),
    ("GET", "/schedule/export-ics"),
    ("GET", "/schedule/conflicts"),
    ("POST", "/schedule/batch"),
    ("DELETE", "/events/event-1"),
    ("POST", "/microtasks/batch-complete"),
    ("POST", "/microtasks/batch-schedule"),
    ("POST", "/microtasks/import"),
    ("POST", "/goals/goal-1/schedule-next"),
    ("POST", "/goals/decompose"),
    ("POST", "/team/conflicts"),
    ("POST", "/team/golden-windows"),
    ("POST", "/team/book-meeting"),
    ("GET", "/reminders"),
    ("POST", "/reminders"),
    ("PUT", "/reminders/reminder-1"),
    ("DELETE", "/reminders/reminder-1"),
    ("POST", "/notifications/devices"),
    ("DELETE", "/notifications/devices/device-1"),
    ("POST", "/notifications/test"),
    ("GET", "/devices"),
    ("POST", "/devices"),
    ("DELETE", "/devices/device-1"),
    ("POST", "/devices/device-1/samples"),
    ("GET", "/devices/device-1/status"),
    ("PUT", "/devices/device-1/permissions"),
    ("GET", "/integrations/providers"),
    ("POST", "/integrations/calendar-google/connect"),
    ("POST", "/integrations/calendar-google/callback"),
    ("DELETE", "/integrations/calendar-google"),
    ("POST", "/integrations/calendar-google/import"),
    ("GET", "/integrations/calendar-google/sync-status"),
    ("POST", "/ai/parse-task"),
    ("POST", "/ai/decompose-goal"),
    ("POST", "/ai/explain-plan"),
    ("POST", "/ai/review-suggestions"),
    ("POST", "/ai/tuning"),
    ("POST", "/files/upload"),
    ("GET", "/files/file-1"),
    ("DELETE", "/files/file-1"),
    ("POST", "/files/parse-task-list"),
    ("GET", "/sync/pull"),
    ("POST", "/sync/push"),
    ("GET", "/sync/status"),
    ("POST", "/sync/conflicts/conflict-1/resolve"),
]


def _headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={
            "contactAddress": "reserved@example.com",
            "displayName": "Reserved",
            "password": "secret123",
        },
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def _request(client: TestClient, method: str, path: str, headers: dict[str, str] | None = None):
    return client.request(method, path, json={} if method in {"POST", "PUT"} else None, headers=headers)


def test_reserved_endpoints_require_authentication(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "reserved.sqlite3")) as client:
        response = _request(client, "GET", "/diagnostics/summary")

    assert response.status_code == 401


def test_reserved_endpoints_return_explicit_reserved_error(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "reserved.sqlite3")) as client:
        headers = _headers(client)

        for method, path in RESERVED_ENDPOINTS:
            response = _request(client, method, path, headers=headers)
            assert response.status_code == 501, f"{method} {path}"
            body = response.json()
            assert body["detail"]["code"] == "RESERVED_ENDPOINT"
            assert body["detail"]["status"] == "Reserved"


def test_reserved_endpoints_are_visible_in_openapi(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "reserved.sqlite3")) as client:
        paths = client.get("/openapi.json").json()["paths"]

    expected_paths = {
        path.replace("goal-1", "{goal_id}")
        .replace("task-1", "{task_id}")
        .replace("event-1", "{event_id}")
        .replace("member-1", "{member_id}")
        .replace("reminder-1", "{reminder_id}")
        .replace("device-1", "{device_id}")
        .replace("calendar-google", "{provider}")
        .replace("file-1", "{file_id}")
        .replace("conflict-1", "{conflict_id}")
        for _, path in RESERVED_ENDPOINTS
    }

    assert expected_paths.issubset(paths.keys())
