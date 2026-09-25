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


def test_settings_are_persisted_and_isolated_per_user(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "settings.sqlite3")) as client:
        first = _register(client, "settings-first@example.com")
        second = _register(client, "settings-second@example.com")

        updated = client.put(
            "/settings",
            headers=first,
            json={"themeMode": "dark", "locale": "en_US"},
        )
        assert updated.status_code == 200, updated.text
        assert updated.json()["themeMode"] == "dark"
        assert updated.json()["locale"] == "en_US"

        first_read = client.get("/settings", headers=first)
        second_read = client.get("/settings", headers=second)
        assert first_read.json()["themeMode"] == "dark"
        assert first_read.json()["locale"] == "en_US"
        assert second_read.json()["themeMode"] == "system"
        assert second_read.json()["locale"] == "zh_CN"

        invalid = client.put("/settings", headers=first, json={"themeMode": "neon"})
        assert invalid.status_code == 422
