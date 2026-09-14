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


def test_strategy_policy_matrix_is_versioned_and_complete() -> None:
    config = load_strategy_config()
    assert config.policy_version == "1"
    assert config.hard_constraint_order == (
        "normalize",
        "fixedSchedule",
        "workWindows",
        "dependencies",
        "deadline",
    )
    assert config.explanation_code_order == (
        "deadline_proximity",
        "priority",
        "energy_fit",
        "kept_baseline",
        "fixed_conflict",
    )
    expected_fields = {
        "scenario",
        "fixedSchedule",
        "baselinePolicy",
        "deadlinePolicy",
        "lowEnergyPolicy",
        "movementPolicy",
        "recoveryPolicy",
        "overdueRiskPolicy",
    }
    assert all(set(policy) == expected_fields for policy in config.policies.values())


@pytest.mark.parametrize("field", ["hardConstraintOrder", "explanationCodeOrder"])
def test_invalid_policy_order_is_rejected(tmp_path: Path, field: str) -> None:
    source = json.loads(
        (ROOT / "contracts/scheduling/v1/rescue-strategies.json").read_text(encoding="utf-8")
    )
    source[field] = ["unknown"]
    path = tmp_path / "rescue-strategies.json"
    path.write_text(json.dumps(source), encoding="utf-8")
    with pytest.raises(ValueError):
        load_strategy_config(path)


def test_unknown_strategy_policy_value_is_rejected(tmp_path: Path) -> None:
    source = json.loads(
        (ROOT / "contracts/scheduling/v1/rescue-strategies.json").read_text(encoding="utf-8")
    )
    source["strategies"]["protectDeadline"]["scenario"] = "unknown"
    path = tmp_path / "rescue-strategies.json"
    path.write_text(json.dumps(source), encoding="utf-8")
    with pytest.raises(ValueError):
        load_strategy_config(path)
