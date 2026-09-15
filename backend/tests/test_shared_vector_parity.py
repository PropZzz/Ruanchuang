"""Tests for the cross-runtime shared-vector parity adapter.

These tests describe the adapter contract before its implementation exists.  In
particular, parser failures must be observable, canonical differences must
retain A's review classification, and a failed Dart process must never be
treated as a successful comparison.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from scripts.scheduling_parity import (
    DartRunResult,
    compare_fixture,
    parse_dart_output,
    run_dart_runner,
    run_python_fixture,
    _report_requires_failure,
    _transaction_actual,
)


def _payload(*, fixtures: list[dict] | None = None) -> str:
    value = {"fixtures": fixtures or [], "matched": 0, "mismatched": 0, "invalid": 0}
    return (
        "SHARED_VECTOR_RESULT_BEGIN\n"
        + json.dumps(value)
        + "\nSHARED_VECTOR_RESULT_END"
    )


def _fixture(*, classification: str = "contract_error") -> dict:
    return {
        "schemaVersion": "scheduling/v1",
        "id": "parity-test-001",
        "kind": "plan",
        "tags": ["work_window"],
        "request": {"day": "2026-09-16"},
        "assertions": {
            "taskOrder": ["task-1"],
            "timeBlocks": {
                "task-1": {"hour": 9, "minute": 0, "durationMinutes": 30}
            },
            "issues": [],
            "explanationCodes": [],
        },
        "review": {
            "classification": classification,
            "reason": "A review reason",
        },
    }


def _actual(*, minute: int = 0) -> dict:
    return {
        "entries": [
            {
                "id": "task-1",
                "day": "2026-09-16",
                "time": {"hour": 9, "minute": minute},
                "durationMinutes": 30,
                "source": "planned",
                "explanationCodes": [],
            }
        ],
        "issues": [],
    }


def test_parse_dart_output_requires_exactly_one_marker_pair() -> None:
    with pytest.raises(ValueError, match="marker"):
        parse_dart_output("flutter output without result markers", returncode=0)

    with pytest.raises(ValueError, match="exactly one"):
        parse_dart_output(_payload() + "\n" + _payload(), returncode=0)


def test_parse_dart_output_rejects_nonzero_exit_even_with_payload() -> None:
    with pytest.raises(ValueError, match="exit code"):
        parse_dart_output(_payload(), returncode=1, stderr="test failure")


def test_compare_fixture_reports_canonical_field_and_review_classification() -> None:
    fixture = _fixture(classification="allowed_difference")
    differences = compare_fixture(
        fixture,
        python_actual=_actual(minute=0),
        dart_actual=_actual(minute=5),
    )

    assert differences
    difference = differences[0]
    assert difference["runtime"] == "dart_vs_python"
    assert difference["field"].endswith("entries[0].time.minute")
    assert difference["expected"] == 0
    assert difference["actual"] == 5
    assert difference["classification"] == "allowed_difference"
    assert difference["reason"] == "A review reason"


def test_compare_fixture_preserves_pending_review_classification() -> None:
    fixture = _fixture(classification="pending_a_review")
    differences = compare_fixture(
        fixture,
        python_actual=_actual(minute=0),
        dart_actual=_actual(minute=5),
    )

    assert differences[0]["classification"] == "pending_a_review"


def test_run_dart_runner_reports_missing_output_and_exit_code(tmp_path: Path) -> None:
    missing = run_dart_runner(tmp_path, runner=lambda **_: DartRunResult("", "", 0))
    assert missing.invalid is True
    assert "marker" in missing.error

    failed = run_dart_runner(
        tmp_path,
        runner=lambda **_: DartRunResult(_payload(), "compile error", 1),
    )
    assert failed.invalid is True
    assert "exit code" in failed.error
    assert failed.stderr == "compile error"


def test_python_transaction_rejects_duplicate_entry_ids() -> None:
    fixture = {
        "_fixtureName": "duplicate.json",
        "id": "duplicate-001",
        "kind": "transaction",
        "request": {
            "operation": "apply",
            "before": [
                {"id": "same", "height": 80, "time": {"hour": 9, "minute": 0}},
                {"id": "same", "height": 80, "time": {"hour": 10, "minute": 0}},
            ],
            "after": [],
        },
    }

    with pytest.raises(ValueError, match="duplicate id"):
        _transaction_actual(fixture["request"])

    result = run_python_fixture(fixture)

    assert result.invalid is True
    assert "duplicate id" in result.error


def test_report_exit_gate_rejects_pending_but_allows_explicit_allowed_difference() -> None:
    pending = {
        "dart": {"invalid": False},
        "summary": {"invalid": 0},
        "results": [{"differences": [{"classification": "pending_a_review"}]}],
    }
    allowed = {
        "dart": {"invalid": False},
        "summary": {"invalid": 0},
        "results": [{"differences": [{"classification": "allowed_difference"}]}],
    }

    assert _report_requires_failure(pending) is True
    assert _report_requires_failure(allowed) is False
