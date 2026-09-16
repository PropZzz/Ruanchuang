# Scheduling benchmark

- status: blocked
- parity gate: blocked
- gate reasons: mismatched

普通 issues 仅作为结果计数，不计入 degradation。

## Plan/Rescue timing

| operation | taskCount | samples | p50Ms | p95Ms | p99Ms | timeouts | failures | degraded |
|---|---:|---:|---:|---:|---:|---:|---:|---:|

## Strategies

| taskCount | strategy | samples | successful | timeouts | failures | degraded | avgEntryCount | avgIssueCount | avgHardIssueCount | avgMovedEntryCount | avgRecoveryMinutes | recommended |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|

## Errors

- {"reason": "mismatched", "type": "parity_gate"}
