from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[2]


def _load_json(relative_path: str) -> dict:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def _validator() -> Draft202012Validator:
    schema = _load_json("contracts/scheduling/v1/scheduling.schema.json")
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


@pytest.mark.parametrize(
    "fixture_name",
    ["basic.json", "dependency-blocked.json"],
)
def test_shared_fixture_matches_schema(fixture_name: str) -> None:
    fixture = _load_json(f"contracts/scheduling/v1/fixtures/{fixture_name}")
    validator = _validator()
    validator.validate(fixture["request"])
    validator.validate(fixture["response"])


def test_schema_rejects_unknown_request_field() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["request"])
    invalid["unknownField"] = True
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_schema_rejects_unknown_task_field() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["request"])
    invalid["tasks"][0]["unknownField"] = True
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_schema_rejects_invalid_priority() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["request"])
    invalid["tasks"][0]["priority"] = 6
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_schema_rejects_invalid_clock_minute() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["request"])
    invalid["windows"][0]["start"]["minute"] = 60
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_schema_rejects_invalid_date() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["request"])
    invalid["day"] = "2026-02-30"
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_schema_rejects_invalid_date_time() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["request"])
    invalid["tasks"][0]["due"] = "2026-09-14T25:00:00+08:00"
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_schema_rejects_unknown_entry_field() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["response"])
    invalid["entries"][0]["unknownField"] = True
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_schema_rejects_unknown_issue_field() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/dependency-blocked.json")
    invalid = copy.deepcopy(fixture["response"])
    invalid["issues"][0]["unknownField"] = True
    errors = list(_validator().iter_errors(invalid))
    assert errors


def test_canonical_entries_do_not_allow_legacy_height() -> None:
    fixture = _load_json("contracts/scheduling/v1/fixtures/basic.json")
    invalid = copy.deepcopy(fixture["response"])
    invalid["entries"][0]["height"] = 80
    errors = list(_validator().iter_errors(invalid))
    assert errors
