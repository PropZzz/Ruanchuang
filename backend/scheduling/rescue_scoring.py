from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from types import MappingProxyType
from typing import Any, Mapping


STRATEGY_NAMES = ("protectDeadline", "protectRecovery", "minimizeChanges")
METRIC_NAMES = ("urgency", "priority", "energyFit", "stability", "recovery")
_WEIGHT_TOLERANCE = 0.000001
_POLICY_FIELDS = (
    "scenario",
    "fixedSchedule",
    "baselinePolicy",
    "deadlinePolicy",
    "lowEnergyPolicy",
    "movementPolicy",
    "recoveryPolicy",
    "overdueRiskPolicy",
)
_HARD_CONSTRAINT_ORDER = ("normalize", "fixedSchedule", "workWindows", "dependencies", "deadline")
_EXPLANATION_CODE_ORDER = (
    "deadline_proximity",
    "priority",
    "energy_fit",
    "kept_baseline",
    "fixed_conflict",
)
_POLICY_VALUES = {
    "scenario": {"deadlineFirst", "recoveryFirst", "baselineFirst"},
    "fixedSchedule": {"preserve", "preserveAndLockBaseline"},
    "baselinePolicy": {"reflowNonFixed", "lockAll"},
    "deadlinePolicy": {
        "prioritizeDueDates",
        "preserveHardDeadlines",
        "hardDeadlineNoLateFallback",
    },
    "lowEnergyPolicy": {"preferMatchingLoad", "lowerTargetEnergy", "softPreferenceOnly"},
    "movementPolicy": {"reflowNonFixedBaseline", "preserveBaseline"},
    "recoveryPolicy": {"none", "insert15MinuteBuffer"},
    "overdueRiskPolicy": {"deadlineIssues"},
}


@dataclass(frozen=True)
class PlanMetrics:
    urgency: float
    priority: float
    energy_fit: float
    stability: float
    recovery: float

    @property
    def overdue_risk(self) -> float:
        """Deadline-miss risk paired with the contract's urgency metric."""
        return round(_clamp(1.0 - self.urgency), 6)

    def as_contract_dict(self) -> dict[str, float]:
        return {
            "urgency": self.urgency,
            "priority": self.priority,
            "energyFit": self.energy_fit,
            "stability": self.stability,
            "recovery": self.recovery,
        }


@dataclass(frozen=True)
class RescueStrategyConfig:
    recovery_buffer_minutes: int
    strategies: Mapping[str, Mapping[str, float]]
    policy_version: str
    hard_constraint_order: tuple[str, ...]
    explanation_code_order: tuple[str, ...]
    policies: Mapping[str, Mapping[str, str]]


def _config_path() -> Path:
    return Path(__file__).resolve().parents[2] / "contracts" / "scheduling" / "v1" / "rescue-strategies.json"


def load_strategy_config(path: Path | None = None) -> RescueStrategyConfig:
    config_path = path or _config_path()
    payload = json.loads(config_path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != "1":
        raise ValueError("rescue strategy schemaVersion must be 1")
    if payload.get("policyVersion") != "1":
        raise ValueError("rescue strategy policyVersion must be 1")
    hard_order = payload.get("hardConstraintOrder")
    if not isinstance(hard_order, list) or hard_order != list(_HARD_CONSTRAINT_ORDER):
        raise ValueError("hardConstraintOrder does not match the contract")
    if len(hard_order) != len(set(hard_order)):
        raise ValueError("hardConstraintOrder must not contain duplicates")
    explanation_order = payload.get("explanationCodeOrder")
    if not isinstance(explanation_order, list) or explanation_order != list(_EXPLANATION_CODE_ORDER):
        raise ValueError("explanationCodeOrder does not match the contract")
    if len(explanation_order) != len(set(explanation_order)):
        raise ValueError("explanationCodeOrder must not contain duplicates")
    buffer_minutes = payload.get("recoveryBufferMinutes")
    if not isinstance(buffer_minutes, int) or buffer_minutes <= 0:
        raise ValueError("recoveryBufferMinutes must be a positive integer")
    raw_strategies = payload.get("strategies")
    if not isinstance(raw_strategies, dict) or set(raw_strategies) != set(STRATEGY_NAMES):
        raise ValueError("rescue strategy names do not match the contract")

    strategies: dict[str, dict[str, float]] = {}
    policies: dict[str, dict[str, str]] = {}
    for name in STRATEGY_NAMES:
        raw_weights = raw_strategies[name]
        if not isinstance(raw_weights, dict):
            raise ValueError(f"{name} must define a strategy object")
        raw_policy = {key: raw_weights.get(key) for key in _POLICY_FIELDS}
        if set(raw_policy) != set(_POLICY_FIELDS) or any(value is None for value in raw_policy.values()):
            raise ValueError(f"{name} must define every rescue policy field")
        unknown_policy_values = [
            key for key, value in raw_policy.items()
            if not isinstance(value, str) or value not in _POLICY_VALUES[key]
        ]
        if unknown_policy_values:
            raise ValueError(f"{name} contains an unknown policy value")
        if set(raw_weights) != set(METRIC_NAMES) | set(_POLICY_FIELDS):
            raise ValueError(f"{name} must define every rescue metric")
        weights = {key: float(raw_weights[key]) for key in METRIC_NAMES}
        if any(value < 0 for value in weights.values()):
            raise ValueError(f"{name} contains a negative weight")
        if abs(sum(weights.values()) - 1.0) > _WEIGHT_TOLERANCE:
            raise ValueError(f"{name} weights must sum to 1")
        strategies[name] = weights
        policies[name] = raw_policy
    return RescueStrategyConfig(
        recovery_buffer_minutes=buffer_minutes,
        strategies=MappingProxyType({name: MappingProxyType(values) for name, values in strategies.items()}),
        policy_version="1",
        hard_constraint_order=_HARD_CONSTRAINT_ORDER,
        explanation_code_order=_EXPLANATION_CODE_ORDER,
        policies=MappingProxyType({name: MappingProxyType(values) for name, values in policies.items()}),
    )


def _clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def score_plan(weights: dict[str, float], metrics: PlanMetrics) -> float:
    values = metrics.as_contract_dict()
    score = sum(weights[name] * _clamp(values[name]) for name in METRIC_NAMES)
    return round(score, 6)


def metrics_for_plan(
    plan: dict[str, Any],
    tasks: list[dict[str, Any]],
    *,
    moved_entry_count: int,
    baseline_entry_count: int,
    energy: str,
    recovery_minutes: int,
    recovery_buffer_minutes: int | None = None,
) -> PlanMetrics:
    task_by_id = {
        str(task.get("id")): task
        for task in tasks
        if isinstance(task, dict) and task.get("id")
    }
    entries = [entry for entry in plan.get("entries") or [] if isinstance(entry, dict)]
    def base_task_id(value: object) -> str:
        return str(value or "").split("#", 1)[0]

    placed_ids: list[str] = []
    for entry in entries:
        task_id = base_task_id(entry.get("id"))
        if task_id in task_by_id and entry.get("source", "planned") == "planned" and task_id not in placed_ids:
            placed_ids.append(task_id)
    placed_tasks = [task_by_id[task_id] for task_id in placed_ids]
    issues = [issue for issue in plan.get("issues") or [] if isinstance(issue, dict)]
    evaluated_ids = set(placed_ids)
    evaluated_ids.update(
        base_task_id(issue.get("taskId"))
        for issue in issues
        if issue.get("taskId")
    )
    evaluated_tasks = [task for task_id, task in task_by_id.items() if task_id in evaluated_ids]
    due_count = sum(1 for task in evaluated_tasks if task.get("due"))
    missed_count = sum(
        1 for issue in issues if issue.get("code") in {"miss_due", "overdue"}
    )
    urgency = 1.0 - missed_count / max(1, due_count)
    priority_sum = sum(int(task.get("priority") or 0) for task in placed_tasks)
    priority = priority_sum / (5 * max(1, len(evaluated_tasks)))

    target_load = 0 if energy in {"veryLow", "low"} else 1 if energy == "medium" else 2
    load_index = {"low": 0, "medium": 1, "high": 2}
    mismatch = 0.0
    for task in placed_tasks:
        load = task.get("load")
        mismatch += abs(load_index.get(str(load), target_load) - target_load) / 2.0
    energy_fit = 1.0 - mismatch / max(1, len(placed_tasks))
    stability = 1.0 - moved_entry_count / max(1, baseline_entry_count)
    buffer = recovery_buffer_minutes or load_strategy_config().recovery_buffer_minutes
    recovery = min(recovery_minutes / buffer, 1.0)
    return PlanMetrics(
        urgency=_clamp(urgency),
        priority=_clamp(priority),
        energy_fit=_clamp(energy_fit),
        stability=_clamp(stability),
        recovery=_clamp(recovery),
    )
