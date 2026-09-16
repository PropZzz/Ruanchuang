from __future__ import annotations

import time

from scripts.scheduling_benchmark import (
    build_workload,
    evaluate_parity_gate,
    measure_call,
    percentile,
    summarize_samples,
)


def test_percentile_uses_linear_interpolation() -> None:
    assert percentile([10, 20, 30, 40], 0.95) == 38.5


def test_build_workload_is_seeded_and_has_requested_task_count() -> None:
    first = build_workload(7, seed=123)
    second = build_workload(7, seed=123)

    assert first == second
    assert len(first["tasks"]) == 7


def test_evaluate_parity_gate_blocks_mismatches_and_pending_review() -> None:
    summary = {"total": 2, "matched": 1, "mismatched": 1, "invalid": 0}
    dart = {"invalid": False}
    classification_counts = {"pending_a_review": 1}

    result = evaluate_parity_gate(summary, dart, classification_counts)

    assert result["status"] == "blocked"
    assert "mismatched" in result["reasons"]
    assert "pending_a_review" in result["reasons"]


def test_summarize_samples_counts_outcomes_and_calculates_p50() -> None:
    samples = [
        {"status": "success", "elapsedMs": 10},
        {"status": "timeout", "elapsedMs": 20},
        {"status": "failure", "elapsedMs": 30},
        {"status": "degraded", "elapsedMs": 40},
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
