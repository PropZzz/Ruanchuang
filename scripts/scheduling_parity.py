from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from backend.scheduling.core import SchedulerCore
from backend.scheduling_contract import SchedulingRequest, to_contract_response


BEGIN_MARKER = "SCHEDULING_PARITY_RESULT_BEGIN"
END_MARKER = "SCHEDULING_PARITY_RESULT_END"


class ParityRunnerError(RuntimeError):
    pass


def load_fixtures(root: Path) -> list[tuple[str, dict[str, Any]]]:
    directory = root / "contracts" / "scheduling" / "v1" / "fixtures"
    fixtures: list[tuple[str, dict[str, Any]]] = []
    for path in sorted(directory.glob("*.json"), key=lambda item: item.name):
        fixtures.append((path.name, json.loads(path.read_text(encoding="utf-8"))))
    if not fixtures:
        raise ParityRunnerError(f"no scheduling fixtures found in {directory}")
    return fixtures


def run_python_fixture(fixture: dict[str, Any]) -> dict[str, Any]:
    request = SchedulingRequest.model_validate(fixture["request"])
    result = SchedulerCore().plan(request.to_engine_request())
    return to_contract_response(result, request).model_dump(
        mode="json",
        by_alias=True,
        exclude_none=True,
    )


def parse_runner_output(stdout: str) -> dict[str, Any]:
    begin_count = stdout.count(BEGIN_MARKER)
    end_count = stdout.count(END_MARKER)
    if begin_count != 1 or end_count != 1:
        raise ParityRunnerError(
            f"runner markers must occur once (begin={begin_count}, end={end_count})"
        )
    start = stdout.index(BEGIN_MARKER) + len(BEGIN_MARKER)
    end = stdout.index(END_MARKER, start)
    payload_text = stdout[start:end]
    first_object = payload_text.find("{")
    last_object = payload_text.rfind("}")
    if first_object < 0 or last_object <= first_object:
        raise ParityRunnerError("runner marker payload is not a JSON object")
    try:
        payload = json.loads(payload_text[first_object : last_object + 1])
    except json.JSONDecodeError as exc:
        raise ParityRunnerError("runner marker payload is malformed JSON") from exc
    if not isinstance(payload, dict) or not isinstance(payload.get("fixtures"), list):
        raise ParityRunnerError("runner payload must contain a fixtures array")
    return payload


def run_dart_runner(root: Path) -> dict[str, Any]:
    environment = os.environ.copy()
    environment["SCHEDULING_FIXTURES_DIR"] = str(
        root / "contracts" / "scheduling" / "v1" / "fixtures"
    )
    flutter = shutil.which("flutter.bat") or shutil.which("flutter") or "flutter.bat"
    process = subprocess.run(
        [flutter, "test", "test/scheduling_fixture_runner_test.dart", "-r", "compact"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
        env=environment,
    )
    combined = f"{process.stdout}\n{process.stderr}"
    payload = parse_runner_output(combined)
    payload["processExitCode"] = process.returncode
    return payload


def _differences(expected: Any, actual: Any, path: str = "") -> list[dict[str, Any]]:
    if isinstance(expected, dict) and isinstance(actual, dict):
        differences: list[dict[str, Any]] = []
        for key in sorted(set(expected) | set(actual)):
            if key == "message":
                continue
            child_path = f"{path}.{key}" if path else key
            differences.extend(_differences(expected.get(key), actual.get(key), child_path))
        return differences
    if isinstance(expected, list) and isinstance(actual, list):
        differences = []
        if len(expected) != len(actual):
            differences.append(
                {"field": f"{path}.length", "expected": len(expected), "actual": len(actual)}
            )
        for index in range(min(len(expected), len(actual))):
            differences.extend(_differences(expected[index], actual[index], f"{path}[{index}]"))
        return differences
    if expected != actual:
        return [{"field": path, "expected": expected, "actual": actual}]
    return []


def compare_results(
    expected: dict[str, Any],
    python_result: dict[str, Any],
    dart_result: dict[str, Any],
) -> dict[str, Any]:
    differences: list[dict[str, Any]] = []
    for runtime, result in (("python", python_result), ("dart", dart_result)):
        for difference in _differences(expected, result):
            difference["runtime"] = runtime
            differences.append(difference)
    return {"status": "matched" if not differences else "mismatched", "differences": differences}


def write_report(report: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    root = ROOT
    report_path = root / "reports" / "scheduling-parity-2026-09-14.json"
    try:
        fixtures = load_fixtures(root)
        dart_payload = run_dart_runner(root)
        dart_results = {
            item.get("name"): item
            for item in dart_payload["fixtures"]
            if isinstance(item, dict) and isinstance(item.get("name"), str)
        }
    except Exception as exc:
        report = {
            "schemaVersion": "1",
            "summary": {"fixtures": 0, "matched": 0, "mismatched": 0, "invalid": 1},
            "fixtures": [],
            "error": str(exc),
        }
        write_report(report, report_path)
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 1

    records: list[dict[str, Any]] = []
    for name, fixture in fixtures:
        dart_item = dart_results.get(name)
        try:
            python_result = run_python_fixture(fixture)
            if not isinstance(dart_item, dict) or dart_item.get("status") == "invalid":
                raise ParityRunnerError("Dart runner did not produce a valid fixture result")
            dart_result = dart_item.get("actual")
            if not isinstance(dart_result, dict):
                raise ParityRunnerError("Dart fixture result has no canonical actual response")
            comparison = compare_results(fixture["response"], python_result, dart_result)
            records.append(
                {
                    "name": name,
                    "status": comparison["status"],
                    "differences": comparison["differences"],
                    "python": python_result,
                    "dart": dart_result,
                }
            )
        except Exception as exc:
            records.append({"name": name, "status": "invalid", "error": str(exc)})

    summary = {
        "fixtures": len(records),
        "matched": sum(record["status"] == "matched" for record in records),
        "mismatched": sum(record["status"] == "mismatched" for record in records),
        "invalid": sum(record["status"] == "invalid" for record in records),
    }
    report = {"schemaVersion": "1", "summary": summary, "fixtures": records}
    write_report(report, report_path)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if summary["mismatched"] == 0 and summary["invalid"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
