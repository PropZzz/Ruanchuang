from datetime import date

from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _register(client: TestClient, address: str = "platform@example.com") -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={
            "contactAddress": address,
            "displayName": "Platform User",
            "password": "secret123",
        },
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def test_logout_revokes_the_current_token(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "platform.sqlite3")) as client:
        headers = _register(client)

        logout = client.post("/auth/logout", headers=headers)

        assert logout.status_code == 204
        assert client.get("/auth/me", headers=headers).status_code == 401


def test_profile_update_is_scoped_to_authenticated_user(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "profile.sqlite3")) as client:
        headers = _register(client)

        response = client.put("/auth/profile", headers=headers, json={"displayName": "Updated Name"})

        assert response.status_code == 200, response.text
        assert response.json()["displayName"] == "Updated Name"
        assert client.get("/auth/me", headers=headers).json()["displayName"] == "Updated Name"


def test_version_and_server_time_expose_compatibility_metadata(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "metadata.sqlite3")) as client:
        headers = _register(client)

        version = client.get("/version", headers=headers)
        server_time = client.get("/server/time", headers=headers)

        assert version.status_code == 200, version.text
        assert version.json()["apiVersion"] == "0.1.0"
        assert isinstance(version.json()["clientCompatibility"], str)
        assert server_time.status_code == 200, server_time.text
        assert server_time.json()["timezone"] == "UTC"
        assert isinstance(server_time.json()["unixMillis"], int)
        assert "T" in server_time.json()["serverTime"]


def test_diagnostics_counts_only_the_authenticated_user(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "diagnostics.sqlite3")) as client:
        first = _register(client, "first@example.com")
        client.post(
            "/schedule",
            headers=first,
            json={
                "title": "Only first user",
                "tag": "test",
                "day": date.today().isoformat(),
                "time": {"hour": 9, "minute": 0},
            },
        )
        second = _register(client, "second@example.com")

        response = client.get("/diagnostics/summary", headers=second)

        assert response.status_code == 200, response.text
        assert response.json()["counts"]["schedules"] == 0
        assert response.json()["database"] == "sqlite"
