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


def _member(member_id: str = "member-1", **overrides):
    return {
        "memberId": member_id,
        "displayName": "Li Ming",
        "role": "PM",
        "energy": "high",
        "permission": "details",
        "busy": [
            {
                "id": "busy-1",
                "day": "2026-08-09",
                "title": "Product sync",
                "tag": "Meeting",
                "load": "medium",
                "height": 80.0,
                "color": 4278255360,
                "time": {"hour": 9, "minute": 0},
                "reminderMinutesBefore": 10,
                "repeat": "none",
                "repeatUntil": None,
            }
        ],
        **overrides,
    }


def test_team_members_require_authentication(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "team.sqlite3")) as client:
        response = client.get("/team/members")

    assert response.status_code == 401


def test_team_member_crud_permission_and_calendar_roundtrip(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "team.sqlite3")) as client:
        headers = _headers(client, "team@example.com")

        created = client.post("/team/members", json=_member(), headers=headers)
        assert created.status_code == 200
        assert created.json()["memberId"] == "member-1"

        listed = client.get("/team/members", headers=headers)
        assert listed.status_code == 200
        assert [member["memberId"] for member in listed.json()] == ["member-1"]

        updated = client.put(
            "/team/members/member-1",
            json={**created.json(), "displayName": "Li Ming Updated", "energy": "medium"},
            headers=headers,
        )
        assert updated.status_code == 200
        assert updated.json()["displayName"] == "Li Ming Updated"
        assert updated.json()["energy"] == "medium"

        permission = client.put(
            "/team/members/member-1/permission",
            json={"permission": "freeBusy"},
            headers=headers,
        )
        assert permission.status_code == 200
        assert permission.json()["permission"] == "freeBusy"

        calendars = client.get(
            "/team/calendars",
            params={"day": "2026-08-09"},
            headers=headers,
        )
        assert calendars.status_code == 200
        assert calendars.json()[0]["memberId"] == "member-1"
        assert calendars.json()[0]["busy"][0]["id"] == "busy-1"

        deleted = client.delete("/team/members/member-1", headers=headers)
        assert deleted.status_code == 204
        assert client.get("/team/members", headers=headers).json() == []


def test_team_member_ids_are_isolated_and_cross_user_conflicts_are_rejected(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "team.sqlite3")) as client:
        alice_headers = _headers(client, "alice-team@example.com")
        bob_headers = _headers(client, "bob-team@example.com")

        assert client.post("/team/members", json=_member("shared-member"), headers=alice_headers).status_code == 200

        bob_conflict = client.post("/team/members", json=_member("shared-member"), headers=bob_headers)
        assert bob_conflict.status_code == 409

        bob_list = client.get("/team/members", headers=bob_headers)
        assert bob_list.status_code == 200
        assert bob_list.json() == []


def test_team_permission_validation_and_missing_member(tmp_path):
    reset_token_store()
    with TestClient(create_app(tmp_path / "team.sqlite3")) as client:
        headers = _headers(client, "team-errors@example.com")

        missing = client.put(
            "/team/members/missing/permission",
            json={"permission": "freeBusy"},
            headers=headers,
        )
        assert missing.status_code == 404

        invalid = client.post(
            "/team/members",
            json=_member("bad-permission", permission="owner"),
            headers=headers,
        )
        assert invalid.status_code == 422
