"""Pure rescue strategy ranking helpers."""

from __future__ import annotations

from typing import Any, Iterable


class RescueStrategy:
    """Apply hard-issue precedence and stable score tie-breaking."""

    ORDER = ("protectDeadline", "protectRecovery", "minimizeChanges")
    HARD_ISSUE_CODES = frozenset({"fixed_conflict", "no_slot", "dependency_blocked"})

    @classmethod
    def hard_issue_count(cls, issues: Iterable[dict[str, Any]]) -> int:
        return sum(
            1
            for issue in issues
            if isinstance(issue, dict) and issue.get("code") in cls.HARD_ISSUE_CODES
        )

    @classmethod
    def recommended_index(cls, options: list[dict[str, Any]]) -> int | None:
        if not options:
            return None
        return min(
            range(len(options)),
            key=lambda index: (
                int(options[index].get("hardIssueCount") or 0),
                -float(options[index].get("score") or 0.0),
                index,
            ),
        )


__all__ = ["RescueStrategy"]
