from __future__ import annotations

import json
from pathlib import Path

import pytest

from backend.scheduling.rescue_scoring import PlanMetrics, load_strategy_config, score_plan


ROOT = Path(__file__).resolve().parents[2]


def test_strategy_weights_are_normalized() -> None:
    config = load_strategy_config()
    assert config.recovery_buffer_minutes == 15
    assert set(config.strategies) == {
        "protectDeadline",
        "protectRecovery",
        "minimizeChanges",
    }
    for weights in config.strategies.values():
        assert all(value >= 0 for value in weights.values())
        assert sum(weights.values()) == pytest.approx(1.0, abs=0.000001)


def test_score_uses_weighted_metrics() -> None:
    weights = load_strategy_config().strategies["protectDeadline"]
    metrics = PlanMetrics(
        urgency=1.0,
        priority=0.8,
        energy_fit=0.5,
        stability=0.9,
        recovery=0.0,
    )
    assert score_plan(weights, metrics) == 0.89


def test_config_file_contains_the_runtime_contract() -> None:
    payload = json.loads(
        (ROOT / "contracts/scheduling/v1/rescue-strategies.json").read_text(encoding="utf-8")
    )
    assert payload["schemaVersion"] == "1"
    assert payload["recoveryBufferMinutes"] == 15
