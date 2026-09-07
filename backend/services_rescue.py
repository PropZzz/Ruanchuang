from __future__ import annotations

from typing import Any

from .services_scheduling import plan_schedule


def build_rescue_options(request: dict[str, Any]) -> list[dict[str, Any]]:
    day = request.get("day")
    urgent = dict(request.get("urgentTask") or {})
    current = [dict(item) for item in request.get("currentEntries") or [] if isinstance(item, dict)]
    energy = str(request.get("energy") or "medium")
    windows = [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 20, "minute": 0}}]
    strategies = request.get("strategies") or ["protectDeadline", "protectRecovery", "minimizeChanges"]
    options: list[dict[str, Any]] = []
    for strategy in strategies:
        fixed = current
        if strategy == "protectRecovery":
            fixed = [*current, {"id": f"recovery-{day}", "day": day, "title": "恢复缓冲", "tag": "Recovery", "height": 20, "time": {"hour": 15, "minute": 0}}]
        plan = plan_schedule({"day": day, "energy": energy, "windows": windows, "fixed": fixed, "tasks": [urgent]})
        baseline_ids = {str(entry.get("id")) for entry in current}
        moved = sum(1 for entry in current if str(entry.get("id")) not in {str(item.get("id")) for item in plan["entries"]})
        options.append(
            {
                "id": f"rescue-{strategy}",
                "strategy": strategy,
                "title": {"protectDeadline": "优先保住截止时间", "protectRecovery": "优先保留恢复时间", "minimizeChanges": "尽量少动原计划"}.get(strategy, strategy),
                "recommended": strategy == "protectDeadline",
                "rationale": "先安排紧急事项，再处理原有日程。" if strategy == "protectDeadline" else "保留当前日程并尽量留出恢复空间。",
                "tradeoff": "可能移动普通任务。" if strategy != "minimizeChanges" else "空档不足时可能无法安排。",
                "movedEntryCount": moved,
                "recoveryMinutes": 15 if strategy == "protectRecovery" else 0,
                "issueCount": len(plan["issues"]),
                "affectedEntries": [entry for entry in current if str(entry.get("id")) not in baseline_ids],
                "plannedEntries": plan["entries"],
                "issues": plan["issues"],
            }
        )
    return options
