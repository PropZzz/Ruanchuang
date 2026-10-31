# Scheduling benchmark

- status: completed
- parity gate: passed
- gate reasons: none

普通 issues 仅作为结果计数，不计入 degradation。

## Plan/Rescue timing

| operation | taskCount | samples | p50Ms | p95Ms | p99Ms | timeouts | failures | degraded |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| plan | 10 | 10 | 1.119 | 1.278 | 1.313 | 0 | 0 | 0 |
| rescue | 10 | 10 | 5.253 | 5.867 | 5.873 | 0 | 0 | 0 |
| plan | 50 | 10 | 3.134 | 4.454 | 4.734 | 0 | 0 | 0 |
| rescue | 50 | 10 | 13.051 | 14.798 | 15.104 | 0 | 0 | 0 |
| plan | 100 | 10 | 5.818 | 6.812 | 7.148 | 0 | 0 | 0 |
| rescue | 100 | 10 | 20.935 | 23.815 | 24.298 | 0 | 0 | 0 |
| plan | 200 | 10 | 11.058 | 14.511 | 14.597 | 0 | 0 | 0 |
| rescue | 200 | 10 | 39.858 | 41.854 | 41.906 | 0 | 0 | 0 |

## Process memory

RSS is the OS process lifetime high-water mark, including interpreter/imports. It is not an incremental allocation measurement. Thread samples share the caller process. Missing counters stay null.

| operation | taskCount | peakRssBytes | rssSource | rssScope | rssSamples | peakMemoryBytes |
|---|---:|---:|---|---|---:|---:|
| plan | 10 | 36831232 | psutil.peak_wset | worker_process_lifetime | 10 | 19780 |
| rescue | 10 | 37027840 | psutil.peak_wset | worker_process_lifetime | 10 | 46187 |
| plan | 50 | 36941824 | psutil.peak_wset | worker_process_lifetime | 10 | 53661 |
| rescue | 50 | 36986880 | psutil.peak_wset | worker_process_lifetime | 10 | 95650 |
| plan | 100 | 37089280 | psutil.peak_wset | worker_process_lifetime | 10 | 103863 |
| rescue | 100 | 37273600 | psutil.peak_wset | worker_process_lifetime | 10 | 161566 |
| plan | 200 | 37343232 | psutil.peak_wset | worker_process_lifetime | 10 | 195901 |
| rescue | 200 | 37724160 | psutil.peak_wset | worker_process_lifetime | 10 | 290649 |

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

- none
