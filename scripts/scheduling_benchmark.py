"""Deterministic scheduling benchmark primitives, matrix runner, and reports.

The parity gate is evaluated before any scheduling work; measurement helpers
use killable processes where possible and mark thread timeouts explicitly.
"""

from __future__ import annotations

import argparse
import copy
from datetime import datetime, timedelta, timezone
from functools import partial
import json
import math
import multiprocessing
from pathlib import Path
import pickle
import random
import subprocess
import sys
import tempfile
import threading
import time
import tracemalloc
from typing import Any, Callable, Mapping, Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

# Imported here so later benchmark layers can use the same production
# services.  The primitive functions below never invoke either service.
from backend.services_rescue import build_options  # noqa: F401
from backend.services_scheduling import plan_schedule  # noqa: F401


def percentile(samples: Sequence[float], quantile: float) -> float:
    """Return a linearly interpolated percentile from a non-empty sequence."""

    if not samples:
        raise ValueError("samples must not be empty")
    try:
        q = float(quantile)
    except (TypeError, ValueError) as exc:
        raise ValueError("quantile must be between 0 and 1") from exc
    if not math.isfinite(q) or not 0.0 <= q <= 1.0:
        raise ValueError("quantile must be between 0 and 1")

    try:
        values = sorted(float(sample) for sample in samples)
    except (TypeError, ValueError) as exc:
        raise ValueError("samples must contain finite numbers") from exc
    if any(not math.isfinite(value) for value in values):
        raise ValueError("samples must contain finite numbers")
    position = (len(values) - 1) * q
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return values[lower]
    fraction = position - lower
    return values[lower] + (values[upper] - values[lower]) * fraction


def build_workload(task_count: int, *, seed: int) -> dict[str, Any]:
    """Build a deterministic, JSON-compatible scheduling/rescue request."""

    if isinstance(task_count, bool) or not isinstance(task_count, int) or task_count < 1:
        raise ValueError("task_count must be at least 1")
    if isinstance(seed, bool) or not isinstance(seed, int):
        raise ValueError("seed must be an integer")

    rng = random.Random(seed)
    day = "2026-09-16"
    day_start = datetime.fromisoformat(f"{day}T00:00:00+08:00")
    tags = ("Focus", "Admin", "DeepWork", "Planning")
    loads = ("low", "medium", "high")
    durations = (30, 45, 60, 90, 120)

    tasks: list[dict[str, Any]] = []
    for index in range(task_count):
        duration = rng.choice(durations)
        due_hour = rng.randint(9, 20)
        due_minute = rng.choice((0, 15, 30, 45))
        due = day_start.replace(hour=due_hour, minute=due_minute)
        tasks.append(
            {
                "id": f"task-{index:04d}",
                "title": f"Benchmark task {index + 1}",
                "durationMinutes": duration,
                "priority": rng.randint(1, 5),
                "load": rng.choice(loads),
                "tag": rng.choice(tags),
                "due": due.isoformat(timespec="minutes"),
                "hardDeadline": rng.random() < 0.25,
                "dependsOn": [],
                "splittable": False,
            }
        )

    fixed_duration = rng.choice((30, 45, 60))
    fixed_hour = rng.choice((9, 10, 14, 15, 16))
    fixed = [
        {
            "id": "fixed-0000",
            "day": day,
            "title": "Benchmark fixed block",
            "tag": "Fixed",
            "load": "medium",
            "durationMinutes": fixed_duration,
            "time": {"hour": fixed_hour, "minute": 0},
            "source": "fixed",
        }
    ]

    urgent_due = day_start.replace(hour=18, minute=0) + timedelta(days=1)
    urgent_task = {
        "id": "urgent-0000",
        "title": "Benchmark urgent task",
        "durationMinutes": 45,
        "priority": 5,
        "due": urgent_due.isoformat(timespec="minutes"),
        "load": "high",
        "tag": "Urgent",
        "hardDeadline": True,
        "dependsOn": [],
        "splittable": False,
    }

    return {
        "day": day,
        "tasks": tasks,
        "windows": [
            {"start": {"hour": 8, "minute": 0}, "end": {"hour": 12, "minute": 0}},
            {"start": {"hour": 13, "minute": 0}, "end": {"hour": 18, "minute": 0}},
        ],
        "fixed": fixed,
        "energy": rng.choice(("low", "medium", "high")),
        "tuning": {
            "defaultDurationMultiplier": 1.0,
            "tagDurationMultiplier": {"Focus": 1.0, "DeepWork": 1.1},
            "highLoadPenaltyWhenLowEnergy": 1.0,
        },
        "urgentTask": urgent_task,
        "currentEntries": [],
    }


def _as_count(value: object) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    return None


def evaluate_parity_gate(report: Mapping[str, Any]) -> dict[str, Any]:
    """Classify a parity report as usable or blocked with diagnostic reasons."""

    reasons: list[str] = []
    summary_raw = report.get("summary") if isinstance(report, Mapping) else None
    summary = dict(summary_raw) if isinstance(summary_raw, Mapping) else {}
    if not isinstance(report, Mapping):
        reasons.append("report")
    if not isinstance(summary_raw, Mapping):
        reasons.append("summary")

    total_key = "total" if "total" in summary else "fixtures"
    total = _as_count(summary.get(total_key)) if total_key in summary else None
    if total is None:
        reasons.append("total" if total_key == "total" else "fixtures")
    elif total <= 0:
        reasons.append("total")

    counts: dict[str, int | None] = {}
    for key in ("matched", "mismatched", "invalid"):
        value = _as_count(summary.get(key)) if key in summary else None
        counts[key] = value
        if value is None or value < 0:
            reasons.append(key)
    if total is not None and all(value is not None for value in counts.values()):
        if sum(value for value in counts.values() if value is not None) != total:
            reasons.append("count_mismatch")
    if counts["mismatched"] is not None and counts["mismatched"] > 0:
        reasons.append("mismatched")
    if counts["invalid"] is not None and counts["invalid"] > 0:
        reasons.append("invalid")

    classifications_raw = report.get("classificationCounts") if isinstance(report, Mapping) else None
    classifications = (
        classifications_raw if isinstance(classifications_raw, Mapping) else {}
    )
    if not isinstance(classifications_raw, Mapping):
        reasons.append("classificationCounts")
    pending = _as_count(classifications.get("pending_a_review"))
    if pending is None or pending < 0:
        reasons.append("pending_a_review")
    elif pending > 0:
        reasons.append("pending_a_review")

    dart_raw = report.get("dart") if isinstance(report, Mapping) else None
    dart = dart_raw if isinstance(dart_raw, Mapping) else {}
    if not isinstance(dart_raw, Mapping):
        reasons.append("dart")
    if dart.get("invalid") is not False:
        reasons.append("dart_invalid")
    if dart.get("error"):
        reasons.append("dart_error")
    returncode = dart.get("returncode")
    code = _as_count(returncode)
    if code is None:
        reasons.append("dart_returncode")
    elif code != 0:
        reasons.append("dart_returncode")

    # Keep diagnostics stable if multiple validation checks hit the same field.
    reasons = list(dict.fromkeys(reasons))
    gate_summary = dict(summary)
    gate_summary.update({
        "pending_a_review": pending,
        "dartInvalid": dart.get("invalid"),
        "dartReturncode": returncode,
        "dartError": dart.get("error"),
    })
    return {
        "status": "blocked" if reasons else "passed",
        "reasons": reasons,
        "summary": gate_summary,
    }


def _classify_value(value: Any) -> str:
    if isinstance(value, Mapping) and (
        value.get("degraded") is True or value.get("fallback") is True
    ):
        return "degraded"
    return "success"


def _thread_call(call: Callable[[], Any], timeout_ms: int, clock: Callable[[], float]) -> dict[str, Any]:
    started = clock()
    outcome: dict[str, Any] = {}

    def invoke() -> None:
        try:
            outcome["value"] = call()
        except BaseException as exc:  # runner failures are benchmark data
            outcome["exception"] = exc

    worker = threading.Thread(target=invoke, daemon=True)
    worker.start()
    worker.join(timeout_ms / 1000.0)
    result: dict[str, Any] = {
        "durationMs": round(max(0.0, (clock() - started) * 1000.0), 3),
        "timeoutMs": timeout_ms,
        "isolation": "thread",
    }
    result["wallDurationMs"] = result["durationMs"]
    if worker.is_alive():
        result.update({"status": "timeout", "timeoutUncancellable": True, "wallDurationMs": result["durationMs"]})
    elif "exception" in outcome:
        exc = outcome["exception"]
        result.update({"status": "failure", "errorType": type(exc).__name__, "error": str(exc)})
    elif "value" not in outcome:
        result.update({"status": "failure", "errorType": "WorkerError", "error": "worker exited without a value"})
    else:
        value = outcome["value"]
        result.update({"result": value, "status": _classify_value(value)})
    return result


def _process_invoke(call: Callable[[], Any], output: Any) -> None:
    try:
        output.put(("value", call()))
    except BaseException as exc:
        try:
            output.put(("exception", type(exc).__name__, str(exc)))
        except BaseException:
            pass


def _process_call(call: Callable[[], Any], timeout_ms: int, clock: Callable[[], float]) -> dict[str, Any]:
    context_name = "fork" if "fork" in multiprocessing.get_all_start_methods() else "spawn"
    context = multiprocessing.get_context(context_name)
    output = context.Queue()
    started = clock()
    worker = context.Process(target=_process_invoke, args=(call, output), daemon=True)
    try:
        worker.start()
    except BaseException:
        try:
            output.cancel_join_thread()
        except Exception:
            pass
        output.close()
        try:
            worker.close()
        except Exception:
            pass
        return _thread_call(call, timeout_ms, clock)
    worker.join(timeout_ms / 1000.0)
    timed_out = worker.is_alive()
    if timed_out:
        worker.terminate()
        worker.join()
    result: dict[str, Any] = {
        "durationMs": round(max(0.0, (clock() - started) * 1000.0), 3),
        "timeoutMs": timeout_ms,
        "isolation": "process",
    }
    result["wallDurationMs"] = result["durationMs"]
    message: tuple[Any, ...] | None = None
    try:
        message = output.get(timeout=0.1) if not timed_out else None
    except Exception:
        message = None
    try:
        output.cancel_join_thread()
    except Exception:
        pass
    output.close()
    try:
        worker.close()
    except Exception:
        pass
    if timed_out:
        result["status"] = "timeout"
    elif message and message[0] == "exception":
        result.update({"status": "failure", "errorType": message[1], "error": message[2]})
    elif message and message[0] == "value":
        result.update({"result": message[1], "status": _classify_value(message[1])})
    else:
        result.update({"status": "failure", "errorType": "WorkerError", "error": "worker exited without a value"})
    return result


def measure_call(
    call: Callable[[], Any],
    *,
    timeoutMs: int,
    clock: Callable[[], float] = time.perf_counter,
) -> dict[str, Any]:
    """Run a picklable call in a killable process, or a daemon thread fallback."""

    if isinstance(timeoutMs, bool) or not isinstance(timeoutMs, int) or timeoutMs < 0:
        raise ValueError("timeoutMs must be non-negative")
    try:
        pickle.dumps(call)
    except Exception:
        return _thread_call(call, timeoutMs, clock)
    return _process_call(call, timeoutMs, clock)


def _duration(sample: Mapping[str, Any]) -> float | None:
    value = sample.get("durationMs")
    if value is None:
        value = sample.get("duration_ms")
    if isinstance(value, bool):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) and number >= 0 else None


def summarize_samples(samples: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Aggregate benchmark outcomes and non-timeout latency statistics."""

    sample_count = len(samples)
    timeout_count = 0
    failure_count = 0
    degraded_count = 0
    successful_count = 0
    durations: list[float] = []
    for sample in samples:
        if not isinstance(sample, Mapping):
            failure_count += 1
            continue
        status = sample.get("status")
        if status == "timeout":
            timeout_count += 1
        elif status == "failure":
            failure_count += 1
        elif status == "degraded":
            degraded_count += 1
            successful_count += 1
            duration = _duration(sample)
            if duration is not None:
                durations.append(duration)
        elif status == "success":
            successful_count += 1
            duration = _duration(sample)
            if duration is not None:
                durations.append(duration)
        else:
            failure_count += 1

    def rounded(value: float | None) -> float | None:
        return None if value is None else round(value, 3)

    return {
        "sampleCount": sample_count,
        "successfulSampleCount": successful_count,
        "timeoutCount": timeout_count,
        "failureCount": failure_count,
        "degradedCount": degraded_count,
        "p50Ms": rounded(percentile(durations, 0.50)) if durations else None,
        "p95Ms": rounded(percentile(durations, 0.95)) if durations else None,
        "p99Ms": rounded(percentile(durations, 0.99)) if durations else None,
        "minMs": rounded(min(durations)) if durations else None,
        "maxMs": rounded(max(durations)) if durations else None,
    }


STRATEGIES = ("protectDeadline", "protectRecovery", "minimizeChanges")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _error_record(*, operation: str, task_count: int, status: str, message: str, strategy: str | None = None, error_type: str | None = None) -> dict[str, Any]:
    record: dict[str, Any] = {
        "operation": operation,
        "taskCount": task_count,
        "status": status,
        "type": error_type or status.title(),
        "message": message,
        "error": message,
    }
    if strategy is not None:
        record["strategy"] = strategy
    return record


def _numeric(value: Any, default: float = 0.0) -> float:
    if isinstance(value, bool):
        return default
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return number if math.isfinite(number) else default


def _valid_plan_result(value: Any) -> bool:
    if not isinstance(value, Mapping) or not isinstance(value.get("entries"), list) or not isinstance(value.get("issues"), list):
        return False
    for entry in [*value["entries"], *value["issues"]]:
        if not isinstance(entry, Mapping):
            return False
        if "id" in entry and not isinstance(entry.get("id"), str):
            return False
        if "time" in entry and not isinstance(entry.get("time"), Mapping):
            return False
    return True


def _option_map(value: Any) -> dict[str, Mapping[str, Any]] | None:
    raw = value.get("options") if isinstance(value, Mapping) else value
    if not isinstance(raw, list):
        return None
    options: dict[str, Mapping[str, Any]] = {}
    for option in raw:
        if not isinstance(option, Mapping) or not isinstance(option.get("strategy"), str):
            return None
        strategy = str(option["strategy"])
        if strategy in options:
            return None
        options[strategy] = option
    return options


_OPTION_METRICS = ("issueCount", "hardIssueCount", "movedEntryCount", "recoveryMinutes")


def _validate_option(strategy: str, option: Mapping[str, Any] | None) -> str | None:
    if option is None:
        return f"missing option: {strategy}"
    if option.get("strategy") != strategy:
        return f"option strategy must be {strategy}"
    if not isinstance(option.get("plannedEntries"), list):
        return "plannedEntries must be a list"
    for key in _OPTION_METRICS:
        value = option.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return f"{key} must be a finite non-negative number"
        try:
            number = float(value)
        except (TypeError, ValueError):
            return f"{key} must be a finite non-negative number"
        if not math.isfinite(number) or number < 0:
            return f"{key} must be a finite non-negative number"
    return None


def _memory_wrapped_call(call: Callable[[], Any]) -> dict[str, Any]:
    was_tracing = tracemalloc.is_tracing()
    if not was_tracing:
        tracemalloc.start()
    current_before, _ = tracemalloc.get_traced_memory()
    tracemalloc.reset_peak()
    started = time.perf_counter()
    try:
        value = call()
        inner_duration = (time.perf_counter() - started) * 1000.0
        _, peak = tracemalloc.get_traced_memory()
        return {"__benchmark_value__": value, "__peak_memory_bytes__": int(max(0, peak - current_before)), "__inner_duration_ms__": round(inner_duration, 3)}
    finally:
        if not was_tracing:
            tracemalloc.stop()


def _run_sample(
    runner: Callable[[dict[str, Any]], Any],
    request: dict[str, Any],
    *,
    operation: str,
    task_count: int,
    timeout_ms: int,
    clock: Callable[[], float],
) -> dict[str, Any]:
    observed = measure_call(partial(_memory_wrapped_call, partial(runner, copy.deepcopy(request))), timeoutMs=timeout_ms, clock=clock)
    observed["operation"] = operation
    observed["taskCount"] = task_count
    if observed.get("status") in {"success", "degraded"}:
        wrapped = observed.get("result")
        if isinstance(wrapped, Mapping) and "__benchmark_value__" in wrapped:
            observed["result"] = wrapped.get("__benchmark_value__")
            observed["peakMemoryBytes"] = wrapped.get("__peak_memory_bytes__")
            observed["innerDurationMs"] = wrapped.get("__inner_duration_ms__")
            observed["wallDurationMs"] = observed.get("durationMs")
            observed["durationMs"] = observed.get("innerDurationMs")
            observed["status"] = _classify_value(observed["result"])
        else:
            observed.update({"status": "failure", "errorType": "WorkerError", "error": "worker did not return benchmark payload"})
    if observed.get("status") in {"success", "degraded"}:
        try:
            json.dumps(observed.get("result"), allow_nan=False)
        except (TypeError, ValueError):
            observed.update({"status": "failure", "errorType": "MalformedJSON", "error": "result is not JSON serializable"})
    if observed.get("status") in {"success", "degraded"}:
        if operation == "plan" and not _valid_plan_result(observed.get("result")):
            observed.update({"status": "failure", "errorType": "MalformedResult", "error": "plan result must contain entries and issues lists"})
        elif operation == "rescue" and _option_map(observed.get("result")) is None:
            observed.update({"status": "failure", "errorType": "MalformedResult", "error": "rescue result must contain an options list"})
    return observed


def _strategy_row(task_count: int, samples: Sequence[Mapping[str, Any]], strategy: str, warmups: int, sample_count: int) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    errors: list[dict[str, Any]] = []
    strategy_samples: list[dict[str, Any]] = []
    recommended_count = 0
    metric_values: dict[str, list[float]] = {key: [] for key in ("entryCount", "issueCount", "hardIssueCount", "movedEntryCount", "recoveryMinutes")}
    for sample in samples:
        status = sample.get("status")
        option = None
        if status in {"success", "degraded"}:
            options = _option_map(sample.get("result")) or {}
            if strategy == STRATEGIES[0]:
                for unknown in sorted(set(options) - set(STRATEGIES)):
                    errors.append(_error_record(operation="rescue", task_count=task_count, strategy=unknown, status="failure", error_type="UnknownStrategy", message=f"unknown strategy: {unknown}"))
            option = options.get(strategy)
            validation_error = _validate_option(strategy, option)
            if validation_error is not None:
                status = "failure"
                errors.append(_error_record(operation="rescue", task_count=task_count, strategy=strategy, status="failure", error_type="OptionValidation", message=validation_error))
                option = None
        if option is not None:
            entry_count = option["plannedEntries"]
            if isinstance(entry_count, list):
                metric_values["entryCount"].append(float(len(entry_count)))
                metric_values["issueCount"].append(float(option["issueCount"]))
                metric_values["hardIssueCount"].append(float(option["hardIssueCount"]))
                metric_values["movedEntryCount"].append(float(option["movedEntryCount"]))
                metric_values["recoveryMinutes"].append(float(option["recoveryMinutes"]))
                if option.get("recommended") is True:
                    recommended_count += 1
        item = dict(sample)
        item["status"] = status
        if option is not None:
            item["result"] = {"strategy": strategy, **{key: option.get(key) for key in ("plannedEntries", "issueCount", "hardIssueCount", "movedEntryCount", "recoveryMinutes", "recommended")}}
        strategy_samples.append(item)
    summary = summarize_samples(strategy_samples)
    row: dict[str, Any] = {
        "runtime": "python",
        "operation": "rescue",
        "taskCount": task_count,
        "strategy": strategy,
        "warmups": warmups,
        "samples": sample_count,
        "resultSummary": {},
        "recommendedCount": recommended_count,
    }
    row.update(summary)
    for key, values in metric_values.items():
        label = f"{key[0].upper()}{key[1:]}"
        row[f"avg{label}"] = round(sum(values) / len(values), 3) if values else None
        row[f"min{label}"] = round(min(values), 3) if values else None
        row[f"max{label}"] = round(max(values), 3) if values else None
    if strategy_samples:
        last = strategy_samples[-1]
        if isinstance(last.get("result"), Mapping):
            row["resultSummary"] = {"strategy": strategy, "recommended": last["result"].get("recommended"), "plannedEntryCount": len(last["result"].get("plannedEntries") or [])}
    return row, errors


def run_benchmark(
    *,
    task_counts: Sequence[int],
    warmups: int,
    samples: int,
    seed: int,
    timeoutMs: int,
    parity_report: Mapping[str, Any],
    plan_runner: Callable[[dict[str, Any]], Any] = plan_schedule,
    rescue_runner: Callable[[dict[str, Any]], Any] = build_options,
    clock: Callable[[], float] = time.perf_counter,
) -> dict[str, Any]:
    started = _utc_now()
    gate = evaluate_parity_gate(parity_report)
    base: dict[str, Any] = {
        "schemaVersion": "scheduling-benchmark/v1",
        "command": ["python", "scripts/scheduling_benchmark.py"],
        "startedAt": started,
        "seed": seed,
        "taskCounts": list(task_counts) if isinstance(task_counts, Sequence) and not isinstance(task_counts, (str, bytes)) else task_counts,
        "warmups": warmups,
        "samples": samples,
        "timeoutMs": timeoutMs,
        "gate": gate,
        "runs": [],
        "strategies": [],
        "errors": [],
    }
    if gate["status"] != "passed":
        base["status"] = "blocked"
        base["errors"] = [{"type": "parity_gate", "reason": reason} for reason in gate["reasons"]] or [{"type": "parity_gate", "reason": "blocked"}]
        base["finishedAt"] = _utc_now()
        base["peakRssBytes"] = None
        base["peakMemoryBytes"] = None
        base["rssSource"] = "unavailable"
        base["parentPeakMemoryBytes"] = None
        base["memorySource"] = "tracemalloc"
        return base

    errors: list[dict[str, Any]] = []
    valid_counts = isinstance(task_counts, Sequence) and not isinstance(task_counts, (str, bytes))
    if not valid_counts or any(isinstance(value, bool) or not isinstance(value, int) or value < 1 for value in task_counts):
        errors.append({"type": "validation", "field": "task_counts", "message": "task_counts must contain positive integers"})
    if isinstance(warmups, bool) or not isinstance(warmups, int) or warmups < 0:
        errors.append({"type": "validation", "field": "warmups", "message": "warmups must be non-negative"})
    if isinstance(samples, bool) or not isinstance(samples, int) or samples < 1:
        errors.append({"type": "validation", "field": "samples", "message": "samples must be at least 1"})
    if isinstance(timeoutMs, bool) or not isinstance(timeoutMs, int) or timeoutMs < 0:
        errors.append({"type": "validation", "field": "timeoutMs", "message": "timeoutMs must be non-negative"})
    if isinstance(seed, bool) or not isinstance(seed, int):
        errors.append({"type": "validation", "field": "seed", "message": "seed must be an integer"})
    if errors:
        base["status"] = "failed"
        base["errors"] = errors
        base["finishedAt"] = _utc_now()
        base["peakRssBytes"] = None
        base["peakMemoryBytes"] = None
        base["rssSource"] = "unavailable"
        base["parentPeakMemoryBytes"] = None
        base["memorySource"] = "tracemalloc"
        return base

    tracemalloc.start()
    tracemalloc.reset_peak()
    try:
        for task_count in task_counts:
            request = build_workload(task_count, seed=seed + task_count * 1009)
            for _ in range(warmups):
                _run_sample(plan_runner, request, operation="plan", task_count=task_count, timeout_ms=timeoutMs, clock=clock)
                _run_sample(rescue_runner, request, operation="rescue", task_count=task_count, timeout_ms=timeoutMs, clock=clock)
            plan_samples = [_run_sample(plan_runner, request, operation="plan", task_count=task_count, timeout_ms=timeoutMs, clock=clock) for _ in range(samples)]
            rescue_samples = [_run_sample(rescue_runner, request, operation="rescue", task_count=task_count, timeout_ms=timeoutMs, clock=clock) for _ in range(samples)]
            for operation, measured in (("plan", plan_samples), ("rescue", rescue_samples)):
                summary = summarize_samples(measured)
                row_peaks = [int(sample["peakMemoryBytes"]) for sample in measured if sample.get("status") in {"success", "degraded"} and isinstance(sample.get("peakMemoryBytes"), int)]
                row_peak = max(row_peaks) if row_peaks else None
                row: dict[str, Any] = {"runtime": "python", "operation": operation, "taskCount": task_count, "warmups": warmups, "samples": samples, "samplesData": measured, "peakRssBytes": None, "peakMemoryBytes": row_peak}
                row.update(summary)
                if operation == "plan" and measured:
                    last = measured[-1]
                    result = last.get("result")
                    if isinstance(result, Mapping):
                        row["resultSummary"] = {"entryCount": len(result.get("entries") or []) if isinstance(result.get("entries"), list) else 0, "issueCount": len(result.get("issues") or []) if isinstance(result.get("issues"), list) else 0}
                elif operation == "rescue" and measured:
                    result = measured[-1].get("result")
                    option_map = _option_map(result)
                    row["resultSummary"] = {"strategies": list(option_map or {}), "recommended": next((strategy for strategy, option in (option_map or {}).items() if option.get("recommended") is True), None)}
                base["runs"].append(row)
                for sample in measured:
                    if sample.get("status") in {"failure", "timeout"}:
                        errors.append(
                            _error_record(
                                operation=operation,
                                task_count=task_count,
                                status=str(sample.get("status")),
                                error_type=str(sample.get("errorType") or "") or None,
                                message=str(sample.get("error") or sample.get("status")),
                            )
                        )
            for strategy in STRATEGIES:
                row, strategy_errors = _strategy_row(task_count, rescue_samples, strategy, warmups, samples)
                base["strategies"].append(row)
                errors.extend(strategy_errors)
    finally:
        _, parent_peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
    sample_peaks = [
        int(sample.get("peakMemoryBytes"))
        for row in base["runs"]
        if isinstance(row, Mapping)
        for sample in (row.get("samplesData") or [])
        if isinstance(sample, Mapping) and sample.get("status") in {"success", "degraded"} and isinstance(sample.get("peakMemoryBytes"), int)
    ]
    peak = max(sample_peaks) if sample_peaks else None
    base["errors"] = errors
    completed_samples = sum(
        int(row.get("successfulSampleCount", 0) or 0)
        for row in base["runs"]
        if isinstance(row, Mapping)
    )
    base["status"] = "completed" if completed_samples > 0 else "failed"
    base["finishedAt"] = _utc_now()
    base["peakRssBytes"] = None
    base["peakMemoryBytes"] = peak
    base["rssSource"] = "unavailable"
    base["parentPeakMemoryBytes"] = int(parent_peak)
    base["memorySource"] = "tracemalloc"
    return base


def _markdown_benchmark(report: Mapping[str, Any]) -> str:
    gate = report.get("gate") if isinstance(report.get("gate"), Mapping) else {}
    reasons = gate.get("reasons") if isinstance(gate.get("reasons"), list) else []
    lines = ["# Scheduling benchmark", "", f"- status: {report.get('status')}", f"- parity gate: {gate.get('status')}", f"- gate reasons: {', '.join(map(str, reasons)) or 'none'}", "", "普通 issues 仅作为结果计数，不计入 degradation。", "", "## Plan/Rescue timing", "", "| operation | taskCount | samples | p50Ms | p95Ms | p99Ms | timeouts | failures | degraded |", "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for run in report.get("runs", []):
        if isinstance(run, Mapping):
            lines.append(f"| {run.get('operation')} | {run.get('taskCount')} | {run.get('sampleCount', run.get('samples'))} | {run.get('p50Ms')} | {run.get('p95Ms')} | {run.get('p99Ms')} | {run.get('timeoutCount')} | {run.get('failureCount')} | {run.get('degradedCount')} |")
    lines.extend(["", "## Strategies", "", "| taskCount | strategy | samples | successful | timeouts | failures | degraded | avgEntryCount | avgIssueCount | avgHardIssueCount | avgMovedEntryCount | avgRecoveryMinutes | recommended |", "|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"])
    for row in report.get("strategies", []):
        if isinstance(row, Mapping):
            lines.append(f"| {row.get('taskCount')} | {row.get('strategy')} | {row.get('sampleCount')} | {row.get('successfulSampleCount')} | {row.get('timeoutCount')} | {row.get('failureCount')} | {row.get('degradedCount')} | {row.get('avgEntryCount')} | {row.get('avgIssueCount')} | {row.get('avgHardIssueCount')} | {row.get('avgMovedEntryCount')} | {row.get('avgRecoveryMinutes')} | {row.get('recommendedCount')} |")
    lines.extend(["", "## Errors", ""])
    errors = report.get("errors") if isinstance(report.get("errors"), list) else []
    lines.extend(f"- {json.dumps(error, ensure_ascii=False, sort_keys=True, allow_nan=False)}" for error in errors) if errors else lines.append("- none")
    return "\n".join(lines) + "\n"


def write_benchmark_report(report: Mapping[str, Any], output_dir: Path) -> Path:
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    stem = f"scheduling-benchmark-{timestamp}"
    payload = json.dumps(dict(report), ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"
    markdown = _markdown_benchmark(report)
    index = 0
    while True:
        suffix = "" if index == 0 else f"-{index}"
        json_path = output_dir / f"{stem}{suffix}.json"
        md_path = output_dir / f"{stem}{suffix}.md"
        created_json = False
        created_md = False
        try:
            with json_path.open("x", encoding="utf-8") as handle:
                created_json = True
                handle.write(payload)
            with md_path.open("x", encoding="utf-8") as handle:
                created_md = True
                handle.write(markdown)
            return json_path
        except FileExistsError:
            if created_json:
                try:
                    json_path.unlink()
                except OSError:
                    pass
            if created_md:
                try:
                    md_path.unlink()
                except OSError:
                    pass
            index += 1
        except Exception:
            if created_json:
                try:
                    json_path.unlink()
                except OSError:
                    pass
            if created_md:
                try:
                    md_path.unlink()
                except OSError:
                    pass
            raise


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run scheduling benchmark matrix")
    parser.add_argument("--parity-report", type=Path, default=Path("reports/shared-vector-diff.json"))
    parser.add_argument("--output-dir", type=Path, default=Path("reports/benchmarks"))
    parser.add_argument("--task-count", type=int, action="append", dest="task_counts")
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--seed", type=int, default=20260916)
    parser.add_argument("--timeout-ms", type=int, default=1000, dest="timeout_ms")
    refresh_group = parser.add_mutually_exclusive_group()
    refresh_group.add_argument("--refresh-parity", dest="refresh_parity", action="store_true")
    refresh_group.add_argument("--no-refresh-parity", dest="refresh_parity", action="store_false")
    parser.set_defaults(refresh_parity=True)
    args = parser.parse_args(argv)
    parity_path = args.parity_report if args.parity_report.is_absolute() else REPO_ROOT / args.parity_report
    refresh_error: str | None = None
    if args.refresh_parity:
        with tempfile.TemporaryDirectory(prefix="scheduling-parity-") as refresh_dir_name:
            refresh_dir = Path(refresh_dir_name)
            fresh_path = refresh_dir / "shared-vector-diff.json"
            try:
                refresh_result = subprocess.run(
                    [sys.executable, "scripts/scheduling_parity.py", "--reports-dir", str(refresh_dir)],
                    cwd=REPO_ROOT,
                    check=False,
                )
                returncode = getattr(refresh_result, "returncode", 1)
                parity_path = fresh_path
                if returncode != 0:
                    refresh_error = f"parity refresh failed with returncode {returncode}"
            except Exception as exc:
                refresh_error = f"parity refresh failed: {exc}"
            fresh_parity: Mapping[str, Any] | None = None
            if fresh_path.exists():
                try:
                    parity = json.loads(fresh_path.read_text(encoding="utf-8"))
                    if not isinstance(parity, Mapping):
                        raise ValueError("refreshed parity report must be an object")
                    fresh_parity = parity
                except Exception as exc:
                    refresh_error = f"parity refresh report unavailable: {exc}"
                    parity = {}
            if fresh_parity is None:
                parity = {}
            else:
                parity = fresh_parity
                refresh_error = None
        if refresh_error:
            report = run_benchmark(task_counts=tuple(args.task_counts or (10, 50, 100, 200)), warmups=args.warmups, samples=args.samples, seed=args.seed, timeoutMs=args.timeout_ms, parity_report={})
            report["errors"].append({"type": "parity_refresh", "reason": refresh_error})
            path = write_benchmark_report(report, args.output_dir if args.output_dir.is_absolute() else REPO_ROOT / args.output_dir)
            print(f"benchmark report: {path} status={report.get('status')}")
            return 2
    else:
        parity = None
    try:
        if parity is None:
            parity = json.loads(parity_path.read_text(encoding="utf-8"))
            if not isinstance(parity, Mapping):
                raise ValueError("parity report must be an object")
    except Exception as exc:
        parity = {}
        report = run_benchmark(task_counts=tuple(args.task_counts or (10, 50, 100, 200)), warmups=args.warmups, samples=args.samples, seed=args.seed, timeoutMs=args.timeout_ms, parity_report=parity)
        report["errors"].append({"type": "parity_refresh" if args.refresh_parity else "parity_report", "reason": str(exc)})
    else:
        report = run_benchmark(task_counts=tuple(args.task_counts or (10, 50, 100, 200)), warmups=args.warmups, samples=args.samples, seed=args.seed, timeoutMs=args.timeout_ms, parity_report=parity)
    path = write_benchmark_report(report, args.output_dir if args.output_dir.is_absolute() else REPO_ROOT / args.output_dir)
    print(f"benchmark report: {path} status={report.get('status')}")
    if report.get("status") == "blocked":
        return 2
    if report.get("status") != "completed" or any(error.get("status") in {"failure", "timeout"} for error in report.get("errors", []) if isinstance(error, Mapping)):
        return 1
    return 0


__all__ = [
    "build_options",
    "build_workload",
    "evaluate_parity_gate",
    "measure_call",
    "percentile",
    "plan_schedule",
    "run_benchmark",
    "summarize_samples",
    "write_benchmark_report",
]


if __name__ == "__main__":
    raise SystemExit(main())
