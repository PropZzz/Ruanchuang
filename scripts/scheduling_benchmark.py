"""Small, deterministic primitives used by the scheduling benchmark.

The matrix runner and report writer are intentionally kept out of this module
until parity has been validated.  These helpers are side-effect free apart
from the daemon thread used by :func:`measure_call`.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import math
import random
import threading
import time
from typing import Any, Callable, Mapping, Sequence

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

    values = sorted(float(sample) for sample in samples)
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
    if isinstance(value, float) and value.is_integer() and math.isfinite(value):
        return int(value)
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

    total: int | None = None
    for key in ("total", "fixtures"):
        if key in summary:
            value = summary[key]
            if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
                total = len(value)
            else:
                total = _as_count(value)
            if total is None:
                reasons.append(f"{key}")
            break
    if total is None:
        reasons.append("total")
    elif total <= 0:
        reasons.append("total")

    for key in ("mismatched", "invalid"):
        value = _as_count(summary.get(key, 0))
        if value is None:
            reasons.append(key)
        elif value > 0:
            reasons.append(key)

    classifications_raw = report.get("classificationCounts") if isinstance(report, Mapping) else None
    classifications = (
        classifications_raw if isinstance(classifications_raw, Mapping) else {}
    )
    if not isinstance(classifications_raw, Mapping):
        reasons.append("classificationCounts")
    pending = _as_count(classifications.get("pending_a_review", 0))
    if pending is None:
        reasons.append("pending_a_review")
    elif pending > 0:
        reasons.append("pending_a_review")

    dart_raw = report.get("dart") if isinstance(report, Mapping) else None
    dart = dart_raw if isinstance(dart_raw, Mapping) else {}
    if not isinstance(dart_raw, Mapping):
        reasons.append("dart")
    if dart.get("invalid") is True:
        reasons.append("dart_invalid")
    elif dart.get("invalid") not in (False, None):
        reasons.append("dart_invalid")
    if dart.get("error"):
        reasons.append("dart_error")
    returncode = dart.get("returncode", 0)
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


def measure_call(
    call: Callable[[], Any],
    *,
    timeoutMs: int,
    clock: Callable[[], float] = time.perf_counter,
) -> dict[str, Any]:
    """Run ``call`` on a daemon thread and classify its outcome."""

    if isinstance(timeoutMs, bool) or not isinstance(timeoutMs, int) or timeoutMs < 0:
        raise ValueError("timeoutMs must be non-negative")
    started = clock()
    outcome: dict[str, Any] = {}

    def invoke() -> None:
        try:
            outcome["value"] = call()
        except Exception as exc:  # runner failures are data, not process errors
            outcome["exception"] = exc

    worker = threading.Thread(target=invoke, daemon=True)
    worker.start()
    worker.join(timeoutMs / 1000.0)
    duration_ms = max(0.0, (clock() - started) * 1000.0)
    result: dict[str, Any] = {"durationMs": round(duration_ms, 3), "timeoutMs": timeoutMs}
    if worker.is_alive():
        result["status"] = "timeout"
        return result
    if "exception" in outcome:
        exc = outcome["exception"]
        result.update(
            {
                "status": "failure",
                "errorType": type(exc).__name__,
                "error": str(exc),
            }
        )
        return result

    value = outcome.get("value")
    result["result"] = value
    if isinstance(value, Mapping) and (value.get("degraded") or value.get("fallback")):
        result["status"] = "degraded"
    else:
        result["status"] = "success"
    return result


def _duration(sample: Mapping[str, Any]) -> float | None:
    value = sample.get("durationMs")
    if value is None:
        value = sample.get("duration_ms")
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
