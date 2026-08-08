from starlette.testclient import TestClient

from backend.main import create_app


def test_health_endpoint_returns_ok_payload():
    client = TestClient(create_app())

    response = client.get("/health")
    payload = response.json()

    assert response.status_code == 200
    assert payload["ok"] is True
    assert payload["database"] == "sqlite"
    assert isinstance(payload["version"], str)
    assert payload["version"]
