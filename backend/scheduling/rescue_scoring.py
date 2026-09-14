from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any


STRATEGY_NAMES = ("protectDeadline", "protectRecovery", "minimizeChanges")
METRIC_NAMES = ("urgency", "priority", "energyFit", "stability", "recovery")
_WEIGHT_TOLERANCE = 0.000001


@dataclass(frozen=True)
class PlanMetrics:
    urgency: float
    priority: float
    energy_fit: float
    stability: float
    recovery: float

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
    strategies: dict[str, dict[str, float]]


def _config_path() -> Path:
    return Path(__file__).resolve().parents[2] / "contracts" / "scheduling" / "v1" / "rescue-strategies.json"


def load_strategy_config(path: Path | None = None) -> RescueStrategyConfig:
    config_path = path or _config_path()
    payload = json.loads(config_path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != "1":
        raise ValueError("rescue strategy schemaVersion must be 1")
    buffer_minutes = payload.get("recoveryBufferMinutes")
    if not isinstance(buffer_minutes, int) or buffer_minutes <= 0:
        raise ValueError("recoveryBufferMinutes must be a positive integer")
    raw_strategies = payload.get("strategies")
    if not isinstance(raw_strategies, dict) or set(raw_strategies) != set(STRATEGY_NAMES):
        raise ValueError("rescue strategy names do not match the contract")

    strategies: dict[str, dict[str, float]] = {}
    for name in STRATEGY_NAMES:
        raw_weights = raw_strategies[name]
        if not isinstance(raw_weights, dict) or set(raw_weights) != set(METRIC_NAMES):
            raise ValueError(f"{name} must define every rescue metric")
        weights = {key: float(raw_weights[key]) for key in METRIC_NAMES}
        if any(value < 0 for value in weights.values()):
            raise ValueError(f"{name} contains a negative weight")
        if abs(sum(weights.values()) - 1.0) > _WEIGHT_TOLERANCE:
            raise ValueError(f"{name} weights must sum to 1")
        strategies[name] = weights
    return RescueStrategyConfig(buffer_minutes, strategies)


def _clamp(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def score_plan(weights: dict[str, float], metrics: PlanMetrics) -> float:
    values = metrics.as_contract_dict()
    score = sum(weights[name] * _clamp(values[name]) for name in METRIC_NAMES)
    return round(score, 6)
