"""Pure-computation tests for the rescue service layer."""

from backend.services_rescue import (
    build_options,
    build_rescue_event,
    compute_baseline_hash,
    filter_rescue_events,
)


DAY = "2026-08-09"


def _entry(entry_id="e1", day=DAY, hour=9, minute=0, height=80.0, **over):
    entry = {
        "id": entry_id,
        "day": day,
        "title": "任务",
        "tag": "Work",
        "load": "medium",
        "height": height,
        "color": 0,
        "time": {"hour": hour, "minute": minute},
        "reminderMinutesBefore": 10,
        "repeat": "none",
    }
    entry.update(over)
    return entry


def _request(**over):
    request = {
        "day": DAY,
        "urgentTask": {
            "id": "urgent_1",
            "title": "客户紧急问题",
            "durationMinutes": 60,
            "priority": 5,
            "load": "high",
            "tag": "Urgent",
            "due": f"{DAY}T15:30:00+08:00",
        },
        "currentEntries": [_entry("base_1", hour=9)],
        "energy": "medium",
        "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 18, "minute": 0}}],
    }
    request.update(over)
    return request


def test_baseline_hash_is_order_independent_and_stable():
    entries = [_entry("b"), _entry("a"), _entry("c", hour=14)]
    shuffled = list(reversed(entries))
    assert compute_baseline_hash(entries, DAY) == compute_baseline_hash(shuffled, DAY)
    assert compute_baseline_hash(entries, DAY) == compute_baseline_hash(entries, DAY)


def test_baseline_hash_excludes_other_days_and_inbox():
    entries = [_entry("a"), _entry("b", day="2026-08-10"), _entry("c", day=None)]
    assert compute_baseline_hash(entries, DAY) == compute_baseline_hash([_entry("a")], DAY)


def test_baseline_hash_collapses_float_noise_and_ignores_extra_keys():
    base = _entry("a", height=80.0)
    noisy = _entry("a", height=80.004, extra="ignored")
    assert compute_baseline_hash([base], DAY) == compute_baseline_hash([noisy], DAY)


def test_baseline_hash_changes_when_entries_change():
    same = _entry("a")
    moved = _entry("a", hour=10)
    renamed = _entry("b")
    assert compute_baseline_hash([same], DAY) != compute_baseline_hash([moved], DAY)
    assert compute_baseline_hash([same], DAY) != compute_baseline_hash([renamed], DAY)
    assert compute_baseline_hash([], DAY) != compute_baseline_hash([same], DAY)


def test_build_options_returns_three_options_in_requested_order():
    result = build_options(_request())
    assert [option["strategy"] for option in result["options"]] == [
        "protectDeadline",
        "protectRecovery",
        "minimizeChanges",
    ]
    assert [option["id"] for option in result["options"]] == [
        "option_001",
        "option_002",
        "option_003",
    ]
    for option in result["options"]:
        assert option["title"]
        assert option["rationale"]
        assert option["tradeoff"]
        assert option["recoveryMinutes"] == (15 if option["strategy"] == "protectRecovery" else 0)
        assert isinstance(option["plannedEntries"], list)
    assert sum(1 for option in result["options"] if option["recommended"]) == 1
    assert len(result["baselineHash"]) == 64


def test_build_options_filters_strategies():
    result = build_options(_request(strategies=["minimizeChanges"]))
    assert [option["strategy"] for option in result["options"]] == ["minimizeChanges"]


def test_build_options_protect_deadline_places_urgent_before_due():
    result = build_options(_request())
    deadline = next(
        option for option in result["options"] if option["strategy"] == "protectDeadline"
    )
    urgent_entry = next(entry for entry in deadline["plannedEntries"] if entry["id"] == "urgent_1")
    end_minutes = (
        urgent_entry["time"]["hour"] * 60
        + urgent_entry["time"]["minute"]
        + int(round((urgent_entry["height"] / 80.0) * 60.0))
    )
    assert end_minutes <= 15 * 60 + 30


def test_build_options_protect_recovery_contains_recovery_buffer():
    result = build_options(_request())
    recovery = next(
        option for option in result["options"] if option["strategy"] == "protectRecovery"
    )
    buffers = [entry for entry in recovery["plannedEntries"] if entry["id"] == f"rescue_recovery_{DAY}"]
    assert len(buffers) == 1
    assert buffers[0]["height"] == 20.0
    # The only window starts at 8:00 (< 12:00), so the buffer falls back to its start.
    assert buffers[0]["time"] == {"hour": 8, "minute": 0}


def test_build_options_recovery_buffer_prefers_afternoon_window():
    request = _request()
    request["windows"] = [
        {"start": {"hour": 8, "minute": 0}, "end": {"hour": 11, "minute": 0}},
        {"start": {"hour": 13, "minute": 30}, "end": {"hour": 18, "minute": 0}},
    ]
    result = build_options(request)
    recovery = next(
        option for option in result["options"] if option["strategy"] == "protectRecovery"
    )
    buffers = [entry for entry in recovery["plannedEntries"] if entry["id"] == f"rescue_recovery_{DAY}"]
    assert buffers[0]["time"] == {"hour": 13, "minute": 30}


def test_build_options_minimize_changes_locks_baseline():
    result = build_options(_request())
    minimal = next(
        option for option in result["options"] if option["strategy"] == "minimizeChanges"
    )
    assert minimal["movedEntryCount"] == 0
    baseline_entry = next(entry for entry in minimal["plannedEntries"] if entry["id"] == "base_1")
    assert baseline_entry["time"] == {"hour": 9, "minute": 0}

    deadline = next(
        option for option in result["options"] if option["strategy"] == "protectDeadline"
    )
    assert deadline["movedEntryCount"] >= 1
    assert deadline["affectedEntries"] == ["base_1"]


def test_filter_rescue_events_keeps_only_rescue_reasons():
    events = [
        {"id": "1", "reason": "rescue_accept:protectDeadline"},
        {"id": "2", "reason": "rescue_undo:protectDeadline"},
        {"id": "3", "reason": "meeting"},
        {"id": "4", "reason": None},
    ]
    kept = filter_rescue_events(events)
    assert [event["id"] for event in kept] == ["1", "2"]


def test_build_rescue_event_fields_and_defaults():
    urgent = {
        "id": "u1",
        "title": "紧急",
        "tag": "Urgent",
        "load": "high",
        "durationMinutes": 45,
    }
    event = build_rescue_event(urgent, "evt-1", "medium")
    assert event["id"] == "evt-1"
    assert event["taskId"] == "u1"
    assert event["title"] == "紧急"
    assert event["tag"] == "Urgent"
    assert event["load"] == "high"
    assert event["plannedMinutes"] == 45
    assert event["energy"] == "medium"

    fallback = build_rescue_event(None, None, "low")
    assert "id" not in fallback
    assert fallback["title"] == "救援任务"
    assert fallback["tag"] == "Urgent"
    assert fallback["plannedMinutes"] == 0
    assert fallback["energy"] == "low"
