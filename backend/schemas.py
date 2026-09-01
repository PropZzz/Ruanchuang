from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class APIModel(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")


class ClockTime(APIModel):
    hour: int = 0
    minute: int = 0


class UserCreate(APIModel):
    contact_address: str = Field(alias="contactAddress")
    display_name: str = Field(alias="displayName")
    password: str


class UserLogin(APIModel):
    contact_address: str = Field(alias="contactAddress")
    password: str


class UserOut(APIModel):
    id: str
    contact_address: str = Field(alias="contactAddress")
    display_name: str = Field(alias="displayName")


class TokenResponse(APIModel):
    access_token: str = Field(alias="accessToken")
    token_type: str = Field(default="Bearer", alias="tokenType")
    user: UserOut


class ScheduleEntryIn(APIModel):
    id: str | None = None
    day: date | None = None
    title: str
    tag: str
    load: str | None = None
    goal_id: str | None = Field(default=None, alias="goalId")
    goal_task_id: str | None = Field(default=None, alias="goalTaskId")
    height: float = 60.0
    color: int = 0
    time: ClockTime = Field(default_factory=ClockTime)
    reminder_minutes_before: int = Field(default=10, alias="reminderMinutesBefore")
    repeat: str = "none"
    repeat_until: date | None = Field(default=None, alias="repeatUntil")


class ScheduleEntryOut(ScheduleEntryIn):
    id: str


class MicroTaskIn(APIModel):
    id: str | None = None
    title: str
    tag: str
    minutes: int
    priority: int = 3
    requirement: str | None = None
    done: bool = False


class MicroTaskOut(MicroTaskIn):
    id: str


class TimeWindow(APIModel):
    start: ClockTime
    end: ClockTime


class SchedulingRequest(APIModel):
    day: date
    tasks: list[PlanTask]
    windows: list[TimeWindow]
    energy: str = "medium"
    tuning: "SchedulingTuning" = Field(default_factory=lambda: SchedulingTuning())
    fixed: list[ScheduleEntryIn] = Field(default_factory=list)


class SchedulingIssue(APIModel):
    code: str
    message: str
    task_id: str | None = Field(default=None, alias="taskId")


class SchedulingPlanOut(APIModel):
    entries: list[ScheduleEntryOut]
    issues: list[SchedulingIssue] = Field(default_factory=list)


class CrystalOut(APIModel):
    start: ClockTime
    minutes: int
    bucket: str


class CrystalRecommendationRequest(APIModel):
    schedule: list[ScheduleEntryIn] = Field(default_factory=list)
    micro_tasks: list[MicroTaskIn] = Field(default_factory=list, alias="microTasks")
    windows: list[TimeWindow] = Field(default_factory=list)
    energy: str = "medium"
    now: ClockTime = Field(default_factory=ClockTime)
    max_recommendations: int = Field(default=5, alias="maxRecommendations")


class CrystalRecommendationOut(APIModel):
    crystal: CrystalOut
    task: MicroTaskOut
    score: float


class EmotionState:
    efficient = "efficient"
    stable = "stable"
    tired = "tired"
    irritable = "irritable"


class EmotionCheckIn(APIModel):
    id: str
    at: datetime
    state: str
    note: str | None = None

    @field_validator("state")
    @classmethod
    def validate_state(cls, value: str) -> str:
        allowed = {"efficient", "stable", "tired", "irritable"}
        if value not in allowed:
            raise ValueError(f"state must be one of: {', '.join(sorted(allowed))}")
        return value


class EmotionStatusOut(APIModel):
    id: str | None = None
    at: datetime | None = None
    state: str = EmotionState.stable
    note: str | None = None


class CareAlertOut(APIModel):
    active: bool
    severity: str = "none"
    message: str


class EnergySample(APIModel):
    id: str
    at: datetime
    level: str = "medium"
    status: str = "flow"
    description: str = ""
    battery_percent: int = Field(default=85, alias="batteryPercent")
    emotion: str = EmotionState.stable
    flow_state: str = Field(default="normal", alias="flowState")
    source: str = "manual"

    @field_validator("level")
    @classmethod
    def validate_level(cls, value: str) -> str:
        allowed = {"veryLow", "low", "medium", "high", "veryHigh"}
        if value not in allowed:
            raise ValueError(f"level must be one of: {', '.join(sorted(allowed))}")
        return value

    @field_validator("battery_percent")
    @classmethod
    def validate_battery_percent(cls, value: int) -> int:
        if value < 0 or value > 100:
            raise ValueError("batteryPercent must be between 0 and 100")
        return value

    @field_validator("emotion")
    @classmethod
    def validate_emotion(cls, value: str) -> str:
        allowed = {"efficient", "stable", "tired", "irritable"}
        if value not in allowed:
            raise ValueError(f"emotion must be one of: {', '.join(sorted(allowed))}")
        return value

    @field_validator("source")
    @classmethod
    def validate_source(cls, value: str) -> str:
        if value != "manual":
            raise ValueError("source must be manual until device sampling is implemented")
        return value


class EnergyStatusOut(APIModel):
    id: str | None = None
    at: datetime | None = None
    level: str = "medium"
    status: str = "flow"
    description: str = "No recent energy sample; using balanced default."
    battery_percent: int = Field(default=85, alias="batteryPercent")
    emotion: str = EmotionState.stable
    flow_state: str = Field(default="normal", alias="flowState")
    source: str = "default"


class EnergyProfileOut(APIModel):
    sample_count: int = Field(alias="sampleCount")
    latest_level: str = Field(alias="latestLevel")
    average_battery_percent: int = Field(alias="averageBatteryPercent")


class GoalTask(APIModel):
    id: str
    title: str
    duration_minutes: int = Field(alias="durationMinutes")
    load: str
    tag: str
    done: bool = False
    depends_on: list[str] = Field(default_factory=list, alias="dependsOn")

    def copy_with(self, **kwargs):
        data = self.model_dump(by_alias=True)
        data.update(kwargs)
        return GoalTask.model_validate(data)


class Goal(APIModel):
    id: str
    title: str
    due: datetime
    priority: int
    tasks: list[GoalTask]

    @property
    def progress(self) -> float:
        if not self.tasks:
            return 0.0
        return len([t for t in self.tasks if t.done]) / len(self.tasks)


class PlanTask(APIModel):
    id: str
    title: str
    duration_minutes: int = Field(alias="durationMinutes")
    priority: int
    due: datetime | None = None
    load: str
    tag: str


class TaskEvent(APIModel):
    id: str
    task_id: str = Field(alias="taskId")
    title: str
    tag: str
    load: str | None = None
    at: datetime
    type: str
    planned_minutes: int | None = Field(default=None, alias="plannedMinutes")
    energy: str | None = None
    actual_minutes: int | None = Field(default=None, alias="actualMinutes")
    interruptions: int | None = None
    reason: str | None = None


class SchedulingTuning(APIModel):
    default_duration_multiplier: float = Field(default=1.0, alias="defaultDurationMultiplier")
    tag_duration_multiplier: dict[str, float] = Field(default_factory=dict, alias="tagDurationMultiplier")
    high_load_penalty_when_low_energy: float = Field(
        default=1.0, alias="highLoadPenaltyWhenLowEnergy"
    )


class ReviewReport(APIModel):
    week_start: datetime = Field(alias="weekStart")
    week_end: datetime = Field(alias="weekEnd")
    started_count: int = Field(alias="startedCount")
    completed_count: int = Field(alias="completedCount")
    completion_rate: float = Field(alias="completionRate")
    planned_minutes_total: int = Field(alias="plannedMinutesTotal")
    actual_minutes_total: int = Field(alias="actualMinutesTotal")
    actual_duration_buckets: dict[str, int] = Field(alias="actualDurationBuckets")
    delay_attribution: dict[str, int] = Field(alias="delayAttribution")
    suggestions: list[str]
    tuning: SchedulingTuning


class DailyReviewPoint(APIModel):
    day: date
    started: int
    completed: int
    planned_minutes: int = Field(alias="plannedMinutes")
    actual_minutes: int = Field(alias="actualMinutes")


class MonthReviewReport(APIModel):
    month_start: date = Field(alias="monthStart")
    month_end: date = Field(alias="monthEnd")
    started_count: int = Field(alias="startedCount")
    completed_count: int = Field(alias="completedCount")
    completion_rate: float = Field(alias="completionRate")
    planned_minutes_total: int = Field(alias="plannedMinutesTotal")
    actual_minutes_total: int = Field(alias="actualMinutesTotal")
    actual_duration_buckets: dict[str, int] = Field(alias="actualDurationBuckets")
    bottleneck_attribution: dict[str, int] = Field(alias="bottleneckAttribution")
    weekly_completion_rate: dict[str, float] = Field(alias="weeklyCompletionRate")
    daily_trend: list[DailyReviewPoint] = Field(alias="dailyTrend")
    suggestions: list[str]


class TuningApplyRequest(APIModel):
    tuning: SchedulingTuning


def _validate_team_permission(value: str) -> str:
    allowed = {"none", "freeBusy", "details"}
    if value not in allowed:
        raise ValueError(f"permission must be one of: {', '.join(sorted(allowed))}")
    return value


class TeamMemberCalendar(APIModel):
    member_id: str = Field(alias="memberId")
    display_name: str = Field(alias="displayName")
    role: str
    energy: str
    permission: str
    busy: list[ScheduleEntryOut] = Field(default_factory=list)

    @field_validator("permission")
    @classmethod
    def validate_permission(cls, value: str) -> str:
        return _validate_team_permission(value)


class TeamPermissionUpdate(APIModel):
    permission: str

    @field_validator("permission")
    @classmethod
    def validate_permission(cls, value: str) -> str:
        return _validate_team_permission(value)


SchedulingRequest.model_rebuild()
CrystalRecommendationRequest.model_rebuild()
