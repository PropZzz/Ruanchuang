from starlette.testclient import TestClient

from backend.auth import resolve_token
from backend.database import BUSY_TIMEOUT_MS, get_connection
from backend.main import create_app
from backend.repositories import RepositoryConflictError


def test_sqlite_connections_use_wal_and_busy_timeout(tmp_path):
    connection = get_connection(tmp_path / "pragma.sqlite3")
    try:
        journal_mode = connection.execute("PRAGMA journal_mode").fetchone()[0]
        busy_timeout = connection.execute("PRAGMA busy_timeout").fetchone()[0]
    finally:
        connection.close()

    assert str(journal_mode).lower() == "wal"
    assert busy_timeout == BUSY_TIMEOUT_MS


def test_logout_forgets_the_token_instead_of_keeping_it(tmp_path):
    with TestClient(create_app(tmp_path / "auth.sqlite3")) as client:
        registered = client.post(
            "/auth/register",
            json={
                "contactAddress": "logout@example.com",
                "displayName": "Logout",
                "password": "secret123",
            },
        )
        assert registered.status_code == 200, registered.text
        token = registered.json()["accessToken"]
        headers = {"Authorization": f"Bearer {token}"}

        assert client.get("/auth/me", headers=headers).status_code == 200

        logout = client.post("/auth/logout", headers=headers)
        assert logout.status_code == 204

        assert resolve_token(token, tmp_path / "auth.sqlite3") is None
        assert client.get("/auth/me", headers=headers).status_code == 401

        login = client.post(
            "/auth/login",
            json={"contactAddress": "logout@example.com", "password": "secret123"},
        )
        assert login.status_code == 200
        fresh_headers = {"Authorization": f"Bearer {login.json()['accessToken']}"}
        assert client.get("/auth/me", headers=fresh_headers).status_code == 200


def test_unhandled_repository_errors_are_mapped_instead_of_500(tmp_path):
    app = create_app(tmp_path / "handler.sqlite3")

    @app.get("/__test/repository-conflict")
    def repository_conflict() -> None:
        raise RepositoryConflictError("Schedule id already belongs to another user: shared")

    with TestClient(app) as client:
        response = client.get("/__test/repository-conflict")

    assert response.status_code == 409
    assert response.json()["detail"].startswith("Schedule id already belongs")


def test_registration_rejects_blank_fields_and_short_passwords(tmp_path):
    with TestClient(create_app(tmp_path / "register.sqlite3")) as client:
        valid = {
            "contactAddress": "  padded@example.com  ",
            "displayName": "  Padded  ",
            "password": "secret123",
        }

        assert client.post("/auth/register", json={**valid, "contactAddress": "   "}).status_code == 422
        assert client.post("/auth/register", json={**valid, "displayName": "  "}).status_code == 422
        assert client.post("/auth/register", json={**valid, "password": "12345"}).status_code == 422

        created = client.post("/auth/register", json=valid)
        assert created.status_code == 200, created.text
        # 账号与昵称在入库前去除首尾空格，避免产生“看起来一样但登录不上”的账号。
        assert created.json()["user"]["contactAddress"] == "padded@example.com"
        assert created.json()["user"]["displayName"] == "Padded"

        login = client.post(
            "/auth/login",
            json={"contactAddress": " padded@example.com ", "password": "secret123"},
        )
        assert login.status_code == 200, login.text

