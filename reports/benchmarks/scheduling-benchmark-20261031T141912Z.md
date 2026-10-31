# Scheduling benchmark

- status: completed
- parity gate: passed
- gate reasons: none

普通 issues 仅作为结果计数，不计入 degradation。

## Plan/Rescue timing

| operation | taskCount | samples | p50Ms | p95Ms | p99Ms | timeouts | failures | degraded |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| plan | 10 | 10 | 1.197 | 1.432 | 1.441 | 0 | 0 | 0 |
| rescue | 10 | 10 | 5.483 | 6.463 | 6.801 | 0 | 0 | 0 |
| plan | 50 | 10 | 3.641 | 3.976 | 3.992 | 0 | 0 | 0 |
| rescue | 50 | 10 | 14.466 | 15.566 | 15.755 | 0 | 0 | 0 |
| plan | 100 | 10 | None | None | None | 10 | 0 | 0 |
| rescue | 100 | 10 | 24.53 | 27.511 | 28.637 | 0 | 0 | 0 |
| plan | 200 | 10 | None | None | None | 10 | 0 | 0 |
| rescue | 200 | 10 | 47.977 | 53.818 | 55.471 | 0 | 0 | 0 |

## Process memory

RSS is the OS process lifetime high-water mark, including interpreter/imports. It is not an incremental allocation measurement. Thread samples share the caller process. Missing counters stay null.

| operation | taskCount | peakRssBytes | rssSource | rssScope | rssSamples | peakMemoryBytes |
|---|---:|---:|---|---|---:|---:|
| plan | 10 | 36929536 | psutil.peak_wset | worker_process_lifetime | 10 | 19780 |
| rescue | 10 | 37040128 | psutil.peak_wset | worker_process_lifetime | 10 | 46187 |
| plan | 50 | 36933632 | psutil.peak_wset | worker_process_lifetime | 10 | 53661 |
| rescue | 50 | 37154816 | psutil.peak_wset | worker_process_lifetime | 10 | 95650 |
| plan | 100 | None | unavailable | unavailable | 0 | None |
| rescue | 100 | 37285888 | psutil.peak_wset | worker_process_lifetime | 10 | 161566 |
| plan | 200 | None | unavailable | unavailable | 0 | None |
| rescue | 200 | 37658624 | psutil.peak_wset | worker_process_lifetime | 10 | 290649 |

## Strategies

| taskCount | strategy | samples | successful | timeouts | failures | degraded | avgEntryCount | avgIssueCount | avgHardIssueCount | avgMovedEntryCount | avgRecoveryMinutes | recommended |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10 | protectDeadline | 10 | 10 | 0 | 0 | 0 | 9.0 | 10.0 | 3.0 | 0.0 | 0.0 | 0 |
| 10 | protectRecovery | 10 | 10 | 0 | 0 | 0 | 9.0 | 10.0 | 3.0 | 0.0 | 0.0 | 0 |
| 10 | minimizeChanges | 10 | 10 | 0 | 0 | 0 | 9.0 | 10.0 | 3.0 | 0.0 | 0.0 | 10 |
| 50 | protectDeadline | 10 | 10 | 0 | 0 | 0 | 9.0 | 49.0 | 43.0 | 0.0 | 0.0 | 0 |
| 50 | protectRecovery | 10 | 10 | 0 | 0 | 0 | 9.0 | 50.0 | 44.0 | 0.0 | 15.0 | 0 |
| 50 | minimizeChanges | 10 | 10 | 0 | 0 | 0 | 9.0 | 49.0 | 43.0 | 0.0 | 0.0 | 10 |
| 100 | protectDeadline | 10 | 10 | 0 | 0 | 0 | 7.0 | 100.0 | 95.0 | 0.0 | 0.0 | 0 |
| 100 | protectRecovery | 10 | 10 | 0 | 0 | 0 | 8.0 | 100.0 | 95.0 | 0.0 | 15.0 | 10 |
| 100 | minimizeChanges | 10 | 10 | 0 | 0 | 0 | 7.0 | 100.0 | 95.0 | 0.0 | 0.0 | 0 |
| 200 | protectDeadline | 10 | 10 | 0 | 0 | 0 | 8.0 | 200.0 | 194.0 | 0.0 | 0.0 | 0 |
| 200 | protectRecovery | 10 | 10 | 0 | 0 | 0 | 9.0 | 200.0 | 193.0 | 0.0 | 0.0 | 10 |
| 200 | minimizeChanges | 10 | 10 | 0 | 0 | 0 | 8.0 | 200.0 | 194.0 | 0.0 | 0.0 | 0 |

## Errors

- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 100, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
- {"error": "timeout", "message": "timeout", "operation": "plan", "status": "timeout", "taskCount": 200, "type": "Timeout"}
