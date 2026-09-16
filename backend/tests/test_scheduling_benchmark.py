from __future__ import annotations

import time
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from scripts.scheduling_benchmark import (
    build_workload,
    evaluate_parity_gate,
    measure_call,
    percentile,
    summarize_samples,
    run_benchmark,
    write_benchmark_report,
    main,
)


def _picklable_echo() -> dict[str, str]:
    return {"ok": "yes"}


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


def test_measure_call_uses_process_for_picklable_runner() -> None:
    result = measure_call(_picklable_echo, timeoutMs=1000)
    assert result["isolation"] == "process"
    assert result["result"] == {"ok": "yes"}
    assert result["durationMs"] >= 0


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


def _passed_parity() -> dict[str, object]:
    return {
        "summary": {"total": 1, "matched": 1, "mismatched": 0, "invalid": 0},
        "dart": {"invalid": False, "returncode": 0},
        "classificationCounts": {"pending_a_review": 0},
    }


@pytest.mark.parametrize("bad_seed", [True, "7", 1.5])
def test_run_benchmark_rejects_non_integer_seed_without_calling_runners(bad_seed: object) -> None:
    calls = 0

    def runner(_: dict[str, object]) -> dict[str, object]:
        nonlocal calls
        calls += 1
        return {"entries": [], "issues": []}

    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=1, seed=bad_seed, timeoutMs=100,  # type: ignore[arg-type]
        parity_report=_passed_parity(), plan_runner=runner, rescue_runner=runner,
    )

    assert report["status"] == "failed"
    assert calls == 0
    assert any(error.get("field") == "seed" for error in report["errors"])


def test_run_benchmark_marks_missing_rescue_metric_as_strategy_failure() -> None:
    def rescue_runner(_: dict[str, object]) -> dict[str, object]:
        return {"options": [{"strategy": strategy, "plannedEntries": [], **({} if strategy == "protectRecovery" else {"issueCount": 0, "hardIssueCount": 0, "movedEntryCount": 0, "recoveryMinutes": 0}), "recommended": False} for strategy in ("protectDeadline", "protectRecovery", "minimizeChanges")]}

    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=1, seed=7, timeoutMs=100,
        parity_report=_passed_parity(), plan_runner=lambda _: {"entries": [], "issues": []},
        rescue_runner=rescue_runner,
    )

    row = next(item for item in report["strategies"] if item["strategy"] == "protectRecovery")
    assert row["failureCount"] == 1
    assert any(error.get("strategy") == "protectRecovery" and error.get("type") for error in report["errors"])


def test_run_benchmark_marks_missing_and_unknown_rescue_strategies_as_failures() -> None:
    def rescue_runner(_: dict[str, object]) -> dict[str, object]:
        return {"options": [{"strategy": "protectDeadline", "plannedEntries": [], "issueCount": 0, "hardIssueCount": 0, "movedEntryCount": 0, "recoveryMinutes": 0, "recommended": True}, {"strategy": "unknown", "plannedEntries": [], "issueCount": 0, "hardIssueCount": 0, "movedEntryCount": 0, "recoveryMinutes": 0, "recommended": False}]}

    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=1, seed=7, timeoutMs=100,
        parity_report=_passed_parity(), plan_runner=lambda _: {"entries": [], "issues": []},
        rescue_runner=rescue_runner,
    )

    assert all(item["failureCount"] == 1 for item in report["strategies"] if item["strategy"] != "protectDeadline")
    assert any(error.get("strategy") == "unknown" for error in report["errors"])


def test_run_benchmark_counts_timeout_failure_and_degraded_samples() -> None:
    responses = iter([TimeoutError("sleep"), RuntimeError("boom"), {"entries": [], "issues": [], "degraded": True}])

    def plan_runner(_: dict[str, object]) -> dict[str, object]:
        response = next(responses)
        if isinstance(response, Exception):
            if isinstance(response, TimeoutError):
                time.sleep(0.05)
            raise response
        return response

    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=3, seed=7, timeoutMs=1,
        parity_report=_passed_parity(), plan_runner=plan_runner,
        rescue_runner=lambda _: {"options": []},
    )
    plan = next(item for item in report["runs"] if item["operation"] == "plan")
    assert plan["timeoutCount"] == 1
    assert plan["failureCount"] == 1
    assert plan["degradedCount"] == 1


def test_blocked_gate_does_not_call_runners() -> None:
    calls = []

    def runner(_: dict[str, object]) -> dict[str, object]:
        calls.append(True)
        return {"entries": [], "issues": []}

    report = run_benchmark(task_counts=(1,), warmups=0, samples=1, seed=7, timeoutMs=100, parity_report={"summary": {"total": 1, "matched": 0, "mismatched": 1, "invalid": 0}}, plan_runner=runner, rescue_runner=runner)
    assert report["status"] == "blocked"
    assert calls == []


def test_degraded_malformed_plan_and_rescue_are_failures_not_degradation() -> None:
    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=1, seed=7, timeoutMs=100,
        parity_report=_passed_parity(), plan_runner=lambda _: {"degraded": True},
        rescue_runner=lambda _: {"degraded": True, "options": None},
    )
    plan = next(item for item in report["runs"] if item["operation"] == "plan")
    rescue = next(item for item in report["runs"] if item["operation"] == "rescue")
    assert plan["failureCount"] == 1 and plan["degradedCount"] == 0
    assert rescue["failureCount"] == 1 and rescue["degradedCount"] == 0


def test_markdown_strategy_table_includes_timeout_and_degraded_columns(tmp_path) -> None:
    path = write_benchmark_report({"status": "completed", "gate": {"status": "passed", "reasons": []}, "runs": [], "strategies": [{"taskCount": 1, "strategy": "protectDeadline", "sampleCount": 1, "successfulSampleCount": 1, "timeoutCount": 0, "failureCount": 0, "degradedCount": 0, "avgEntryCount": 0, "avgIssueCount": 0, "avgHardIssueCount": 0, "avgMovedEntryCount": 0, "avgRecoveryMinutes": 0, "recommendedCount": 1}], "errors": []}, tmp_path)
    markdown = path.with_suffix(".md").read_text(encoding="utf-8")
    header = next(line for line in markdown.splitlines() if line.startswith("| taskCount | strategy"))
    assert "timeout" in header and "degraded" in header


def test_refresh_parity_failure_blocks_even_when_stale_report_is_valid(tmp_path, monkeypatch) -> None:
    stale = tmp_path / "stale.json"
    stale.write_text(json.dumps(_passed_parity()), encoding="utf-8")

    def failed_refresh(*args: object, **kwargs: object) -> SimpleNamespace:
        return SimpleNamespace(returncode=1)

    monkeypatch.setattr("scripts.scheduling_benchmark.subprocess.run", failed_refresh)
    assert main(["--refresh-parity", "--parity-report", str(stale), "--output-dir", str(tmp_path)]) == 2
    reports = sorted(tmp_path.glob("scheduling-benchmark-*.json"))
    payload = json.loads(reports[-1].read_text(encoding="utf-8"))
    assert payload["status"] == "blocked"
    assert any(error.get("type") == "parity_refresh" for error in payload["errors"])


def test_benchmark_records_inner_duration_and_sample_peak_memory() -> None:
    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=1, seed=7, timeoutMs=100,
        parity_report=_passed_parity(), plan_runner=lambda _: {"entries": [], "issues": []},
        rescue_runner=lambda _: {"options": [{"strategy": s, "plannedEntries": [], "issueCount": 0, "hardIssueCount": 0, "movedEntryCount": 0, "recoveryMinutes": 0, "recommended": False} for s in ("protectDeadline", "protectRecovery", "minimizeChanges")]},
    )
    run = report["runs"][0]
    sample = run["samplesData"][0]
    assert "innerDurationMs" in sample and "peakMemoryBytes" in sample
    assert run["peakRssBytes"] == sample["peakMemoryBytes"]
    assert report["memorySource"] == "tracemalloc"
    assert "parentPeakMemoryBytes" in report


def test_thread_timeout_is_marked_uncancellable() -> None:
    sample = measure_call(lambda: time.sleep(0.05), timeoutMs=1)
    assert sample["status"] == "timeout"
    assert sample["isolation"] == "thread"
    assert sample["timeoutUncancellable"] is True


def test_malformed_non_json_plan_result_is_failure() -> None:
    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=1, seed=7, timeoutMs=100,
        parity_report=_passed_parity(), plan_runner=lambda _: {"entries": [{"bad": {1, 2}}], "issues": []},
        rescue_runner=lambda _: {"options": []},
    )
    plan = next(item for item in report["runs"] if item["operation"] == "plan")
    assert plan["failureCount"] == 1 and plan["degradedCount"] == 0


def test_refresh_parity_uses_fresh_temporary_reports_dir(tmp_path, monkeypatch) -> None:
    stale = tmp_path / "shared-vector-diff.json"
    stale.write_text(json.dumps(_passed_parity()), encoding="utf-8")

    def fake_refresh(command: list[str], cwd: object, check: bool) -> SimpleNamespace:
        reports_dir = Path(command[-1])
        reports_dir.mkdir()
        (reports_dir / "shared-vector-diff.json").write_text(json.dumps({"summary": {"total": 1, "matched": 0, "mismatched": 1, "invalid": 0}, "dart": {"invalid": False, "returncode": 0}, "classificationCounts": {"pending_a_review": 0}}), encoding="utf-8")
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr("scripts.scheduling_benchmark.subprocess.run", fake_refresh)
    assert main(["--refresh-parity", "--parity-report", str(stale), "--output-dir", str(tmp_path)]) == 2


def test_write_benchmark_report_rejects_nan_without_partial_files(tmp_path) -> None:
    with pytest.raises(ValueError):
        write_benchmark_report({"status": "blocked", "value": float("nan")}, tmp_path)
    assert list(tmp_path.iterdir()) == []


def test_benchmark_exposes_peak_memory_aliases() -> None:
    report = run_benchmark(
        task_counts=(1,), warmups=0, samples=1, seed=7, timeoutMs=100,
        parity_report=_passed_parity(), plan_runner=lambda _: {"entries": [], "issues": []},
        rescue_runner=lambda _: {"options": [{"strategy": s, "plannedEntries": [], "issueCount": 0, "hardIssueCount": 0, "movedEntryCount": 0, "recoveryMinutes": 0, "recommended": False} for s in ("protectDeadline", "protectRecovery", "minimizeChanges")]},
    )
    assert report["peakMemoryBytes"] == report["peakRssBytes"]
    assert all(row["peakMemoryBytes"] == row["peakRssBytes"] for row in report["runs"])


def test_runner_receives_deepcopied_request_each_sample() -> None:
    seen: list[int] = []

    def plan_runner(request: dict[str, object]) -> dict[str, object]:
        tasks = request["tasks"]
        assert isinstance(tasks, list)
        seen.append(len(tasks))
        tasks.append({"id": "mutated"})
        return {"entries": [], "issues": []}

    run_benchmark(task_counts=(1,), warmups=0, samples=2, seed=7, timeoutMs=100, parity_report=_passed_parity(), plan_runner=plan_runner, rescue_runner=lambda _: {"options": []})
    assert seen == [1, 1]
