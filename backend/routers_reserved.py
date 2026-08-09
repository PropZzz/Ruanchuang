from __future__ import annotations

from collections.abc import Callable

from fastapi import APIRouter, Depends, HTTPException, Request, status

from .auth import current_user_id


router = APIRouter(tags=["reserved"])


RESERVED_ENDPOINTS: tuple[tuple[str, str, str], ...] = (
    ("GET", "/diagnostics/summary", "Diagnostics summary"),
    ("GET", "/version", "Client compatibility version"),
    ("GET", "/server/time", "Server clock"),
    ("POST", "/auth/logout", "Logout"),
    ("POST", "/auth/refresh", "Refresh token"),
    ("PUT", "/auth/profile", "Update profile"),
    ("POST", "/auth/password/reset-request", "Password reset request"),
    ("POST", "/auth/password/reset-confirm", "Password reset confirmation"),
    ("POST", "/schedule/import-ics", "Import ICS schedule"),
    ("GET", "/schedule/export-ics", "Export ICS schedule"),
    ("GET", "/schedule/conflicts", "Schedule conflict summary"),
    ("POST", "/schedule/batch", "Batch schedule upsert"),
    ("POST", "/schedule/rescue/options", "Generate schedule rescue options"),
    ("POST", "/schedule/rescue/apply", "Apply schedule rescue option"),
    ("POST", "/schedule/rescue/undo", "Undo applied schedule rescue option"),
    ("GET", "/schedule/rescue/history", "Schedule rescue history"),
    ("DELETE", "/events/{event_id}", "Delete task event"),
    ("POST", "/microtasks/batch-complete", "Batch complete microtasks"),
    ("POST", "/microtasks/batch-schedule", "Batch schedule microtasks"),
    ("POST", "/microtasks/import", "Import microtask list"),
    ("GET", "/emotion/current", "Current emotion state"),
    ("POST", "/emotion/checkins", "Create emotion check-in"),
    ("GET", "/emotion/checkins", "List emotion check-ins"),
    ("GET", "/emotion/care-alert", "Emotion care alert"),
    ("GET", "/energy/current", "Current energy state"),
    ("POST", "/energy/samples", "Create energy sample"),
    ("GET", "/energy/profile", "Energy profile"),
    ("GET", "/goals", "List goals"),
    ("POST", "/goals", "Create goal"),
    ("PUT", "/goals/{goal_id}", "Update goal"),
    ("DELETE", "/goals/{goal_id}", "Delete goal"),
    ("POST", "/goals/{goal_id}/tasks", "Create goal task"),
    ("PUT", "/goals/{goal_id}/tasks/{task_id}", "Update goal task"),
    ("POST", "/goals/{goal_id}/schedule-next", "Schedule next goal task"),
    ("POST", "/goals/decompose", "Decompose goal with AI"),
    ("GET", "/team/members", "List team members"),
    ("POST", "/team/members", "Create team member"),
    ("PUT", "/team/members/{member_id}", "Update team member"),
    ("DELETE", "/team/members/{member_id}", "Delete team member"),
    ("PUT", "/team/members/{member_id}/permission", "Update team sharing permission"),
    ("GET", "/team/calendars", "List team calendars"),
    ("POST", "/team/conflicts", "Detect team conflicts"),
    ("POST", "/team/golden-windows", "Recommend team golden windows"),
    ("POST", "/team/book-meeting", "Book team meeting"),
    ("GET", "/reminders", "List reminders"),
    ("POST", "/reminders", "Create reminder"),
    ("PUT", "/reminders/{reminder_id}", "Update reminder"),
    ("DELETE", "/reminders/{reminder_id}", "Delete reminder"),
    ("POST", "/notifications/devices", "Register notification device"),
    ("DELETE", "/notifications/devices/{device_id}", "Unregister notification device"),
    ("POST", "/notifications/test", "Send test notification"),
    ("GET", "/devices", "List devices"),
    ("POST", "/devices", "Bind device"),
    ("DELETE", "/devices/{device_id}", "Unbind device"),
    ("POST", "/devices/{device_id}/samples", "Create device sample"),
    ("GET", "/devices/{device_id}/status", "Device status"),
    ("PUT", "/devices/{device_id}/permissions", "Update device permissions"),
    ("GET", "/integrations/providers", "List integration providers"),
    ("POST", "/integrations/{provider}/connect", "Connect integration provider"),
    ("POST", "/integrations/{provider}/callback", "Integration authorization callback"),
    ("DELETE", "/integrations/{provider}", "Disconnect integration provider"),
    ("POST", "/integrations/{provider}/import", "Import integration data"),
    ("GET", "/integrations/{provider}/sync-status", "Integration sync status"),
    ("POST", "/ai/parse-task", "Parse task with AI"),
    ("POST", "/ai/decompose-goal", "Decompose goal with AI"),
    ("POST", "/ai/explain-plan", "Explain plan with AI"),
    ("POST", "/ai/review-suggestions", "Generate review suggestions with AI"),
    ("POST", "/ai/tuning", "Generate scheduling tuning with AI"),
    ("POST", "/files/upload", "Upload file"),
    ("GET", "/files/{file_id}", "Download file"),
    ("DELETE", "/files/{file_id}", "Delete file"),
    ("POST", "/files/parse-task-list", "Parse task list from file"),
    ("GET", "/sync/pull", "Pull sync changes"),
    ("POST", "/sync/push", "Push sync changes"),
    ("GET", "/sync/status", "Sync status"),
    ("POST", "/sync/conflicts/{conflict_id}/resolve", "Resolve sync conflict"),
)


def _reserved_detail(summary: str, request: Request) -> dict[str, object]:
    return {
        "code": "RESERVED_ENDPOINT",
        "message": f"{summary} is reserved for a later implementation.",
        "status": "Reserved",
        "path": request.url.path,
    }


def _reserved_handler(summary: str) -> Callable[..., None]:
    def handler(
        request: Request,
        user_id: str = Depends(current_user_id),
    ) -> None:
        del user_id
        raise HTTPException(
            status_code=status.HTTP_501_NOT_IMPLEMENTED,
            detail=_reserved_detail(summary, request),
        )

    handler.__name__ = "reserved_" + "".join(
        char if char.isalnum() else "_" for char in summary.lower()
    )
    return handler


for method, path, summary in RESERVED_ENDPOINTS:
    router.add_api_route(
        path,
        _reserved_handler(summary),
        methods=[method],
        summary=f"[Reserved] {summary}",
    )
