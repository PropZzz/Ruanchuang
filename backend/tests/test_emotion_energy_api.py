from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app


def _headers(client: TestClient, account: str) -> dict[str, str]:
    response = client.post(
        "/auth/register",
        json={
            "contactAddress": account,
            "displayName": account.split("@")[0],
            "password": "secret123",
        },
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['accessToken']}"}


def test_emotion_current_requires_authentication(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "emotion.sqlite3")) as client:
        response = client.get("/emotion/current")

    assert response.status_code == 401


def test_emotion_checkins_roundtrip_current_and_user_isolation(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "emotion.sqlite3")) as client:
        alice_headers = _headers(client, "alice-emotion@example.com")
        bob_headers = _headers(client, "bob-emotion@example.com")

        default_current = client.get("/emotion/current", headers=alice_headers)
        assert default_current.status_code == 200
        assert default_current.json()["state"] == "stable"

        checkin = {
            "id": "emotion-1",
            "at": "2026-08-09T09:00:00",
            "state": "tired",
            "note": "Need a recovery buffer.",
        }
        created = client.post("/emotion/checkins", json=checkin, headers=alice_headers)
        assert created.status_code == 200
        assert created.json() == checkin

        listed = client.get(
            "/emotion/checkins",
            params={"day": "2026-08-09"},
            headers=alice_headers,
        )
        assert listed.status_code == 200
        assert listed.json() == [checkin]

        current = client.get("/emotion/current", headers=alice_headers)
        assert current.status_code == 200
        assert current.json()["id"] == "emotion-1"
        assert current.json()["state"] == "tired"

        bob_listed = client.get(
            "/emotion/checkins",
            params={"day": "2026-08-09"},
            headers=bob_headers,
        )
        assert bob_listed.status_code == 200
        assert bob_listed.json() == []


def test_emotion_same_day_keeps_latest_and_care_alert_is_rule_based(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "emotion-care.sqlite3")) as client:
        headers = _headers(client, "care@example.com")

        yesterday = {
            "id": "emotion-yesterday",
            "at": "2026-08-08T21:00:00",
            "state": "tired",
            "note": None,
        }
        morning = {
            "id": "emotion-morning",
            "at": "2026-08-09T09:00:00",
            "state": "stable",
            "note": "Recovered.",
        }
        evening = {
            "id": "emotion-evening",
            "at": "2026-08-09T19:00:00",
            "state": "irritable",
            "note": "Too many interruptions.",
        }
        assert client.post("/emotion/checkins", json=yesterday, headers=headers).status_code == 200
        assert client.post("/emotion/checkins", json=morning, headers=headers).status_code == 200
        assert client.post("/emotion/checkins", json=evening, headers=headers).status_code == 200

        listed = client.get(
            "/emotion/checkins",
            params={"day": "2026-08-09"},
            headers=headers,
        )
        assert listed.status_code == 200
        assert listed.json() == [evening]

        alert = client.get(
            "/emotion/care-alert",
            params={"day": "2026-08-09"},
            headers=headers,
        )
        assert alert.status_code == 200
        assert alert.json()["active"] is True
        assert alert.json()["severity"] == "gentle"


def test_energy_samples_drive_current_status_and_profile(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "energy.sqlite3")) as client:
        headers = _headers(client, "energy@example.com")

        default_current = client.get("/energy/current", headers=headers)
        assert default_current.status_code == 200
        assert default_current.json()["level"] == "medium"
        assert default_current.json()["batteryPercent"] == 85

        sample = {
            "id": "energy-1",
            "at": "2026-08-09T10:00:00",
            "level": "high",
            "status": "flow",
            "description": "Manual sample during deep work.",
            "batteryPercent": 92,
            "emotion": "stable",
            "flowState": "focused",
            "source": "manual",
        }
        created = client.post("/energy/samples", json=sample, headers=headers)
        assert created.status_code == 200
        assert created.json() == sample

        current = client.get("/energy/current", headers=headers)
        assert current.status_code == 200
        assert current.json()["level"] == "high"
        assert current.json()["batteryPercent"] == 92
        assert current.json()["flowState"] == "focused"

        profile = client.get("/energy/profile", headers=headers)
        assert profile.status_code == 200
        assert profile.json()["sampleCount"] == 1
        assert profile.json()["latestLevel"] == "high"
        assert profile.json()["averageBatteryPercent"] == 92


def test_emotion_and_energy_reject_invalid_fields(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "emotion-validation.sqlite3")) as client:
        headers = _headers(client, "validation@example.com")

        invalid_emotion = client.post(
            "/emotion/checkins",
            json={
                "id": "bad-emotion",
                "at": "2026-08-09T09:00:00",
                "state": "angry",
                "note": None,
            },
            headers=headers,
        )
        assert invalid_emotion.status_code == 422

        invalid_energy = client.post(
            "/energy/samples",
            json={
                "id": "bad-energy",
                "at": "2026-08-09T09:00:00",
                "level": "turbo",
                "status": "flow",
                "description": "",
                "batteryPercent": 120,
                "emotion": "stable",
                "flowState": "normal",
                "source": "wearable",
            },
            headers=headers,
        )
        assert invalid_energy.status_code == 422
