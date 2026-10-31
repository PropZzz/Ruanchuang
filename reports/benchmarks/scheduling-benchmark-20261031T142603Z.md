# Scheduling benchmark

- status: completed
- parity gate: passed
- gate reasons: none

普通 issues 仅作为结果计数，不计入 degradation。

## Plan/Rescue timing

| operation | taskCount | samples | p50Ms | p95Ms | p99Ms | timeouts | failures | degraded |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| plan | 10 | 10 | 1.227 | 1.806 | 1.921 | 0 | 0 | 0 |
| rescue | 10 | 10 | 6.127 | 6.536 | 6.558 | 0 | 0 | 0 |
| plan | 50 | 10 | 4.002 | 4.204 | 4.22 | 0 | 0 | 0 |
| rescue | 50 | 10 | 15.792 | 16.955 | 17.212 | 0 | 0 | 0 |
| plan | 100 | 10 | 6.537 | 7.648 | 8.082 | 0 | 0 | 0 |
| rescue | 100 | 10 | 25.835 | 30.44 | 31.074 | 0 | 0 | 0 |
| plan | 200 | 10 | 13.291 | 15.204 | 15.739 | 0 | 0 | 0 |
| rescue | 200 | 10 | 49.084 | 51.58 | 51.922 | 0 | 0 | 0 |

## Process memory

RSS is the OS process lifetime high-water mark, including interpreter/imports. It is not an incremental allocation measurement. Thread samples share the caller process. Missing counters stay null.

| operation | taskCount | peakRssBytes | rssSource | rssScope | rssSamples | peakMemoryBytes |
|---|---:|---:|---|---|---:|---:|
| plan | 10 | 36909056 | psutil.peak_wset | worker_process_lifetime | 10 | 19780 |
| rescue | 10 | 36982784 | psutil.peak_wset | worker_process_lifetime | 10 | 46187 |
| plan | 50 | 36925440 | psutil.peak_wset | worker_process_lifetime | 10 | 53661 |
| rescue | 50 | 37142528 | psutil.peak_wset | worker_process_lifetime | 10 | 95650 |
| plan | 100 | 37109760 | psutil.peak_wset | worker_process_lifetime | 10 | 103863 |
| rescue | 100 | 37244928 | psutil.peak_wset | worker_process_lifetime | 10 | 161566 |
| plan | 200 | 37462016 | psutil.peak_wset | worker_process_lifetime | 10 | 195901 |
| rescue | 200 | 37720064 | psutil.peak_wset | worker_process_lifetime | 10 | 290649 |

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
