"""Contract checks for the cross-runtime scheduling vector corpus."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES_DIR = REPO_ROOT / "contracts" / "scheduling" / "v1" / "fixtures"

REQUIRED_FIELDS = {
    "schemaVersion",
    "id",
    "kind",
    "tags",
    "request",
    "assertions",
    "review",
}
SCENARIO_TAGS = {
    "fixed_conflict",
    "work_window",
    "deadline_infeasible",
    "dependency_blocked",
    "low_energy_match",
    "rescue_strategies",
    "no_available_block",
    "overdue",
    "apply_rollback",
    "undo_restore",
    "timeout",
    "boundary_time",
}
ALLOWED_KINDS = {"plan", "rescue", "transaction", "boundary"}
ALLOWED_REVIEW_CLASSES = {
    "implementation_error",
    "contract_error",
    "allowed_difference",
    "pending_a_review",
}


def _fixture_paths() -> list[Path]:
    return sorted(FIXTURES_DIR.glob("*.json"))


def _read_fixture(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"{path.name} is not valid JSON: {exc}")
    assert isinstance(value, dict), f"{path.name} must contain a JSON object"
    return value


def test_shared_fixture_corpus_covers_required_scenarios_and_unique_ids() -> None:
    paths = _fixture_paths()
    assert paths, f"no shared vector fixtures found under {FIXTURES_DIR}"

    fixtures = [_read_fixture(path) for path in paths]
    ids = [fixture.get("id") for fixture in fixtures]
    assert len(ids) == len(set(ids)), "fixture ids must be unique"

    tags = {tag for fixture in fixtures for tag in fixture.get("tags", [])}
    missing = SCENARIO_TAGS - tags
    assert not missing, f"missing required scenario tags: {sorted(missing)}"


@pytest.mark.parametrize("path", _fixture_paths(), ids=lambda path: path.name)
def test_shared_fixture_has_contract_shape(path: Path) -> None:
    fixture = _read_fixture(path)
    missing = REQUIRED_FIELDS - fixture.keys()
    assert not missing, f"{path.name} is missing required fields: {sorted(missing)}"

    assert fixture["schemaVersion"] == "scheduling/v1"
    assert isinstance(fixture["id"], str) and fixture["id"].strip()
    assert fixture["kind"] in ALLOWED_KINDS
    assert isinstance(fixture["tags"], list) and fixture["tags"]
    assert all(isinstance(tag, str) and tag.strip() for tag in fixture["tags"])
    assert isinstance(fixture["request"], dict)
    assert isinstance(fixture["assertions"], dict)

    review = fixture["review"]
    assert isinstance(review, dict)
    assert review.get("classification") in ALLOWED_REVIEW_CLASSES
    assert isinstance(review.get("reason"), str) and review["reason"].strip()


def test_plan_assertions_use_canonical_comparison_fields() -> None:
    for path in _fixture_paths():
        fixture = _read_fixture(path)
        if fixture["kind"] not in {"plan", "rescue"}:
            continue

        assertions = fixture["assertions"]
        assert "taskOrder" in assertions, f"{path.name} must declare taskOrder"
        assert "timeBlocks" in assertions, f"{path.name} must declare timeBlocks"
        assert "issues" in assertions, f"{path.name} must declare issues"
        assert "explanationCodes" in assertions, (
            f"{path.name} must declare explanationCodes"
        )


def test_transaction_and_boundary_assertions_declare_final_state() -> None:
    for path in _fixture_paths():
        fixture = _read_fixture(path)
        if fixture["kind"] not in {"transaction", "boundary"}:
            continue
        assert "finalState" in fixture["assertions"], (
            f"{path.name} must declare assertions.finalState"
        )
        assert isinstance(fixture["assertions"]["finalState"], dict)
