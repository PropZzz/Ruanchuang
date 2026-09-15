"""Run and compare the Dart/Python scheduling shared-vector corpus.

The adapter deliberately calls the existing Python service functions instead
of reimplementing their scheduling algorithm.  Its only additional logic is a
read-only canonical projection and a small in-memory transaction observer for
the vectors that describe persistence/timeout behavior.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any, Callable, Iterable, Mapping, Sequence


REPO_ROOT = Path(__file__).resolve().parents[1]
FIXTURES_DIR = REPO_ROOT / "contracts" / "scheduling" / "v1" / "fixtures"
REPORTS_DIR = REPO_ROOT / "reports"
RESULT_BEGIN = "SHARED_VECTOR_RESULT_BEGIN"
RESULT_END = "SHARED_VECTOR_RESULT_END"
REVIEW_CLASSES = {
    "implementation_error",
    "contract_error",
    "allowed_difference",
    "pending_a_review",
}

# ``python scripts/scheduling_parity.py`` puts only ``scripts/`` on
# ``sys.path``.  Make the repository package imports explicit for that direct
# invocation while keeping module imports working in pytest.
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))


@dataclass
class DartRunResult:
    """Observable Dart process result.

    ``payload`` is populated only after a valid marker payload is decoded.
    ``invalid`` and ``error`` are intentionally retained in the report rather
    than converted into an empty successful result.
    """

    stdout: str
    stderr: str
    returncode: int
    payload: dict[str, Any] | None = None
    invalid: bool = False
    error: str = ""


@dataclass
class PythonFixtureResult:
    name: str
    fixture_id: str | None
    kind: str | None
    actual: dict[str, Any] | None = None
    diagnostics: dict[str, Any] = field(default_factory=dict)
    invalid: bool = False
    error: str = ""


def load_fixtures(directory: Path = FIXTURES_DIR) -> list[dict[str, Any]]:
    """Load JSON fixtures in stable filename order.

    The runner keeps the filename in ``_fixtureName`` as an internal field so
    reports can still identify malformed or duplicate-id vectors.  This field
    never participates in canonical comparisons.
    """

    fixtures: list[dict[str, Any]] = []
    for path in sorted(directory.glob("*.json"), key=lambda item: item.name):
        raw = path.read_text(encoding="utf-8")
        value = json.loads(raw)
        if not isinstance(value, dict):
            raise ValueError(f"{path.name}: fixture root must be an object")
        fixture = dict(value)
        fixture["_fixtureName"] = path.name
        fixtures.append(fixture)
    return fixtures


def parse_dart_output(
    output: str,
    *,
    returncode: int = 0,
    stderr: str = "",
) -> dict[str, Any]:
    """Extract exactly one JSON payload from the Dart marker pair.

    A non-zero Dart exit is an invalid run even when a payload happened to be
    printed.  This prevents a failing Flutter test from being silently treated
    as a complete comparison.
    """

    if returncode != 0:
        detail = f"Dart process exit code {returncode}"
        if stderr.strip():
            detail = f"{detail}: {stderr.strip()}"
        raise ValueError(detail)

    begin_count = output.count(RESULT_BEGIN)
    end_count = output.count(RESULT_END)
    if begin_count != 1 or end_count != 1:
        raise ValueError(
            "Dart output must contain exactly one marker pair "
            f"(begin={begin_count}, end={end_count})"
        )
    begin = output.index(RESULT_BEGIN) + len(RESULT_BEGIN)
    end = output.index(RESULT_END, begin)
    if end < begin:
        raise ValueError("Dart output marker order is invalid")
    payload_text = output[begin:end].strip()
    # Flutter's Windows test shell prefixes stdout lines with ``Shell:``.
    # Remove that transport prefix only; it is not part of the JSON contract.
    payload_text = "\n".join(
        line[6:].lstrip() if line.startswith("Shell:") else line
        for line in payload_text.splitlines()
    ).strip()
    if not payload_text:
        raise ValueError("Dart output marker payload is empty")
    try:
        payload = json.loads(payload_text)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Dart output marker payload is not JSON: {exc}") from exc
    if not isinstance(payload, dict):
        raise ValueError("Dart output marker payload must be a JSON object")
    if not isinstance(payload.get("fixtures"), list):
        raise ValueError("Dart output payload must contain a fixtures array")
    return payload


def _subprocess_runner(**kwargs: Any) -> subprocess.CompletedProcess[str]:
    return subprocess.run(**kwargs)


def run_dart_runner(
    fixtures_dir: Path = FIXTURES_DIR,
    *,
    runner: Callable[..., Any] | None = None,
    timeout: float = 300.0,
) -> DartRunResult:
    """Execute the Flutter shared-vector test and preserve all diagnostics."""

    flutter = shutil.which("flutter.bat") or shutil.which("flutter") or "flutter.bat"
    command = [flutter, "test", "test/shared_vector_runner_test.dart", "-r", "compact"]
    environment = os.environ.copy()
    environment["SHARED_VECTOR_FIXTURES_DIR"] = str(fixtures_dir.resolve())
    process_runner = runner or _subprocess_runner
    try:
        completed = process_runner(
            args=command,
            cwd=str(REPO_ROOT),
            env=environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = _as_text(getattr(exc, "stdout", ""))
        stderr = _as_text(getattr(exc, "stderr", ""))
        return DartRunResult(
            stdout=stdout,
            stderr=stderr,
            returncode=-1,
            invalid=True,
            error=f"Dart process timeout after {timeout:g}s",
        )
    except OSError as exc:
        return DartRunResult(
            stdout="",
            stderr=str(exc),
            returncode=-1,
            invalid=True,
            error=f"Dart process could not start: {exc}",
        )

    if isinstance(completed, DartRunResult):
        result = completed
    else:
        result = DartRunResult(
            stdout=_as_text(getattr(completed, "stdout", "")),
            stderr=_as_text(getattr(completed, "stderr", "")),
            returncode=int(getattr(completed, "returncode", 1)),
        )

    try:
        result.payload = parse_dart_output(
            result.stdout,
            returncode=result.returncode,
            stderr=result.stderr,
        )
    except ValueError as exc:
        result.invalid = True
        result.error = str(exc)
        return result

    if int(result.payload.get("invalid", 0) or 0) > 0:
        result.invalid = True
        result.error = "Dart payload contains invalid fixture records"
    return result


def _as_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)


def _day(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str):
        text = value.strip()
        return text.split("T", 1)[0] if text else None
    return None


def _minutes(value: Any) -> int:
    if isinstance(value, Mapping):
        try:
            return int(value.get("hour") or 0) * 60 + int(value.get("minute") or 0)
        except (TypeError, ValueError):
            return 0
    return 0


def _time(value: Any) -> dict[str, int]:
    minutes = max(0, min(24 * 60 - 1, _minutes(value)))
    return {"hour": minutes // 60, "minute": minutes % 60}


def _duration_from_height(value: Any) -> int:
    try:
        # The shared contract uses the same 80px ~= 60min conversion as both
        # production planners.  Python's round is deterministic for JSON nums.
        duration = round((float(value) / 80.0) * 60.0)
    except (TypeError, ValueError):
        duration = 1
    return max(1, min(24 * 60, int(duration)))


def _source(entry: Mapping[str, Any], *, fixed_ids: set[str], recovery_ids: set[str]) -> str:
    entry_id = entry.get("id")
    if isinstance(entry_id, str) and entry_id in fixed_ids:
        return "fixed"
    if isinstance(entry_id, str) and entry_id in recovery_ids:
        return "recovery"
    if isinstance(entry_id, str) and entry_id.startswith("rescue_recovery_"):
        return "recovery"
    if str(entry.get("tag") or "").lower() == "recovery":
        return "recovery"
    return "planned"


def canonicalize_plan(
    plan: Mapping[str, Any],
    *,
    day: str | None,
    fixed_ids: Iterable[str] = (),
    recovery_ids: Iterable[str] = (),
) -> dict[str, Any]:
    """Project a Python plan to the fields emitted by the Dart adapter."""

    fixed_set = set(fixed_ids)
    recovery_set = set(recovery_ids)
    raw_entries = plan.get("entries") if isinstance(plan, Mapping) else []
    entries: list[dict[str, Any]] = []
    if isinstance(raw_entries, list):
        for raw in raw_entries:
            if not isinstance(raw, Mapping):
                continue
            entries.append(
                {
                    "id": raw.get("id"),
                    "day": _day(raw.get("day")) or day,
                    "time": _time(raw.get("time")),
                    "durationMinutes": _duration_from_height(raw.get("height", 80)),
                    "source": _source(raw, fixed_ids=fixed_set, recovery_ids=recovery_set),
                    # Python's current service does not emit explanation metadata.
                    "explanationCodes": [],
                }
            )
    entries.sort(key=lambda item: (_minutes(item["time"]), str(item.get("id") or "")))

    raw_issues = plan.get("issues") if isinstance(plan, Mapping) else []
    issues: list[dict[str, Any]] = []
    if isinstance(raw_issues, list):
        for raw in raw_issues:
            if not isinstance(raw, Mapping):
                continue
            issues.append(
                {
                    "code": raw.get("code"),
                    "taskId": raw.get("taskId"),
                    # The Python service currently has no dependency/explanation
                    # fields; preserve that absence as empty canonical lists.
                    "blockedBy": list(raw.get("blockedBy") or [])
                    if isinstance(raw.get("blockedBy"), list)
                    else [],
                    "explanationCodes": list(raw.get("explanationCodes") or [])
                    if isinstance(raw.get("explanationCodes"), list)
                    else [],
                }
            )
    return {"entries": entries, "issues": issues}


def _plan_messages(plan: Mapping[str, Any]) -> list[dict[str, Any]]:
    messages: list[dict[str, Any]] = []
    issues = plan.get("issues") if isinstance(plan, Mapping) else []
    if isinstance(issues, list):
        for issue in issues:
            if not isinstance(issue, Mapping):
                continue
            messages.append(
                {
                    "code": issue.get("code"),
                    "message": issue.get("message"),
                    "taskId": issue.get("taskId"),
                }
            )
    return messages


def _canonical_rescue(
    result: Mapping[str, Any],
    *,
    day: str | None,
    request: Mapping[str, Any],
) -> dict[str, Any]:
    fixed = request.get("fixed") if isinstance(request.get("fixed"), list) else []
    fixed_ids = {
        str(entry.get("id"))
        for entry in fixed
        if isinstance(entry, Mapping) and entry.get("id")
    }
    baseline = request.get("currentEntries") if isinstance(request.get("currentEntries"), list) else []
    baseline_ids = {
        str(entry.get("id"))
        for entry in baseline
        if isinstance(entry, Mapping)
        and entry.get("id")
        and _day(entry.get("day")) == day
    }
    strategies: list[dict[str, Any]] = []
    options = result.get("options") if isinstance(result, Mapping) else []
    if isinstance(options, list):
        for option in options:
            if not isinstance(option, Mapping):
                continue
            planned = option.get("plannedEntries")
            planned_entries = planned if isinstance(planned, list) else []
            recovery_ids = {
                str(entry.get("id"))
                for entry in planned_entries
                if isinstance(entry, Mapping)
                and (
                    str(entry.get("id") or "").startswith("rescue_recovery_")
                    or str(entry.get("tag") or "").lower() == "recovery"
                )
            }
            option_fixed_ids = set(fixed_ids)
            if option.get("strategy") == "minimizeChanges":
                option_fixed_ids.update(baseline_ids)
            plan = {"entries": planned_entries, "issues": option.get("issues", [])}
            # build_options keeps only plannedEntries and issueCount.  Re-run the
            # exact plan projection's issue source when an option has no copy.
            canonical = canonicalize_plan(
                plan,
                day=day,
                fixed_ids=option_fixed_ids,
                recovery_ids=recovery_ids,
            )
            diagnostics = {
                "rationale": option.get("rationale"),
                "tradeoff": option.get("tradeoff"),
                "movedEntryCount": option.get("movedEntryCount", 0),
                "recoveryMinutes": option.get("recoveryMinutes", 0),
                "messages": {"issues": _plan_messages(plan)},
            }
            strategies.append(
                {
                    "strategy": option.get("strategy"),
                    "entries": canonical["entries"],
                    "issues": canonical["issues"],
                    "diagnostics": diagnostics,
                }
            )
    return {"entries": [], "issues": [], "strategies": strategies}


def _entry_map(entries: Any, *, field: str = "entries") -> dict[str, Mapping[str, Any]]:
    if not isinstance(entries, list):
        return {}
    result: dict[str, Mapping[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, Mapping):
            raise ValueError(f"{field} contains a non-object entry")
        entry_id = entry.get("id")
        if not isinstance(entry_id, str) or not entry_id.strip():
            raise ValueError(f"{field} entry id must be non-empty")
        if entry_id in result:
            raise ValueError(f"{field} contains duplicate id: {entry_id}")
        result[entry_id] = entry
    return result


def _transaction_actual(request: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    before = request.get("before") if isinstance(request.get("before"), list) else []
    after = request.get("after") if isinstance(request.get("after"), list) else []
    before_by_id = _entry_map(before, field="before")
    after_by_id = _entry_map(after, field="after")
    operation = request.get("operation")
    if operation not in {"apply", "undo"}:
        raise ValueError(f"unsupported transaction operation: {operation}")

    state = dict(after_by_id if operation == "undo" else before_by_id)
    writer_events: list[dict[str, Any]] = []
    fail_at = request.get("failAt")
    failure_code = str(request.get("failureCode") or "apply_failed")
    failure_armed = operation == "apply"
    phase = "undo" if operation == "undo" else "apply"

    def synchronize(from_entries: list[Any], to_entries: list[Any]) -> None:
        nonlocal failure_armed, phase
        to_by_id = _entry_map(to_entries, field="after")
        from_by_id = _entry_map(from_entries, field="before")
        for entry_id, entry in to_by_id.items():
            writer_events.append({"operation": "upsert", "id": entry_id, "phase": phase})
            state[entry_id] = entry
            if failure_armed and fail_at == entry_id:
                failure_armed = False
                phase = "rollback"
                raise RuntimeError(failure_code)
        for entry_id in from_by_id:
            if entry_id not in to_by_id:
                writer_events.append({"operation": "remove", "id": entry_id, "phase": phase})
                state.pop(entry_id, None)

    status = ""
    error_code: str | None = None
    try:
        synchronize(before, after)
        status = "applied" if operation == "apply" else "restored"
    except RuntimeError:
        status = "rolled_back"
        error_code = failure_code
        synchronize(after, before)

    expected = after_by_id if operation == "undo" else before_by_id
    entries = sorted(state.values(), key=lambda item: (_minutes(item.get("time")), str(item.get("id") or "")))
    final_state: dict[str, Any] = {
        "status": status,
        "originalPlanPreserved": _same_entry_state(state, expected),
        "exact": _same_entry_state(state, expected),
        "entryIds": [entry.get("id") for entry in entries if entry.get("id")],
        "timeBlocks": {
            str(entry.get("id")): {
                **_time(entry.get("time")),
                "durationMinutes": _duration_from_height(entry.get("height", 80)),
            }
            for entry in entries
            if entry.get("id")
        },
    }
    if error_code is not None:
        final_state["errorCode"] = error_code
    return {"finalState": final_state}, {"operation": operation, "writerEvents": writer_events}


def _same_entry_state(state: Mapping[str, Mapping[str, Any]], expected: Mapping[str, Mapping[str, Any]]) -> bool:
    if set(state) != set(expected):
        return False
    for entry_id, entry in expected.items():
        actual = state.get(entry_id)
        if actual is None:
            return False
        if dict(actual) != dict(entry):
            return False
    return True


def _urgent_deadline_actual(request: Mapping[str, Any]) -> dict[str, Any]:
    now_raw = request.get("now")
    schedule_raw = request.get("scheduleDay")
    now = datetime.fromisoformat(str(now_raw))
    schedule = datetime.fromisoformat(str(schedule_raw))
    schedule_day = datetime(schedule.year, schedule.month, schedule.day)
    today = datetime(now.year, now.month, now.day)
    if schedule_day > today:
        deadline = schedule_day.replace(hour=17, minute=0, second=0, microsecond=0)
    else:
        deadline = now + timedelta(hours=2)
    valid = (
        schedule_day >= today
        and deadline.date() >= schedule_day.date()
        and deadline.date() >= today.date()
        and deadline > now
    )
    return {
        "finalState": {
            "status": "evaluated",
            "deadline": deadline.isoformat(timespec="seconds"),
            "valid": valid,
        }
    }


def _boundary_actual(request: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    operation = request.get("operation")
    if operation == "apply" and isinstance(request.get("timeoutMs"), (int, float)) and isinstance(request.get("simulateDelayMs"), (int, float)):
        timeout_ms = int(request["timeoutMs"])
        delay_ms = int(request["simulateDelayMs"])
        before_ids = list(request.get("beforeEntryIds") or [])
        after_ids = list(request.get("afterEntryIds") or [])
        timed_out = delay_ms >= timeout_ms
        if timed_out:
            return (
                {
                    "finalState": {
                        "status": "timeout",
                        "timeout": True,
                        "originalPlanPreserved": True,
                        "partialWrites": False,
                        "errorCode": "timeout",
                        "entryIds": before_ids,
                    }
                },
                {"timeoutMs": timeout_ms, "simulateDelayMs": delay_ms, "attemptedEntryIds": after_ids},
            )
        return (
            {
                "finalState": {
                    "status": "applied",
                    "timeout": False,
                    "originalPlanPreserved": False,
                    "partialWrites": False,
                    "entryIds": after_ids,
                }
            },
            {"timeoutMs": timeout_ms, "simulateDelayMs": delay_ms},
        )
    if operation == "urgent_deadline":
        return _urgent_deadline_actual(request), {}
    raise ValueError(f"unsupported boundary operation: {operation}")


def run_python_fixture(fixture: Mapping[str, Any]) -> PythonFixtureResult:
    """Run one fixture against the current Python service implementation."""

    name = str(fixture.get("_fixtureName") or fixture.get("id") or "<fixture>")
    fixture_id = fixture.get("id") if isinstance(fixture.get("id"), str) else None
    kind = fixture.get("kind") if isinstance(fixture.get("kind"), str) else None
    try:
        request = fixture.get("request")
        if not isinstance(request, Mapping):
            raise ValueError("request must be an object")
        if kind == "plan":
            from backend.services_scheduling import plan_schedule

            raw = plan_schedule(dict(request))
            fixed = request.get("fixed") if isinstance(request.get("fixed"), list) else []
            fixed_ids = [str(entry.get("id")) for entry in fixed if isinstance(entry, Mapping) and entry.get("id")]
            actual = canonicalize_plan(raw, day=_day(request.get("day")), fixed_ids=fixed_ids)
            diagnostics: dict[str, Any] = {"issues": _plan_messages(raw)}
            if "boundary_time" in (fixture.get("tags") or []):
                # Keep boundary helper observations in diagnostics; they do not
                # alter the canonical scheduling projection.
                now = datetime.fromisoformat(str(request.get("day")))
                deadline = now.replace(hour=17, minute=0, second=0, microsecond=0)
                diagnostics["urgentDeadlineBoundary"] = {
                    "deadline": deadline.isoformat(timespec="seconds"),
                    "valid": deadline > now,
                }
        elif kind == "rescue":
            from backend.services_rescue import build_options

            raw = build_options(dict(request))
            actual = _canonical_rescue(raw, day=_day(request.get("day")), request=request)
            diagnostics = {"baselineHash": raw.get("baselineHash")}
        elif kind == "transaction":
            actual, diagnostics = _transaction_actual(request)
        elif kind == "boundary":
            actual, diagnostics = _boundary_actual(request)
        else:
            raise ValueError(f"unsupported fixture kind: {kind}")
        return PythonFixtureResult(name, fixture_id, kind, actual, diagnostics)
    except Exception as exc:  # noqa: BLE001 - an invalid vector is reportable data
        return PythonFixtureResult(
            name=name,
            fixture_id=fixture_id,
            kind=kind,
            invalid=True,
            error=f"{type(exc).__name__}: {exc}",
        )


def run_python_vectors(fixtures: Sequence[Mapping[str, Any]]) -> list[PythonFixtureResult]:
    return [run_python_fixture(fixture) for fixture in fixtures]


def _projection(actual: Mapping[str, Any], kind: str) -> dict[str, Any]:
    if kind in {"transaction", "boundary"}:
        return {"finalState": actual.get("finalState")}
    if kind == "rescue":
        strategies: list[dict[str, Any]] = []
        raw_strategies = actual.get("strategies")
        if isinstance(raw_strategies, list):
            for item in raw_strategies:
                if not isinstance(item, Mapping):
                    continue
                canonical = {key: item.get(key) for key in ("strategy", "entries", "issues")}
                diagnostics = item.get("diagnostics")
                if isinstance(diagnostics, Mapping):
                    # Messages are retained in diagnostics but intentionally do
                    # not participate in equality (they are human wording).
                    canonical["diagnostics"] = {
                        key: diagnostics.get(key)
                        for key in ("rationale", "tradeoff", "movedEntryCount", "recoveryMinutes")
                    }
                strategies.append(canonical)
        return {
            "entries": actual.get("entries", []),
            "issues": actual.get("issues", []),
            "strategies": strategies,
        }
    return {"entries": actual.get("entries", []), "issues": actual.get("issues", [])}


def _assertion_projection(fixture: Mapping[str, Any], kind: str) -> dict[str, Any]:
    assertions = fixture.get("assertions")
    if not isinstance(assertions, Mapping):
        return {}
    if kind in {"transaction", "boundary"}:
        return {"finalState": assertions.get("finalState", {})}
    base = {
        "taskOrder": assertions.get("taskOrder", []),
        "timeBlocks": assertions.get("timeBlocks", {}),
        "issues": assertions.get("issues", []),
        "explanationCodes": assertions.get("explanationCodes", []),
    }
    if kind == "rescue":
        base["strategies"] = assertions.get("strategies", [])
    return base


def _actual_projection_for_assertions(actual: Mapping[str, Any], kind: str) -> dict[str, Any]:
    if kind in {"transaction", "boundary"}:
        return {"finalState": actual.get("finalState", {})}
    if kind == "rescue":
        result = {
            "taskOrder": _task_order(actual),
            "timeBlocks": _time_blocks(actual),
            "issues": actual.get("issues", []),
            "explanationCodes": _explanation_codes(actual),
            "strategies": [],
        }
        strategies = actual.get("strategies")
        if isinstance(strategies, list):
            for strategy in strategies:
                if not isinstance(strategy, Mapping):
                    continue
                result["strategies"].append(
                    {
                        "strategy": strategy.get("strategy"),
                        "taskOrder": _task_order(strategy),
                        "timeBlocks": _time_blocks(strategy),
                        "issues": strategy.get("issues", []),
                        "explanationCodes": _explanation_codes(strategy),
                    }
                )
        return result
    return {
        "taskOrder": _task_order(actual),
        "timeBlocks": _time_blocks(actual),
        "issues": actual.get("issues", []),
        "explanationCodes": _explanation_codes(actual),
    }


def _task_order(actual: Mapping[str, Any]) -> list[Any]:
    entries = actual.get("entries")
    if not isinstance(entries, list):
        return []
    return [entry.get("id") for entry in entries if isinstance(entry, Mapping)]


def _time_blocks(actual: Mapping[str, Any]) -> dict[str, Any]:
    entries = actual.get("entries")
    result: dict[str, Any] = {}
    if isinstance(entries, list):
        for entry in entries:
            if not isinstance(entry, Mapping) or not isinstance(entry.get("id"), str):
                continue
            time = entry.get("time") if isinstance(entry.get("time"), Mapping) else {}
            result[entry["id"]] = {
                "hour": time.get("hour"),
                "minute": time.get("minute"),
                "durationMinutes": entry.get("durationMinutes"),
            }
    return result


def _explanation_codes(actual: Mapping[str, Any]) -> list[Any]:
    codes: list[Any] = []
    for key in ("entries", "issues"):
        raw = actual.get(key)
        if not isinstance(raw, list):
            continue
        for item in raw:
            if isinstance(item, Mapping) and isinstance(item.get("explanationCodes"), list):
                codes.extend(item["explanationCodes"])
    return codes


def _review(fixture: Mapping[str, Any]) -> tuple[str, str]:
    review = fixture.get("review")
    if isinstance(review, Mapping):
        classification = review.get("classification")
        reason = review.get("reason")
        if isinstance(classification, str) and classification in REVIEW_CLASSES:
            return classification, str(reason or "")
    return "pending_a_review", "missing or invalid fixture review classification"


def _flatten_differences(expected: Any, actual: Any, path: str = "") -> list[tuple[str, Any, Any]]:
    if isinstance(expected, Mapping) and isinstance(actual, Mapping):
        keys = sorted(set(expected) | set(actual), key=str)
        differences: list[tuple[str, Any, Any]] = []
        for key in keys:
            child = f"{path}.{key}" if path else str(key)
            differences.extend(_flatten_differences(expected.get(key), actual.get(key), child))
        return differences
    if isinstance(expected, list) and isinstance(actual, list):
        differences = []
        if len(expected) != len(actual):
            differences.append((f"{path}.length", len(expected), len(actual)))
        for index in range(min(len(expected), len(actual))):
            differences.extend(_flatten_differences(expected[index], actual[index], f"{path}[{index}]"))
        return differences
    if expected != actual:
        return [(path, expected, actual)]
    return []


def _flatten_subset_differences(
    expected: Any,
    actual: Any,
    path: str = "",
) -> list[tuple[str, Any, Any]]:
    """Compare only declared assertion keys, matching the Dart runner.

    Transaction/boundary vectors intentionally assert state invariants rather
    than every diagnostic field.  Extra observed fields such as deterministic
    ``entryIds`` are useful in the report but must not fail a valid subset
    assertion.
    """

    if isinstance(expected, Mapping):
        if not isinstance(actual, Mapping):
            return [(path, expected, actual)]
        differences: list[tuple[str, Any, Any]] = []
        for key in sorted(expected, key=str):
            child = f"{path}.{key}" if path else str(key)
            if key not in actual:
                differences.append((child, expected[key], None))
                continue
            differences.extend(_flatten_subset_differences(expected[key], actual[key], child))
        return differences
    if isinstance(expected, list):
        if not isinstance(actual, list):
            return [(path, expected, actual)]
        differences: list[tuple[str, Any, Any]] = []
        if len(expected) != len(actual):
            differences.append((f"{path}.length", len(expected), len(actual)))
        for index in range(min(len(expected), len(actual))):
            differences.extend(_flatten_subset_differences(expected[index], actual[index], f"{path}[{index}]"))
        return differences
    if expected != actual:
        return [(path, expected, actual)]
    return []


def _difference_records(
    *,
    runtime: str,
    expected: Any,
    actual: Any,
    classification: str,
    reason: str,
    prefix: str = "",
    subset: bool = False,
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    flatten = _flatten_subset_differences if subset else _flatten_differences
    for field_name, expected_value, actual_value in flatten(expected, actual, prefix):
        records.append(
            {
                "runtime": runtime,
                "field": field_name,
                "expected": expected_value,
                "actual": actual_value,
                "classification": classification,
                "reason": reason,
            }
        )
    return records


def compare_fixture(
    fixture: Mapping[str, Any],
    *,
    python_actual: Mapping[str, Any],
    dart_actual: Mapping[str, Any],
) -> list[dict[str, Any]]:
    """Compare observed canonical values, then compare each runtime to assertions."""

    classification, reason = _review(fixture)
    kind = str(fixture.get("kind") or "")
    python_projection = _projection(python_actual, kind)
    dart_projection = _projection(dart_actual, kind)
    differences = _difference_records(
        runtime="dart_vs_python",
        expected=python_projection,
        actual=dart_projection,
        classification=classification,
        reason=reason,
    )

    expected = _assertion_projection(fixture, kind)
    for runtime, actual in (("python_vs_assertions", python_actual), ("dart_vs_assertions", dart_actual)):
        observed = _actual_projection_for_assertions(actual, kind)
        differences.extend(
            _difference_records(
                runtime=runtime,
                expected=expected,
                actual=observed,
                classification=classification,
                reason=reason,
                subset=kind in {"transaction", "boundary"},
            )
        )
    return differences


def _invalid_difference(
    fixture: Mapping[str, Any],
    *,
    runtime: str,
    error: str,
) -> dict[str, Any]:
    classification, reason = _review(fixture)
    return {
        "runtime": runtime,
        "field": "runtime",
        "expected": "valid output",
        "actual": error,
        "classification": classification,
        "reason": reason,
    }


def _fixture_result_map(payload: Mapping[str, Any] | None) -> dict[str, Mapping[str, Any]]:
    values = payload.get("fixtures") if isinstance(payload, Mapping) else []
    result: dict[str, Mapping[str, Any]] = {}
    if isinstance(values, list):
        for value in values:
            if not isinstance(value, Mapping):
                continue
            key = value.get("id") or value.get("name")
            if isinstance(key, str):
                result[key] = value
    return result


def _markdown_report(report: Mapping[str, Any]) -> str:
    summary = report.get("summary") if isinstance(report.get("summary"), Mapping) else {}
    classifications = report.get("classificationCounts") if isinstance(report.get("classificationCounts"), Mapping) else {}
    lines = [
        "# Dart/Python 共享调度向量差异报告",
        "",
        "本报告由 Dart runner 和 Python runner 实际执行生成；不使用断言替代运行结果。",
        "",
        f"- 场景总数：{summary.get('total', 0)}",
        f"- matched：{summary.get('matched', 0)}",
        f"- mismatched：{summary.get('mismatched', 0)}",
        f"- invalid：{summary.get('invalid', 0)}",
        "",
        "## A 分类统计",
        "",
    ]
    for key in sorted(classifications):
        lines.append(f"- {key}：{classifications[key]}")
    lines.extend(["", "## 逐场景结果", ""])
    for result in report.get("results", []):
        if not isinstance(result, Mapping):
            continue
        status = result.get("status", "invalid")
        lines.append(f"### {result.get('name', result.get('id', 'unknown'))}：{status}")
        lines.append("")
        review = result.get("review") if isinstance(result.get("review"), Mapping) else {}
        lines.append(f"- A 分类：{review.get('classification', 'pending_a_review')}")
        lines.append(f"- 原因：{review.get('reason', '')}")
        differences = result.get("differences") if isinstance(result.get("differences"), list) else []
        if differences:
            lines.append("- 差异：")
            for difference in differences:
                if not isinstance(difference, Mapping):
                    continue
                lines.append(
                    "  - "
                    f"`{difference.get('runtime')}` `{difference.get('field')}`："
                    f"expected={json.dumps(difference.get('expected'), ensure_ascii=False, sort_keys=True)}；"
                    f"actual={json.dumps(difference.get('actual'), ensure_ascii=False, sort_keys=True)}；"
                    f"分类={difference.get('classification')}"
                )
        else:
            lines.append("- 差异：无")
        lines.append("")
    lines.extend(
        [
            "## 对齐门槛",
            "",
            "存在 `pending_a_review`、invalid、未分类差异或未获允许的差异时，不能宣称 Dart/Python 已一致；未对齐前不得单独修改某一端生产算法来消除报告。",
            "",
        ]
    )
    return "\n".join(lines)


def build_report(
    fixtures: Sequence[Mapping[str, Any]],
    python_results: Sequence[PythonFixtureResult],
    dart_result: DartRunResult,
) -> dict[str, Any]:
    dart_map = _fixture_result_map(dart_result.payload)
    python_map = {result.fixture_id or result.name: result for result in python_results}
    results: list[dict[str, Any]] = []
    classification_counts: dict[str, int] = {key: 0 for key in sorted(REVIEW_CLASSES)}
    matched = mismatched = invalid = 0

    for fixture in fixtures:
        name = str(fixture.get("_fixtureName") or fixture.get("id") or "<fixture>")
        fixture_id = fixture.get("id") if isinstance(fixture.get("id"), str) else None
        kind = fixture.get("kind") if isinstance(fixture.get("kind"), str) else None
        review_class, review_reason = _review(fixture)
        result: dict[str, Any] = {
            "name": name,
            "id": fixture_id,
            "kind": kind,
            "review": {"classification": review_class, "reason": review_reason},
            "differences": [],
        }
        python_item = python_map.get(fixture_id or name)
        dart_item = dart_map.get(fixture_id or name) or dart_map.get(name)
        if python_item is None or python_item.invalid:
            error = python_item.error if python_item else "missing Python output"
            result["status"] = "invalid"
            result["differences"] = [_invalid_difference(fixture, runtime="python", error=error)]
            invalid += 1
        elif dart_result.invalid:
            result["status"] = "invalid"
            result["differences"] = [_invalid_difference(fixture, runtime="dart", error=dart_result.error)]
            invalid += 1
        elif dart_item is None:
            result["status"] = "invalid"
            result["differences"] = [_invalid_difference(fixture, runtime="dart", error="missing Dart fixture output")]
            invalid += 1
        elif dart_item.get("status") == "invalid":
            result["status"] = "invalid"
            result["differences"] = [_invalid_difference(fixture, runtime="dart", error=str(dart_item.get("error") or "invalid Dart fixture output"))]
            invalid += 1
        else:
            dart_actual = dart_item.get("actual")
            if not isinstance(dart_actual, Mapping) or python_item.actual is None:
                result["status"] = "invalid"
                result["differences"] = [_invalid_difference(fixture, runtime="dart", error="Dart actual is missing or not an object")]
                invalid += 1
            else:
                differences = compare_fixture(
                    fixture,
                    python_actual=python_item.actual,
                    dart_actual=dart_actual,
                )
                result["status"] = "matched" if not differences else "mismatched"
                result["differences"] = differences
                result["pythonActual"] = python_item.actual
                result["dartActual"] = dart_actual
                result["pythonDiagnostics"] = python_item.diagnostics
                result["dartDiagnostics"] = dart_item.get("diagnostics", {})
                if differences:
                    mismatched += 1
                else:
                    matched += 1
        if result["differences"]:
            for difference in result["differences"]:
                classification = difference.get("classification")
                if classification in classification_counts:
                    classification_counts[classification] += 1
        results.append(result)

    summary = {"total": len(fixtures), "matched": matched, "mismatched": mismatched, "invalid": invalid}
    return {
        "schemaVersion": "scheduling/v1",
        "command": ["python", "scripts/scheduling_parity.py"],
        "summary": summary,
        "classificationCounts": classification_counts,
        "dart": {
            "returncode": dart_result.returncode,
            "invalid": dart_result.invalid,
            "error": dart_result.error,
            "stderr": dart_result.stderr,
        },
        "results": results,
    }


def _report_requires_failure(report: Mapping[str, Any]) -> bool:
    dart = report.get("dart") if isinstance(report.get("dart"), Mapping) else {}
    if dart.get("invalid"):
        return True
    summary = report.get("summary") if isinstance(report.get("summary"), Mapping) else {}
    if int(summary.get("invalid", 0) or 0) > 0:
        return True
    for result in report.get("results", []):
        if not isinstance(result, Mapping):
            continue
        for difference in result.get("differences", []):
            if not isinstance(difference, Mapping):
                continue
            if difference.get("classification") != "allowed_difference":
                return True
    return False


def write_reports(report: Mapping[str, Any], *, reports_dir: Path = REPORTS_DIR) -> None:
    reports_dir.mkdir(parents=True, exist_ok=True)
    json_path = reports_dir / "shared-vector-diff.json"
    markdown_path = reports_dir / "shared-vector-diff.md"
    json_path.write_text(
        json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    markdown_path.write_text(_markdown_report(report), encoding="utf-8")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Compare Dart/Python scheduling shared vectors")
    parser.add_argument("--fixtures-dir", type=Path, default=FIXTURES_DIR)
    parser.add_argument("--reports-dir", type=Path, default=REPORTS_DIR)
    args = parser.parse_args(argv)

    fixtures = load_fixtures(args.fixtures_dir)
    python_results = run_python_vectors(fixtures)
    dart_result = run_dart_runner(args.fixtures_dir)
    report = build_report(fixtures, python_results, dart_result)
    write_reports(report, reports_dir=args.reports_dir)
    summary = report["summary"]
    print(
        "共享向量比较完成："
        f"total={summary['total']} matched={summary['matched']} "
        f"mismatched={summary['mismatched']} invalid={summary['invalid']}"
    )
    if dart_result.stderr.strip():
        print("Dart stderr:")
        print(dart_result.stderr, end="" if dart_result.stderr.endswith("\n") else "\n")
    if _report_requires_failure(report):
        print("存在未获允许的差异、invalid 输出或待 A 审查项；不能宣称双端一致。", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
