"""Compatibility facade for the pure scheduling core."""

from __future__ import annotations

from typing import Any

from .scheduling.core import SchedulerCore


def plan_schedule(request: dict[str, Any]) -> dict[str, Any]:
    return SchedulerCore().plan(request)
