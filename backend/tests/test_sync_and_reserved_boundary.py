from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _register(client: TestClient, address: str) -> dict[str, str]:
    response = client.post("/auth/register", json={"contactAddress": address, "displayName": address, "password": "secret123"})
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def test_sync_status_pull_push_and_user_isolation(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "sync.sqlite3")) as client:
        first = _register(client, "sync-first@example.com")
        second = _register(client, "sync-second@example.com")

        status = client.get("/sync/status", headers=first)
        assert status.status_code == 200
        assert status.json()["cursor"] == 0

        push = client.post(
            "/sync/push",
            headers=first,
            json={"changes": [{"entity": "schedule", "operation": "upsert", "payload": {"id": "sync-1", "day": "2026-09-07", "title": "Synced", "tag": "Sync", "time": {"hour": 9, "minute": 0}}}]},
        )
        assert push.status_code == 200, push.text
        assert push.json()["applied"] == ["sync-1"]

        pulled = client.get("/sync/pull?since=0", headers=first)
        assert pulled.status_code == 200, pulled.text
        assert pulled.json()["changes"][0]["entityId"] == "sync-1"
        assert client.get("/schedule", headers=second).json() == []
        assert client.get("/sync/pull?since=0", headers=second).json()["changes"] == []

        invalid = client.post(
            "/sync/push",
            headers=first,
            json={"changes": [{"entity": "schedule", "operation": "upsert", "payload": {"id": "sync-2", "title": "Should not persist"}}, {"entity": "unknown", "operation": "upsert", "payload": {"id": "bad"}}]},
        )
        assert invalid.status_code == 422
        schedule_ids = {entry["id"] for entry in client.get("/schedule", headers=first).json()}
        assert schedule_ids == {"sync-1"}


def test_reserved_external_capabilities_keep_explicit_501_boundary(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "reserved-boundary.sqlite3")) as client:
        headers = _register(client, "reserved-boundary@example.com")
        for method, path in (("POST", "/ai/parse-task"), ("GET", "/devices"), ("GET", "/integrations/providers"), ("POST", "/files/upload"), ("POST", "/notifications/test")):
            response = client.request(method, path, headers=headers, json={} if method == "POST" else None)
            assert response.status_code == 501, f"{method} {path}"
            assert response.json()["detail"]["code"] == "RESERVED_ENDPOINT"
