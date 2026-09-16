from __future__ import annotations

import time
import json

import pytest

from scripts.scheduling_benchmark import (
    build_workload,
    evaluate_parity_gate,
    measure_call,
    percentile,
    summarize_samples,
    run_benchmark,
    write_benchmark_report,
)


def test_percentile_uses_linear_interpolation() -> None:
    assert percentile([10, 20, 30, 40], 0.95) == 38.5


def test_build_workload_is_seeded_and_has_requested_task_count() -> None:
    first = build_workload(7, seed=123)
    second = build_workload(7, seed=123)

    assert first == second
    assert len(first["tasks"]) == 7


@pytest.mark.parametrize("bad_seed", [None, "123", 1.5, True])
def test_build_workload_rejects_non_integer_seed(bad_seed: object) -> None:
    with pytest.raises(ValueError):
        build_workload(1, seed=bad_seed)  # type: ignore[arg-type]


def test_evaluate_parity_gate_blocks_mismatches_and_pending_review() -> None:
    report = {
        "summary": {"total": 2, "matched": 1, "mismatched": 1, "invalid": 0},
        "dart": {"invalid": False},
        "classificationCounts": {"pending_a_review": 1},
    }

    result = evaluate_parity_gate(report)

    assert result["status"] == "blocked"
    assert "mismatched" in result["reasons"]
    assert "pending_a_review" in result["reasons"]


def test_evaluate_parity_gate_requires_conserved_non_negative_counts() -> None:
    report = {
        "summary": {"total": 2, "matched": 1, "mismatched": 0, "invalid": 0},
        "dart": {"invalid": False, "returncode": 0},
        "classificationCounts": {"pending_a_review": 0},
    }
    assert evaluate_parity_gate(report)["status"] == "blocked"


@pytest.mark.parametrize(
    "summary",
    [
        {"total": 2, "matched": 1, "mismatched": 1, "invalid": -1},
        {"total": 2, "matched": 2, "mismatched": 1, "invalid": 0},
        {"total": 2, "matched": True, "mismatched": 1, "invalid": 0},
        {"total": 2.0, "matched": 1, "mismatched": 1, "invalid": 0},
    ],
)
def test_evaluate_parity_gate_rejects_invalid_summary_shape(summary: dict[str, object]) -> None:
    report = {
        "summary": summary,
        "dart": {"invalid": False, "returncode": 0},
        "classificationCounts": {"pending_a_review": 0},
    }
    assert evaluate_parity_gate(report)["status"] == "blocked"


def test_summarize_samples_counts_outcomes_and_calculates_p50() -> None:
    samples = [
        {"status": "success", "durationMs": 10},
        {"status": "timeout", "durationMs": 20},
        {"status": "failure", "durationMs": 30},
        {"status": "degraded", "durationMs": 40},
    ]

    result = summarize_samples(samples)

    assert result["sampleCount"] == 4
    assert result["timeoutCount"] == 1
    assert result["failureCount"] == 1
    assert result["degradedCount"] == 1
    assert result["p50Ms"] == 25.0


def test_measure_call_reports_timeout() -> None:
    result = measure_call(lambda: time.sleep(0.05), timeoutMs=1)

    assert result["status"] == "timeout"


def test_measure_call_reports_exception_type_for_failure() -> None:
    def fail() -> None:
        raise ValueError("bad workload")

    result = measure_call(fail, timeoutMs=100)

    assert result["status"] == "failure"
    assert result["errorType"] == "ValueError"


def test_measure_call_requires_boolean_degradation_flags() -> None:
    assert measure_call(lambda: {"fallback": "false"}, timeoutMs=100)["status"] == "success"


def test_percentile_and_summary_reject_non_finite_or_boolean_durations() -> None:
    with pytest.raises(ValueError):
        percentile([1.0, float("nan")], 0.5)
    summary = summarize_samples([{"status": "success", "durationMs": True}])
    assert summary["successfulSampleCount"] == 1
    assert summary["p50Ms"] is None


def test_run_benchmark_records_plan_and_rescue_matrix_after_parity_gate() -> None:
    parity = {
        "summary": {"total": 1, "matched": 1, "mismatched": 0, "invalid": 0},
        "dart": {"invalid": False, "returncode": 0},
        "classificationCounts": {"pending_a_review": 0},
    }

    def plan_runner(request: dict[str, object]) -> dict[str, object]:
        return {"entries": [], "issues": []}

    def rescue_runner(request: dict[str, object]) -> dict[str, object]:
        return {
            "options": [
                {
                    "strategy": strategy,
                    "plannedEntries": [],
                    "issueCount": 0,
                    "hardIssueCount": 0,
                    "movedEntryCount": 0,
                    "recoveryMinutes": 0,
                    "recommended": strategy == "protectDeadline",
                }
                for strategy in ("protectDeadline", "protectRecovery", "minimizeChanges")
            ]
        }

    report = run_benchmark(
        task_counts=(3,),
        warmups=0,
        samples=2,
        seed=7,
        timeoutMs=100,
        parity_report=parity,
        plan_runner=plan_runner,
        rescue_runner=rescue_runner,
    )

    assert report["status"] == "completed"
    assert [row["strategy"] for row in report["strategies"]] == [
        "protectDeadline",
        "protectRecovery",
        "minimizeChanges",
    ]
    assert report["runs"]
    assert report["errors"] == []


def test_write_benchmark_report_writes_json_and_markdown_without_overwriting(tmp_path) -> None:
    report = {
        "schemaVersion": "scheduling-benchmark/v1",
        "status": "blocked",
        "gate": {"status": "blocked", "reasons": ["mismatched"]},
        "runs": [],
        "strategies": [],
        "errors": ["parity gate blocked"],
    }

    first = write_benchmark_report(report, tmp_path)
    second = write_benchmark_report(report, tmp_path)

    assert first.suffix == ".json"
    assert first.exists()
    assert second.exists()
    assert first != second
    assert json.loads(first.read_text(encoding="utf-8"))["status"] == "blocked"
    assert first.with_suffix(".md").exists()
    assert second.with_suffix(".md").exists()
