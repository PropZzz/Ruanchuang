# 调度基准与性能证据 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在共享 parity 通过后提供可重复的 Python 调度基准，记录任务规模、规划/救援耗时、超时、失败、降级和三策略结果，并在当前 parity 未通过时生成明确的阻断报告。

**Architecture:** `scripts/scheduling_benchmark.py` 是纯 Python CLI 和可注入的基准库。它读取 parity 机器报告作为门禁，使用固定种子生成单日任务夹具；对可 pickle 的调用优先使用可终止的独立 process 隔离，对不可 pickle 的调用回退到 thread，并在超时结果中标记 `timeoutUncancellable`。基准使用标准库计时/内存采样聚合结果，输出一次性 JSON/Markdown 报告。生产调度核心和 Dart/Python parity runner 不变。

**Tech Stack:** Python 3.10、标准库 `argparse`/`dataclasses`/`random`/`multiprocessing`/`pickle`/`threading`/`tracemalloc`/`time`/`json`、pytest 9.1。

---

### Task 1: 建立基准纯函数契约测试

**Files:**
- Create: `backend/tests/test_scheduling_benchmark.py`
- Test target: `scripts/scheduling_benchmark.py`（此任务只写测试，不创建实现文件）

- [ ] **Step 1: Write the failing tests**

```python
def test_percentile_uses_linear_interpolation():
    assert percentile([10.0, 20.0, 30.0, 40.0], 0.95) == 38.5


def test_workload_generation_is_deterministic_and_has_requested_count():
    first = build_workload(7, seed=123)
    second = build_workload(7, seed=123)
    assert first == second
    assert len(first["tasks"]) == 7


def test_parity_gate_blocks_mismatch_and_pending_report():
    gate = evaluate_parity_gate(
        {"summary": {"total": 2, "matched": 1, "mismatched": 1, "invalid": 0},
         "dart": {"invalid": False},
         "classificationCounts": {"pending_a_review": 1}}
    )
    assert gate["status"] == "blocked"
    assert "mismatched" in gate["reasons"]
    assert "pending_a_review" in gate["reasons"]


def test_summarize_samples_reports_percentiles_and_counts():
    summary = summarize_samples([
        {"status": "success", "durationMs": 10.0},
        {"status": "timeout", "durationMs": 20.0},
        {"status": "failure", "durationMs": 30.0},
        {"status": "degraded", "durationMs": 40.0},
    ])
    assert summary["sampleCount"] == 4
    assert summary["timeoutCount"] == 1
    assert summary["failureCount"] == 1
    assert summary["degradedCount"] == 1
    assert summary["p50Ms"] == 25.0


def test_timeout_and_runner_exception_are_distinct():
    timed_out = measure_call(lambda: time.sleep(0.05), timeoutMs=1)
    failed = measure_call(lambda: (_ for _ in ()).throw(ValueError("bad")), timeoutMs=50)
    assert timed_out["status"] == "timeout"
    assert failed["status"] == "failure"
    assert failed["errorType"] == "ValueError"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python -m pytest backend/tests/test_scheduling_benchmark.py -q`

Expected: collection fails with `ModuleNotFoundError` for `scripts.scheduling_benchmark`, proving the new contract is not already implemented.

- [ ] **Step 3: Commit the red tests**

```bash
git add backend/tests/test_scheduling_benchmark.py
git commit -m "test: define scheduling benchmark contracts"
```

### Task 2: Implement deterministic inputs, gate, timing and aggregation

**Files:**
- Create: `scripts/scheduling_benchmark.py`
- Modify: `backend/tests/test_scheduling_benchmark.py` only when an assertion exposes an incorrect test setup

- [ ] **Step 1: Implement the minimal public API**

Add these exact public functions and behavior:

```python
def percentile(samples: Sequence[float], quantile: float) -> float:
    """Return a linear-interpolated percentile for non-empty finite samples."""

def build_workload(task_count: int, *, seed: int) -> dict[str, Any]:
    """Return deterministic day/tasks/windows/fixed/urgent/currentEntries input."""

def evaluate_parity_gate(report: Mapping[str, Any]) -> dict[str, Any]:
    """Return {'status': 'passed'|'blocked', 'reasons': list[str], 'summary': dict}."""

def measure_call(call: Callable[[], Any], *, timeoutMs: int,
                 clock: Callable[[], float] = time.perf_counter) -> dict[str, Any]:
    """Use a killable process for pickleable calls, else thread fallback."""

def summarize_samples(samples: Sequence[Mapping[str, Any]]) -> dict[str, Any]:
    """Aggregate counts, P50/P95/P99, min/max and successful durations."""
```

`percentile` rejects an empty sequence and quantiles outside `[0, 1]`; it sorts a copy and interpolates `(n - 1) * q`. `build_workload` validates `task_count >= 1`, uses `random.Random(seed)`, stable ids (`task-0000` etc.), two legal windows (`08:00-12:00`, `13:00-18:00`), deterministic fixed entries and a due-dated urgent task. It must return the same JSON-compatible value for the same inputs.

`measure_call` records `durationMs`, `status`, `timeoutMs`, and an exception type/message for failures. It first checks whether the callable can be serialized with pickle and, when so, runs it in a separate process that can be terminated after `timeoutMs`; otherwise it uses a daemon thread fallback. A process timeout returns immediately with `status: timeout`; a thread fallback also returns immediately but marks `timeoutUncancellable: true` because the running call cannot be forcibly stopped. Neither timeout is counted as successful. A normal scheduling response containing `degraded: true` or `fallback: true` is classified as `degraded`; ordinary plan issues are not degradation.

`summarize_samples` counts `success`, `timeout`, `failure`, and `degraded`, computes P50/P95/P99 plus min/max from successful and degraded non-timeout durations, and reports `sampleCount` and `successfulSampleCount`. All duration values are rounded to three decimal milliseconds. `peakMemoryBytes` is the `tracemalloc` estimate of Python allocation growth during the call; `peakRssBytes` remains `null`/uncollected, with `rssSource: "unavailable"` (or `"parentPeakMemoryBytes"` only when explicitly derived from a parent-process memory value).

- [ ] **Step 2: Run the focused tests to verify they pass**

Run: `python -m pytest backend/tests/test_scheduling_benchmark.py -q`

Expected: all focused tests pass with no warnings.

- [ ] **Step 3: Commit the implementation unit**

```bash
git add scripts/scheduling_benchmark.py backend/tests/test_scheduling_benchmark.py
git commit -m "feat: add scheduling benchmark primitives"
```

### Task 3: Add plan/rescue matrix execution and reports

**Files:**
- Modify: `scripts/scheduling_benchmark.py`
- Modify: `backend/tests/test_scheduling_benchmark.py`

- [ ] **Step 1: Write failing matrix/report tests**

Add tests that inject `plan_runner`, `rescue_runner`, a temporary parity report, and `output_dir`:

```python
def test_run_benchmark_records_three_strategy_results_and_errors(tmp_path):
    report = run_benchmark(
        task_counts=(3,), warmups=0, samples=2, seed=7, timeoutMs=100,
        parity_report={"summary": {"total": 1, "matched": 1, "mismatched": 0, "invalid": 0},
                       "dart": {"invalid": False}, "classificationCounts": {}},
        plan_runner=lambda request: {"entries": [], "issues": []},
        rescue_runner=lambda request: {"options": [
            {"strategy": name, "plannedEntries": [], "issueCount": 0,
             "hardIssueCount": 0, "movedEntryCount": 0, "recoveryMinutes": 0,
             "recommended": name == "protectDeadline"}
            for name in ("protectDeadline", "protectRecovery", "minimizeChanges")
        ]},
    )
    assert report["status"] == "completed"
    assert {item["strategy"] for item in report["strategies"]} == {
        "protectDeadline", "protectRecovery", "minimizeChanges"
    }
    assert report["runs"]
    assert report["errors"] == []


def test_blocked_benchmark_writes_no_measurements(tmp_path):
    path = write_benchmark_report(
        {"status": "blocked", "runs": [], "strategies": [], "errors": []},
        tmp_path,
    )
    payload = json.loads(path.read_text(encoding="utf-8"))
    assert payload["status"] == "blocked"
    assert payload["runs"] == []
```

- [ ] **Step 2: Run the matrix tests to verify they fail**

Run: `python -m pytest backend/tests/test_scheduling_benchmark.py -q`

Expected: failures report missing `run_benchmark` or `write_benchmark_report`.

- [ ] **Step 3: Implement matrix execution**

Add `run_benchmark(...)` with injectable `plan_runner`, `rescue_runner`, `clock`, and an already loaded parity mapping. For each requested task count, generate one workload, run `warmups` without recording, then run `samples` for the plan operation and the rescue operation. Measure each call with `timeoutMs`; append one `runs` row per runtime/operation/task count with `runtime: "python"`, task count, sample configuration and `summarize_samples` fields. Use `tracemalloc.reset_peak()` around the matrix and record its Python allocation increment as `peakMemoryBytes`. Keep `peakRssBytes: null` with `rssSource: "unavailable"`; if a future implementation explicitly derives a parent-process value, use `rssSource: "parentPeakMemoryBytes"` and do not label it as current-process RSS.

For each rescue response, look up all three fixed strategy names. Record one strategy row per task count/name with success, failure, timeout and degraded counts, plus averages/min/max for `entryCount`, `issueCount`, `hardIssueCount`, `movedEntryCount`, `recoveryMinutes`, and `recommendedCount`. Missing options and malformed responses become structured `errors` and failures; one bad sample does not stop other samples. Ordinary scheduling issues remain result metrics, not execution failures or degradation.

Set `status: "completed"` when the gate passed and at least one sample completed; set `status: "failed"` when the gate passed but no sample completed. Include `schemaVersion: "scheduling-benchmark/v1"`, UTC timestamps, seed, task counts, warmups, samples, timeout budget, command, gate, runs, strategies and errors.

- [ ] **Step 4: Implement report writers and CLI**

Add:

```python
def write_benchmark_report(report: Mapping[str, Any], output_dir: Path) -> Path:
    """Write a unique UTC-stamped JSON and Markdown pair and return JSON path."""

def main(argv: Sequence[str] | None = None) -> int:
    """Parse CLI, load parity report, gate, run matrix, write report and return status."""
```

CLI defaults: `--parity-report reports/shared-vector-diff.json`, `--output-dir reports/benchmarks`, `--task-count 10 --task-count 50 --task-count 100 --task-count 200`, `--warmups 2`, `--samples 10`, `--seed 20260916`, `--timeout-ms 1000`. Add `--refresh-parity` to run `python scripts/scheduling_parity.py` before reading the report; without it, a missing/invalid report is a blocked gate rather than an implicit pass. A blocked gate writes an empty report with `status: blocked`, `gate.reasons`, and no measurement rows. Return `0` only for completed runs with zero execution failures; return `2` for blocked and `1` for completed-but-failed measurements.

The Markdown writer must include the gate status/reasons, one table for plan/rescue latency (task count, P50/P95/P99, timeout/failure/degraded), one table for the three strategies, and a complete error list. It must state that an ordinary `issues` count is not a degradation.

- [ ] **Step 5: Run focused tests and inspect generated shape**

Run: `python -m pytest backend/tests/test_scheduling_benchmark.py -q`

Expected: all tests pass, and the temporary report contains `gate`, `runs`, `strategies`, `errors`, P50/P95/P99, timeout/failure/degraded counts and a stable seed.

- [ ] **Step 6: Commit the matrix and report unit**

```bash
git add scripts/scheduling_benchmark.py backend/tests/test_scheduling_benchmark.py
git commit -m "feat: record scheduling benchmark matrix"
```

### Task 4: Document the evidence workflow and run real verification

**Files:**
- Modify: `README.md`
- Modify: `contracts/scheduling/v1/README.md`
- Create: `reports/benchmarks/.gitkeep`

- [ ] **Step 1: Document the two-command gate and report fields**

Add a Chinese section to `README.md` with these commands:

```powershell
python scripts/scheduling_parity.py
python scripts/scheduling_benchmark.py --parity-report reports/shared-vector-diff.json
```

Explain that the current parity result must have zero mismatch/invalid/pending before a completed benchmark is valid; otherwise the second command writes a blocked report. Document default scales, seed, warmups/samples, timeout budget, report directory, P50/P95/P99, peak-memory source, strategy metrics, failure and degradation semantics, and the rule that no Go/Rust/C++ rewrite is justified by a blocked or incomplete report.

- [ ] **Step 2: Run the full Python verification**

Run: `python -m pytest backend/tests -q`

Expected: all existing backend tests and benchmark tests pass. If the environment reports pre-existing dependency warnings, record their exact count without changing unrelated code.

- [ ] **Step 3: Generate the current blocked evidence report**

Run: `python scripts/scheduling_benchmark.py --parity-report reports/shared-vector-diff.json --output-dir reports/benchmarks`

Expected: exit code `2`, a new timestamped JSON/Markdown pair, `status: blocked`, reasons containing `mismatched`, `summary.mismatched == 9`, and empty `runs`/`strategies`. Do not label it as performance data.

- [ ] **Step 4: Run repository checks**

Run: `git diff --check`

Expected: no output. Run `flutter analyze` only if Flutter is installed; retain its exit code/output in the handoff when unavailable or when existing unrelated diagnostics prevent a clean run.

- [ ] **Step 5: Commit docs and evidence scaffolding**

```bash
git add README.md contracts/scheduling/v1/README.md reports/benchmarks/.gitkeep
git commit -m "docs: publish scheduling benchmark workflow"
```

- [ ] **Step 6: Push and report the remote revision**

Run: `git push origin main`

Expected: `main` updates `origin/main`; report the pushed commit SHA and the blocked parity evidence honestly in the final Chinese summary.
