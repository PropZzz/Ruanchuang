from __future__ import annotations

from scripts.scheduling_parity import (
    ParityRunnerError,
    compare_results,
    parse_runner_output,
)


def _marked_payload() -> str:
    return """
    noisy test output
    SCHEDULING_PARITY_RESULT_BEGIN
    {"fixtures": [{"name": "basic.json"}, {"name": "dependency-blocked.json"}]}
    SCHEDULING_PARITY_RESULT_END
    """


def test_parse_runner_output_requires_one_marker_pair() -> None:
    parsed = parse_runner_output(_marked_payload())
    assert len(parsed["fixtures"]) == 2
    with __import__("pytest").raises(ParityRunnerError):
        parse_runner_output("SCHEDULING_PARITY_RESULT_BEGIN\n{}\n")


def test_compare_results_reports_field_level_difference() -> None:
    expected = {
        "schemaVersion": "1",
        "entries": [{"id": "a", "durationMinutes": 30}],
        "issues": [],
    }
    python_result = {
        "schemaVersion": "1",
        "entries": [{"id": "a", "durationMinutes": 30}],
        "issues": [],
    }
    dart_result = {
        "schemaVersion": "1",
        "entries": [{"id": "a", "durationMinutes": 45}],
        "issues": [],
    }
    diff = compare_results(expected, python_result, dart_result)
    assert diff["status"] == "mismatched"
    assert any(
        item["field"] == "entries[0].durationMinutes"
        for item in diff["differences"]
    )
