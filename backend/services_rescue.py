"""Rescue service layer: pure computation for the remote schedule-rescue flow.

No network access and no database side effects live here. The three rescue
strategies mirror the Flutter client's `ScheduleRescueService.propose`
(lib/services/scheduling/schedule_rescue.dart) by composing the same inputs
into the existing `plan_schedule` engine, so Dart and Python stay consistent
until the SchedulerCore convergence work (P1 items 1-3) lands.
"""

from __future__ import annotations

from datetime import date, datetime
import hashlib
import json
from typing import Any

from .schemas import ENERGY_TIERS, RESCUE_STRATEGIES
from .services_scheduling import plan_schedule


RESCUE_TITLES = {
    "protectDeadline": "优先保住截止时间",
    "protectRecovery": "优先保留恢复时间",
    "minimizeChanges": "尽量少动原计划",
}

RESCUE_RATIONALES = {
    "protectDeadline": "先安排紧急事项，再重新分配其余任务，优先降低逾期风险。",
    "protectRecovery": "降低高负荷任务的安排倾向，并预留 15 分钟恢复缓冲。",
    "minimizeChanges": "锁定当前已排日程，只在现有空档中放入紧急事项。",
}

RESCUE_TRADEOFFS = {
    "protectDeadline": "可能移动更多原有任务，恢复时间取决于当前能量状态。",
    "protectRecovery": "部分低优先级任务可能顺延，适合疲劳或连续被打断的场景。",
    "minimizeChanges": "如果空档不足，紧急事项可能无法在截止时间前安排。",
}

RECOVERY_BUFFER_COLOR = 0xFF80CBC4
RECOVERY_BUFFER_MINUTES = 15
RECOVERY_BUFFER_HEIGHT = 20.0


def _iso_day(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return None
        return text.split("T", 1)[0]
    return None


def compute_baseline_hash(entries: list[dict[str, Any]], day_iso: str) -> str:
    """Deterministic SHA-256 of the canonical form of a day's schedule entries.

    Rules (keep stable, documented in docs/接口预留与服务器接口文档.md):
    - Only entries whose normalized `day` equals `day_iso` are hashed (inbox
      entries with `day=None` and entries of other days are excluded).
    - Each entry is reduced to the same 13 fields emitted by
      `_schedule_row_to_dict` / `ScheduleEntryIn.model_dump`; `height` is
      rounded to 2 decimals to absorb float noise; entries are sorted by `id`.
    - The result is independent of key order, so client-echoed payloads and
      database rows hash identically.
    """
    canonical: list[dict[str, Any]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if _iso_day(entry.get("day")) != day_iso:
            continue
        time_value = entry.get("time")
        hour = 0
        minute = 0
        if isinstance(time_value, dict):
            hour = int(time_value.get("hour") or 0)
            minute = int(time_value.get("minute") or 0)
        try:
            height = round(float(entry.get("height") or 0.0), 2)
        except (TypeError, ValueError):
            height = 0.0
        try:
            color = int(entry.get("color") or 0)
        except (TypeError, ValueError):
            color = 0
        try:
            reminder = int(entry.get("reminderMinutesBefore") or 10)
        except (TypeError, ValueError):
            reminder = 10
        canonical.append(
            {
                "id": str(entry.get("id") or ""),
                "day": day_iso,
                "title": str(entry.get("title") or ""),
                "tag": str(entry.get("tag") or ""),
                "load": entry.get("load"),
                "goalId": entry.get("goalId"),
                "goalTaskId": entry.get("goalTaskId"),
                "height": height,
                "color": color,
                "time": {"hour": hour, "minute": minute},
                "reminderMinutesBefore": reminder,
                "repeat": str(entry.get("repeat") or "none"),
                "repeatUntil": _iso_day(entry.get("repeatUntil")),
            }
        )
    canonical.sort(key=lambda item: item["id"])
    payload = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _lower_energy(energy: str) -> str:
    if energy not in ENERGY_TIERS:
        return "medium"
    return ENERGY_TIERS[max(0, ENERGY_TIERS.index(energy) - 1)]


def _recovery_buffer(day_iso: str, windows: list[dict[str, Any]]) -> dict[str, Any]:
    """Synthetic 15-minute recovery block, mirroring Dart `_recoveryBuffer`.

    Placed at the start of the first window beginning at/after 12:00, else at
    the first window's start, else at 15:00 when there are no windows.
    """
    preferred: dict[str, Any] | None = None
    for window in windows:
        if not isinstance(window, dict):
            continue
        start = window.get("start")
        if isinstance(start, dict) and int(start.get("hour") or 0) >= 12:
            preferred = start
            break
    if preferred is None and windows:
        first_start = windows[0].get("start")
        if isinstance(first_start, dict):
            preferred = first_start
    if preferred is None:
        preferred = {"hour": 15, "minute": 0}
    return {
        "id": f"rescue_recovery_{day_iso}",
        "day": day_iso,
        "title": "恢复缓冲",
        "tag": "Recovery",
        "load": "low",
        "height": RECOVERY_BUFFER_HEIGHT,
        "color": RECOVERY_BUFFER_COLOR,
        "time": preferred,
    }


def _moved_ids(
    baseline: list[dict[str, Any]],
    candidate: list[dict[str, Any]],
) -> list[str]:
    """Baseline entry ids that changed in the candidate plan.

    Mirrors Dart `_movedEntryCount`: an entry is moved when its id is missing
    from the candidate, its `time` differs, or its `height` differs by > 0.1.
    """
    candidate_by_id = {}
    for entry in candidate:
        entry_id = entry.get("id")
        if isinstance(entry_id, str) and entry_id:
            candidate_by_id[entry_id] = entry
    moved: list[str] = []
    for entry in baseline:
        entry_id = entry.get("id")
        if not isinstance(entry_id, str) or not entry_id:
            continue
        next_entry = candidate_by_id.get(entry_id)
        if next_entry is None:
            moved.append(entry_id)
            continue
        if next_entry.get("time") != entry.get("time"):
            moved.append(entry_id)
            continue
        try:
            height_delta = abs(
                float(next_entry.get("height") or 0.0) - float(entry.get("height") or 0.0)
            )
        except (TypeError, ValueError):
            height_delta = 0.0
        if height_delta > 0.1:
            moved.append(entry_id)
    return moved


def build_options(request: dict[str, Any]) -> dict[str, Any]:
    """Generate the three rescue options plus the baseline hash."""
    day_iso = _iso_day(request.get("day")) or ""
    urgent = request.get("urgentTask") if isinstance(request.get("urgentTask"), dict) else {}
    current_entries = request.get("currentEntries") or []
    energy = request.get("energy") or "medium"
    strategies = request.get("strategies") or list(RESCUE_STRATEGIES)
    windows = request.get("windows") or []
    tuning = request.get("tuning") or {}
    fixed = request.get("fixed") or []
    tasks = request.get("tasks") or []

    baseline = [
        entry
        for entry in current_entries
        if isinstance(entry, dict) and _iso_day(entry.get("day")) == day_iso
    ]

    compositions = {
        "protectDeadline": {
            "tasks": [*tasks, urgent],
            "energy": energy,
            "fixed": fixed,
        },
        "protectRecovery": {
            "tasks": [*tasks, urgent],
            "energy": _lower_energy(energy),
            "fixed": [*fixed, _recovery_buffer(day_iso, windows)],
        },
        "minimizeChanges": {
            "tasks": [urgent],
            "energy": energy,
            "fixed": [*fixed, *baseline],
        },
    }

    options: list[dict[str, Any]] = []
    for index, strategy in enumerate(strategies, start=1):
        composition = compositions[strategy]
        plan = plan_schedule(
            {
                "day": day_iso,
                "tasks": composition["tasks"],
                "windows": windows,
                "energy": composition["energy"],
                "tuning": tuning,
                "fixed": composition["fixed"],
            }
        )
        moved_ids = _moved_ids(baseline, plan["entries"])
        options.append(
            {
                "id": f"option_{index:03d}",
                "strategy": strategy,
                "title": RESCUE_TITLES[strategy],
                "recommended": False,
                "rationale": RESCUE_RATIONALES[strategy],
                "tradeoff": RESCUE_TRADEOFFS[strategy],
                "movedEntryCount": len(moved_ids),
                "recoveryMinutes": RECOVERY_BUFFER_MINUTES if strategy == "protectRecovery" else 0,
                "issueCount": len(plan.get("issues") or []),
                "affectedEntries": moved_ids,
                "plannedEntries": plan["entries"],
            }
        )

    if options:
        recommended_index = min(
            range(len(options)),
            key=lambda i: (options[i]["issueCount"], options[i]["movedEntryCount"], i),
        )
        options[recommended_index]["recommended"] = True

    return {
        "options": options,
        "baselineHash": compute_baseline_hash(current_entries, day_iso),
    }


def is_rescue_event(event: dict[str, Any]) -> bool:
    reason = event.get("reason")
    return isinstance(reason, str) and (
        reason.startswith("rescue_accept:") or reason.startswith("rescue_undo:")
    )


def filter_rescue_events(events: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [event for event in events if is_rescue_event(event)]


def build_rescue_event(
    urgent: dict[str, Any] | None,
    event_id: str | None,
    energy: str,
) -> dict[str, Any]:
    """TaskEvent payload base for accept/undo events, mirroring the client.

    `type`/`reason`/`at` are forced by the repository transaction; the caller
    only supplies the urgent-task facts, an optional client event id and the
    energy level. Undo events hardcode `energy="medium"` like the client.
    """
    urgent = urgent or {}
    event: dict[str, Any] = {}
    if event_id:
        event["id"] = event_id
    event["taskId"] = str(urgent.get("id") or "")
    event["title"] = str(urgent.get("title") or "救援任务")
    event["tag"] = str(urgent.get("tag") or "Urgent")
    event["load"] = urgent.get("load")
    event["plannedMinutes"] = int(urgent.get("durationMinutes") or 0)
    event["energy"] = energy
    return event
