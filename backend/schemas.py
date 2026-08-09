from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


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


class TeamTask(APIModel):
    name: str
    role: str
    task: str
    progress: float = 0.0
    is_high_energy: bool = Field(default=False, alias="isHighEnergy")
    due: datetime | None = None


class TeamMember(APIModel):
    name: str
    task: str
    progress: float
    is_high_energy: bool = Field(alias="isHighEnergy")
    busy_times: list["TimeRange"] = Field(default_factory=list, alias="busyTimes")


class UserProfile(APIModel):
    display_name: str = Field(alias="displayName")
    status: str


class EmotionCheckIn(APIModel):
    id: str
    at: datetime
    state: str
    note: str | None = None


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


class SchedulingIssue(APIModel):
    code: str
    message: str
    task_id: str | None = Field(default=None, alias="taskId")


class SchedulingPlan(APIModel):
    entries: list[ScheduleEntryOut]
    issues: list[SchedulingIssue] = Field(default_factory=list)


class TaskEventType:
    start = "start"
    complete = "complete"
    postpone = "postpone"
    interrupt = "interrupt"


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


class TeamSharePermission:
    none = "none"
    freeBusy = "freeBusy"
    details = "details"


class TeamMemberCalendar(APIModel):
    member_id: str = Field(alias="memberId")
    display_name: str = Field(alias="displayName")
    role: str
    energy: str
    permission: str
    busy: list[ScheduleEntryOut] = Field(default_factory=list)


class TeamConflict(APIModel):
    member_a: str = Field(alias="memberA")
    member_b: str = Field(alias="memberB")
    start: ClockTime
    end: ClockTime


class TeamMeetingRequest(APIModel):
    title: str
    start: ClockTime
    minutes: int
    participant_ids: list[str] = Field(default_factory=list, alias="participantIds")


class TimeRange(APIModel):
    start: ClockTime
    end: ClockTime

    @property
    def duration_minutes(self) -> int:
        return (self.end.hour * 60 + self.end.minute) - (self.start.hour * 60 + self.start.minute)

    def contains(self, time: ClockTime) -> bool:
        time_minutes = time.hour * 60 + time.minute
        start_minutes = self.start.hour * 60 + self.start.minute
        end_minutes = self.end.hour * 60 + self.end.minute
        return start_minutes <= time_minutes <= end_minutes


class UserAccount(APIModel):
    contact_address: str = Field(alias="contactAddress")
    display_name: str = Field(alias="displayName")


class EnergyTier:
    veryLow = "veryLow"
    low = "low"
    medium = "medium"
    high = "high"
    veryHigh = "veryHigh"


class CognitiveLoad:
    low = "low"
    medium = "medium"
    high = "high"


class EmotionState:
    efficient = "efficient"
    stable = "stable"
    tired = "tired"
    irritable = "irritable"


SchedulingRequest.model_rebuild()
CrystalRecommendationRequest.model_rebuild()
