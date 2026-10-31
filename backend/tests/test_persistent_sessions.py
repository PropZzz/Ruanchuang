from __future__ import annotations

import hashlib
from pathlib import Path
import sqlite3
import subprocess
import sys

import pytest
from starlette.testclient import TestClient

from backend.main import create_app


ACCOUNT = {"contactAddress": "session@example.test", "displayName": "Session", "password": "secret123"}


def _register(client: TestClient) -> dict:
    response = client.post("/auth/register", json=ACCOUNT)
    assert response.status_code == 200, response.text
    return response.json()


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def test_session_survives_app_and_process_restart_and_logout_is_durable(tmp_path):
    database = tmp_path / "sessions.sqlite3"
    with TestClient(create_app(database)) as client:
        account = _register(client)
    token = account["accessToken"]
    probe = subprocess.run(
        [sys.executable, "-c", "from backend.auth import resolve_token; import sys; print(resolve_token(sys.argv[1], sys.argv[2]) or '')", token, str(database)],
        cwd=Path(__file__).resolve().parents[2], capture_output=True, text=True, timeout=15,
    )
    assert probe.returncode == 0, probe.stderr
    assert probe.stdout.strip() == account["user"]["id"]

    with TestClient(create_app(database)) as restarted:
        assert restarted.get("/auth/me", headers=_headers(token)).json()["id"] == account["user"]["id"]
        assert restarted.post("/auth/logout", headers=_headers(token)).status_code == 204
    with TestClient(create_app(database)) as after_logout:
        assert after_logout.get("/auth/me", headers=_headers(token)).status_code == 401


def test_tokens_are_hashed_and_scoped_to_the_application_database(tmp_path):
    first_db = tmp_path / "first.sqlite3"
    with TestClient(create_app(first_db)) as first, TestClient(create_app(tmp_path / "second.sqlite3")) as second:
        account = _register(first)
        _register(second)
        token = account["accessToken"]
        assert first.get("/schedule", headers=_headers(token)).status_code == 200
        assert second.get("/schedule", headers=_headers(token)).status_code == 401

    with sqlite3.connect(first_db) as connection:
        row = connection.execute("SELECT token_hash, user_id, expires_at - created_at FROM auth_sessions").fetchone()
    assert row == (hashlib.sha256(token.encode()).hexdigest(), account["user"]["id"], 604800)
    assert token.encode() not in first_db.read_bytes()


def test_expired_tokens_are_rejected_and_pruned(tmp_path, monkeypatch):
    now = {"seconds": 1000.0}
    monkeypatch.setattr("backend.session_store.time.time", lambda: now["seconds"])
    monkeypatch.setenv("SHIXUZHIPEI_SESSION_TTL_SECONDS", "2")
    database = tmp_path / "expired.sqlite3"
    with TestClient(create_app(database)) as client:
        token = _register(client)["accessToken"]
        assert client.get("/auth/me", headers=_headers(token)).status_code == 200
        now["seconds"] = 1002.0
        assert client.get("/auth/me", headers=_headers(token)).status_code == 401
        with sqlite3.connect(database) as connection:
            assert connection.execute("SELECT count(*) FROM auth_sessions").fetchone()[0] == 0


@pytest.mark.parametrize("value", ["0", "-1", "not-a-number"])
def test_invalid_session_lifetime_fails_at_startup(tmp_path, monkeypatch, value):
    monkeypatch.setenv("SHIXUZHIPEI_SESSION_TTL_SECONDS", value)
    with pytest.raises(ValueError):
        create_app(tmp_path / "invalid.sqlite3")


def test_cors_accepts_only_configured_origins(tmp_path, monkeypatch):
    allowed = "https://app.example.test"
    monkeypatch.setenv("SHIXUZHIPEI_CORS_ORIGINS", allowed + ",http://127.0.0.1:5353")
    with TestClient(create_app(tmp_path / "cors.sqlite3")) as client:
        trusted = client.options("/schedule", headers={"Origin": allowed, "Access-Control-Request-Method": "GET"})
        assert trusted.status_code == 200
        assert trusted.headers["access-control-allow-origin"] == allowed
        rejected = client.options("/schedule", headers={"Origin": "https://untrusted.example.test", "Access-Control-Request-Method": "GET"})
        assert rejected.status_code == 400
        assert "access-control-allow-origin" not in rejected.headers
        unauthorized = client.get("/schedule", headers={"Origin": allowed})
        assert unauthorized.status_code == 401
        assert unauthorized.headers["access-control-allow-origin"] == allowed


@pytest.mark.parametrize("value", ["*", "https://app.example.test/path", "https://user:password@app.example.test", "null"])
def test_invalid_cors_origin_fails_at_startup(tmp_path, monkeypatch, value):
    monkeypatch.setenv("SHIXUZHIPEI_CORS_ORIGINS", value)
    with pytest.raises(ValueError):
        create_app(tmp_path / "invalid.sqlite3")
