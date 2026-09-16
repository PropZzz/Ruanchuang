"""Small, deterministic primitives used by the scheduling benchmark.

The matrix runner and report writer are intentionally kept out of this module
until parity has been validated.  These helpers are side-effect free apart
from the daemon thread used by :func:`measure_call`.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import math
import multiprocessing
from pathlib import Path
import pickle
import random
import sys
import threading
import time
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
    return {
        "status": "blocked" if reasons else "passed",
        "reasons": reasons,
        "summary": summary,
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
    if worker.is_alive():
        result["status"] = "timeout"
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
        output.close()
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
    message: tuple[Any, ...] | None = None
    try:
        message = output.get(timeout=0.1) if not timed_out else None
    except Exception:
        message = None
    output.close()
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


__all__ = [
    "build_options",
    "build_workload",
    "evaluate_parity_gate",
    "measure_call",
    "percentile",
    "plan_schedule",
    "summarize_samples",
]
