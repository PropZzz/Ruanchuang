from __future__ import annotations

import re
from datetime import date, datetime, timezone
from enum import Enum
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, field_serializer, field_validator, model_validator


_DATETIME_RE = re.compile(
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]"
    r"(?::[0-5][0-9](?:\.[0-9]+)?)?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])?$"
)


class ContractModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="forbid")


class Energy(str, Enum):
    very_low = "veryLow"
    low = "low"
    medium = "medium"
    high = "high"
    very_high = "veryHigh"


class Load(str, Enum):
    low = "low"
    medium = "medium"
    high = "high"


class IssueCode(str, Enum):
    no_slot = "no_slot"
    miss_due = "miss_due"
    overdue = "overdue"
    dependency_blocked = "dependency_blocked"


class Source(str, Enum):
    fixed = "fixed"
    planned = "planned"
    recovery = "recovery"


ExplanationCode = Literal[
    "deadline_proximity",
    "priority",
    "energy_fit",
    "kept_baseline",
    "fixed_conflict",
]


def _normalise_datetime(value: object) -> datetime:
    if isinstance(value, str):
        if not _DATETIME_RE.fullmatch(value):
            raise ValueError("datetime must be an ISO date-time with timezone offset or Z")
        value = value[:-1] + "+00:00" if value.endswith("Z") else value
        try:
            value = datetime.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("invalid datetime") from exc
    if not isinstance(value, datetime):
        raise ValueError("invalid datetime")
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _utc_z(value: datetime | None) -> str | None:
    if value is None:
        return None
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


class ClockTime(ContractModel):
    hour: int = Field(ge=0, le=23)
    minute: int = Field(ge=0, le=59)


class TimeWindow(ContractModel):
    start: ClockTime
    end: ClockTime

    @model_validator(mode="after")
    def validate_order(self) -> TimeWindow:
        if (self.end.hour, self.end.minute) <= (self.start.hour, self.start.minute):
            raise ValueError("window end must be strictly after start")
        return self


class SchedulingTuning(ContractModel):
    default_duration_multiplier: float = Field(default=1.0, alias="defaultDurationMultiplier", gt=0)
    tag_duration_multiplier: dict[str, float] = Field(default_factory=dict, alias="tagDurationMultiplier")
    high_load_penalty_when_low_energy: float = Field(
        default=1.0, alias="highLoadPenaltyWhenLowEnergy", gt=0
    )

    @field_validator("tag_duration_multiplier")
    @classmethod
    def validate_tag_multipliers(cls, value: dict[str, float]) -> dict[str, float]:
        if any(multiplier <= 0 for multiplier in value.values()):
            raise ValueError("tag duration multipliers must be greater than zero")
        return value


class SchedulingTask(ContractModel):
    id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    duration_minutes: int = Field(alias="durationMinutes", ge=1, le=1440)
    priority: int = Field(ge=1, le=5)
    load: Load | None
    tag: str
    goal_id: str | None = Field(default=None, alias="goalId")
    goal_task_id: str | None = Field(default=None, alias="goalTaskId")
    due: datetime | None = None
    earliest_start: datetime | None = Field(default=None, alias="earliestStart")
    hard_deadline: bool = Field(default=False, alias="hardDeadline")
    depends_on: list[str] = Field(default_factory=list, alias="dependsOn")
    splittable: Literal[False] = False
    minimum_chunk_minutes: Literal[None] = Field(default=None, alias="minimumChunkMinutes")

    @field_validator("due", "earliest_start", mode="before")
    @classmethod
    def normalise_dates(cls, value: object) -> object:
        return None if value is None else _normalise_datetime(value)

    @field_validator("depends_on")
    @classmethod
    def validate_dependencies(cls, value: list[str]) -> list[str]:
        if any(not dependency for dependency in value) or len(set(value)) != len(value):
            raise ValueError("dependsOn must contain unique non-empty ids")
        return value

    @field_serializer("due", "earliest_start", when_used="json")
    def serialize_dates(self, value: datetime | None) -> str | None:
        return _utc_z(value)


def _height_to_duration(value: object) -> int:
    try:
        height = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("legacy fixed height must be numeric") from exc
    return max(1, min(1440, round(height / 80.0 * 60.0)))


class FixedEntry(ContractModel):
    id: str = Field(min_length=1)
    day: date | None = None
    title: str = Field(min_length=1)
    tag: str = "Fixed"
    load: Load | None = None
    goal_id: str | None = Field(default=None, alias="goalId")
    goal_task_id: str | None = Field(default=None, alias="goalTaskId")
    duration_minutes: int = Field(alias="durationMinutes", ge=1, le=1440)
    time: ClockTime
    source: Literal["fixed"] = "fixed"

    @model_validator(mode="before")
    @classmethod
    def convert_legacy_height(cls, value: object) -> object:
        if not isinstance(value, dict):
            return value
        converted = dict(value)
        if "durationMinutes" not in converted and "duration_minutes" not in converted:
            if "height" in converted:
                converted["durationMinutes"] = _height_to_duration(converted.pop("height"))
        else:
            converted.pop("height", None)
        return converted


class SchedulingRequest(ContractModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    day: date
    tasks: list[SchedulingTask]
    windows: list[TimeWindow]
    energy: Energy = Energy.medium
    tuning: SchedulingTuning = Field(default_factory=SchedulingTuning)
    fixed: list[FixedEntry] = Field(default_factory=list)

    def to_engine_request(self) -> dict[str, Any]:
        payload = self.model_dump(mode="json", by_alias=True)
        for entry in payload["fixed"]:
            entry["height"] = round(entry.pop("durationMinutes") / 60.0 * 80.0, 2)
            entry.pop("source", None)
        return payload


class PlanEntry(ContractModel):
    id: str = Field(min_length=1)
    day: date
    title: str = Field(min_length=1)
    tag: str
    load: Load | None
    goal_id: str | None = Field(default=None, alias="goalId")
    goal_task_id: str | None = Field(default=None, alias="goalTaskId")
    duration_minutes: int = Field(alias="durationMinutes", ge=1, le=1440)
    time: ClockTime
    source: Source
    explanation_codes: list[ExplanationCode] = Field(default_factory=list, alias="explanationCodes")


class SchedulingIssue(ContractModel):
    code: IssueCode
    message: str = Field(min_length=1)
    task_id: str | None = Field(default=None, alias="taskId")
    blocked_by: list[str] | None = Field(default=None, alias="blockedBy")
    explanation_codes: list[ExplanationCode] = Field(default_factory=list, alias="explanationCodes")


class SchedulingResponse(ContractModel):
    schema_version: Literal["1"] = Field(default="1", alias="schemaVersion")
    entries: list[PlanEntry]
    issues: list[SchedulingIssue] = Field(default_factory=list)


def _duration_from_height(value: object) -> int:
    try:
        return max(1, min(1440, round(float(value or 80.0) / 80.0 * 60.0)))
    except (TypeError, ValueError):
        return 60


def to_contract_response(result: dict[str, Any], request: SchedulingRequest) -> SchedulingResponse:
    fixed_ids = {entry.id for entry in request.fixed}
    entries: list[dict[str, Any]] = []
    for index, raw in enumerate(result.get("entries") or []):
        item = dict(raw)
        item["id"] = str(item.get("id") or f"plan_{index}")
        item["day"] = item.get("day") or request.day.isoformat()
        item["title"] = str(item.get("title") or "Untitled")
        item["tag"] = str(item.get("tag") or "Task")
        item["load"] = item.get("load")
        item["durationMinutes"] = int(item.get("durationMinutes") or _duration_from_height(item.get("height")))
        item["source"] = "fixed" if item["id"] in fixed_ids else item.get("source", "planned")
        if item["source"] not in {source.value for source in Source}:
            item["source"] = "planned"
        item["explanationCodes"] = list(item.get("explanationCodes") or [])
        entries.append(
            {
                key: item[key]
                for key in (
                    "id",
                    "day",
                    "title",
                    "tag",
                    "load",
                    "goalId",
                    "goalTaskId",
                    "durationMinutes",
                    "time",
                    "source",
                    "explanationCodes",
                )
                if key in item
            }
        )

    issues: list[dict[str, Any]] = []
    for raw in result.get("issues") or []:
        issue = {
            "code": raw.get("code"),
            "message": str(raw.get("message") or "Scheduling issue"),
            "explanationCodes": list(raw.get("explanationCodes") or []),
        }
        if raw.get("taskId") is not None:
            issue["taskId"] = raw["taskId"]
        if raw.get("blockedBy") is not None:
            issue["blockedBy"] = list(raw["blockedBy"])
        issues.append(issue)
    return SchedulingResponse(entries=entries, issues=issues)
