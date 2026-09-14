from __future__ import annotations

import copy
import json
from datetime import datetime, timezone
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker
from pydantic import ValidationError
from starlette.testclient import TestClient

from backend.auth import reset_token_store
from backend.main import create_app
from backend.scheduling_contract import (
    SchedulingRequest,
    SchedulingResponse,
    to_contract_response,
)


ROOT = Path(__file__).resolve().parents[2]


def _fixture_request() -> dict[str, object]:
    return json.loads(
        (ROOT / "contracts/scheduling/v1/fixtures/basic.json").read_text(encoding="utf-8")
    )["request"]


def _schema_validator() -> Draft202012Validator:
    schema = json.loads(
        (ROOT / "contracts/scheduling/v1/scheduling.schema.json").read_text(encoding="utf-8")
    )
    return Draft202012Validator(schema, format_checker=FormatChecker())


def test_request_model_converts_legacy_fixed_height_and_datetime_to_canonical_values() -> None:
    payload = _fixture_request()
    payload.pop("schemaVersion")
    payload["tasks"][0]["due"] = "2026-09-14T13:30:00+08:00"
    payload["fixed"][0].pop("durationMinutes")
    payload["fixed"][0]["height"] = 80

    request = SchedulingRequest.model_validate(payload)

    assert request.schema_version == "1"
    assert request.fixed[0].duration_minutes == 60
    assert "height" not in request.fixed[0].model_dump(by_alias=True)
    assert request.tasks[0].due == datetime(2026, 9, 14, 5, 30, tzinfo=timezone.utc)


@pytest.mark.parametrize(
    "mutate",
    [
        lambda payload: payload["energy"].__class__ and payload.update(energy="invalid"),
        lambda payload: payload["tasks"][0].update(priority=6),
        lambda payload: payload["tasks"][0].update(durationMinutes=0),
        lambda payload: payload["windows"][0]["start"].update(minute=60),
        lambda payload: payload["windows"][0].update(end={"hour": 9, "minute": 0}),
        lambda payload: payload["tasks"][0].update(unknownField=True),
    ],
)
def test_request_model_rejects_invalid_contract_values(mutate) -> None:
    payload = copy.deepcopy(_fixture_request())
    mutate(payload)
    with pytest.raises(ValidationError):
        SchedulingRequest.model_validate(payload)


def test_response_adapter_emits_schema_shape_without_height_or_optional_blocked_by() -> None:
    request = SchedulingRequest.model_validate(_fixture_request())
    result = to_contract_response(
        {
            "entries": [
                {
                    "id": "task-offset",
                    "day": "2026-09-14",
                    "title": "Prepare release notes",
                    "tag": "Writing",
                    "load": "medium",
                    "height": 40,
                    "time": {"hour": 10, "minute": 0},
                }
            ],
            "issues": [
                {"code": "no_slot", "message": "No time slot left", "taskId": "task-beta"}
            ],
        },
        request,
    )

    body = result.model_dump(mode="json", by_alias=True, exclude_none=True)
    assert body["schemaVersion"] == "1"
    assert body["entries"][0]["durationMinutes"] == 30
    assert "height" not in body["entries"][0]
    assert body["entries"][0]["source"] == "planned"
    assert body["issues"][0]["explanationCodes"] == []
    assert "blockedBy" not in body["issues"][0]
    errors = list(_schema_validator().iter_errors(body))
    assert errors == []
    SchedulingResponse.model_validate(body)


def test_replan_api_accepts_missing_schema_version_and_returns_canonical_response(tmp_path) -> None:
    reset_token_store()
    with TestClient(create_app(tmp_path / "contract.sqlite3")) as client:
        registered = client.post(
            "/auth/register",
            json={
                "contactAddress": "contract@example.com",
                "displayName": "Contract",
                "password": "secret123",
            },
        )
        headers = {"Authorization": f"Bearer {registered.json()['accessToken']}"}
        payload = _fixture_request()
        payload.pop("schemaVersion")
        payload["fixed"][0].pop("durationMinutes")
        payload["fixed"][0]["height"] = 80

        response = client.post("/schedule/replan", json=payload, headers=headers)

    assert response.status_code == 200
    body = response.json()
    assert body["schemaVersion"] == "1"
    assert all("height" not in entry for entry in body["entries"])
    assert _schema_validator().is_valid(body)


@pytest.mark.parametrize(
    "field,value",
    [("energy", "invalid"), ("day", "2026-02-30"), ("unknownField", True)],
)
def test_replan_api_rejects_invalid_request_with_422(tmp_path, field, value) -> None:
    reset_token_store()
    with TestClient(create_app(tmp_path / "invalid-contract.sqlite3")) as client:
        registered = client.post(
            "/auth/register",
            json={
                "contactAddress": "invalid-contract@example.com",
                "displayName": "Contract",
                "password": "secret123",
            },
        )
        headers = {"Authorization": f"Bearer {registered.json()['accessToken']}"}
        payload = _fixture_request()
        payload[field] = value
        response = client.post("/schedule/replan", json=payload, headers=headers)

    assert response.status_code == 422
