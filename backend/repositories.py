from __future__ import annotations

from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import sqlite3
import uuid

from .database import get_connection
from .services_rescue import build_rescue_event, compute_baseline_hash


class TaskEventConflictError(Exception):
    pass


class TaskEventBatchValidationError(ValueError):
    pass


class RepositoryConflictError(ValueError):
    pass


class RepositoryNotFoundError(LookupError):
    pass


class RepositoryValidationError(ValueError):
    pass


def _now() -> str:
    return datetime.utcnow().isoformat(timespec="seconds")


def _parse_date(value: object) -> str | None:
    if value is None:
        return None
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, str):
        text = value.strip()
        return text or None
    return None


def _parse_time(value: object) -> tuple[int, int]:
    if isinstance(value, dict):
        hour_raw = value.get("hour", 0)
        minute_raw = value.get("minute", 0)
        hour = int(hour_raw) if hour_raw is not None else 0
        minute = int(minute_raw) if minute_raw is not None else 0
        return hour, minute
    return 0, 0


def _first_non_none(payload: dict[str, object], *keys: str, default: object | None = None) -> object | None:
    for key in keys:
        if key in payload and payload[key] is not None:
            return payload[key]
    return default


def _parse_int(value: object | None, default: int) -> int:
    if value is None:
        return default
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return default
        try:
            return int(text)
        except ValueError:
            return default
    return default


def _parse_float(value: object | None, default: float) -> float:
    if value is None:
        return default
    if isinstance(value, bool):
        return float(int(value))
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        text = value.strip()
        if not text:
            return default
        try:
            return float(text)
        except ValueError:
            return default
    return default


def _parse_bool(value: object | None, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        text = value.strip().lower()
        if text in {"true", "1", "yes", "y", "on"}:
            return True
        if text in {"false", "0", "no", "n", "off", ""}:
            return False
    return bool(value)


def _password_salt() -> str:
    return uuid.uuid4().hex


def _password_hash(password: str, salt: str) -> str:
    digest = hashlib.sha256()
    digest.update(f"{salt}:{password}".encode("utf-8"))
    return digest.hexdigest()


def _connect(db_path: str | Path | None = None) -> sqlite3.Connection:
    connection = get_connection(db_path)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    init_db(db_path, connection)
    return connection


def init_db(db_path: str | Path | None = None, connection: sqlite3.Connection | None = None) -> None:
    owns_connection = connection is None
    if connection is None:
        connection = get_connection(db_path)
        connection.row_factory = sqlite3.Row

    try:
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                contact_address TEXT NOT NULL UNIQUE,
                display_name TEXT NOT NULL,
                password_salt TEXT NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schedules (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                day TEXT,
                title TEXT NOT NULL,
                tag TEXT NOT NULL,
                load TEXT,
                goal_id TEXT,
                goal_task_id TEXT,
                height REAL NOT NULL,
                color INTEGER NOT NULL,
                time_hour INTEGER NOT NULL,
                time_minute INTEGER NOT NULL,
                reminder_minutes_before INTEGER NOT NULL,
                repeat TEXT NOT NULL,
                repeat_until TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS microtasks (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                tag TEXT NOT NULL,
                minutes INTEGER NOT NULL,
                priority INTEGER NOT NULL,
                requirement TEXT,
                done INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS task_events (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                task_id TEXT NOT NULL,
                title TEXT NOT NULL,
                tag TEXT NOT NULL,
                load TEXT,
                at TEXT NOT NULL,
                type TEXT NOT NULL,
                planned_minutes INTEGER,
                energy TEXT,
                actual_minutes INTEGER,
                interruptions INTEGER,
                reason TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS settings (
                user_id TEXT PRIMARY KEY,
                scheduling_tuning_json TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS emotion_checkins (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                at TEXT NOT NULL,
                state TEXT NOT NULL,
                note TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS energy_samples (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                at TEXT NOT NULL,
                level TEXT NOT NULL,
                status TEXT NOT NULL,
                description TEXT NOT NULL,
                battery_percent INTEGER NOT NULL,
                emotion TEXT NOT NULL,
                flow_state TEXT NOT NULL,
                source TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS goals (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                due TEXT NOT NULL,
                priority INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS goal_tasks (
                id TEXT PRIMARY KEY,
                goal_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                title TEXT NOT NULL,
                duration_minutes INTEGER NOT NULL,
                load TEXT NOT NULL,
                tag TEXT NOT NULL,
                done INTEGER NOT NULL,
                depends_on_json TEXT NOT NULL,
                position INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(goal_id) REFERENCES goals(id) ON DELETE CASCADE,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS team_members (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                role TEXT NOT NULL,
                energy TEXT NOT NULL,
                permission TEXT NOT NULL,
                busy_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS rescue_snapshots (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                day TEXT NOT NULL,
                strategy TEXT NOT NULL,
                baseline_hash TEXT NOT NULL,
                urgent_json TEXT,
                before_json TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'active',
                created_at TEXT NOT NULL,
                undone_at TEXT,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
            )
            """
        )
        connection.commit()
    finally:
        if owns_connection:
            connection.close()


def _row_to_dict(row: sqlite3.Row | None) -> dict[str, object] | None:
    if row is None:
        return None
    return dict(row)


def create_user(
    db_path: str | Path | None,
    contact_address: str,
    display_name: str,
    password: str,
) -> dict[str, object]:
    with _connect(db_path) as connection:
        existing = connection.execute(
            "SELECT id FROM users WHERE contact_address = ?",
            (contact_address,),
        ).fetchone()
        if existing is not None:
            raise ValueError("user already exists")

        user_id = uuid.uuid4().hex
        salt = _password_salt()
        password_hash = _password_hash(password, salt)
        now = _now()
        connection.execute(
            """
            INSERT INTO users (id, contact_address, display_name, password_salt, password_hash, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (user_id, contact_address, display_name, salt, password_hash, now, now),
        )
        connection.execute(
            """
            INSERT INTO settings (user_id, scheduling_tuning_json, updated_at)
            VALUES (?, ?, ?)
            """,
            (user_id, json.dumps(default_scheduling_tuning()), now),
        )
        connection.commit()
        return {
            "id": user_id,
            "contactAddress": contact_address,
            "displayName": display_name,
            "passwordSalt": salt,
            "passwordHash": password_hash,
        }


def find_user_by_account(db_path: str | Path | None, contact_address: str) -> dict[str, object] | None:
    with _connect(db_path) as connection:
        row = connection.execute(
            """
            SELECT
                id,
                contact_address AS contactAddress,
                display_name AS displayName,
                password_salt AS passwordSalt,
                password_hash AS passwordHash
            FROM users
            WHERE contact_address = ?
            """,
            (contact_address,),
        ).fetchone()
        return _row_to_dict(row)


def find_user_by_id(db_path: str | Path | None, user_id: str) -> dict[str, object] | None:
    with _connect(db_path) as connection:
        row = connection.execute(
            """
            SELECT
                id,
                contact_address AS contactAddress,
                display_name AS displayName,
                password_salt AS passwordSalt,
                password_hash AS passwordHash
            FROM users
            WHERE id = ?
            """,
            (user_id,),
        ).fetchone()
        return _row_to_dict(row)


def verify_user(db_path: str | Path | None, contact_address: str, password: str) -> dict[str, object] | None:
    user = find_user_by_account(db_path, contact_address)
    if user is None:
        return None
    expected = _password_hash(password, str(user["passwordSalt"]))
    if expected != user["passwordHash"]:
        return None
    return user


def _schedule_row_to_dict(row: sqlite3.Row) -> dict[str, object]:
    return {
        "id": row["id"],
        "day": row["day"],
        "title": row["title"],
        "tag": row["tag"],
        "load": row["load"],
        "goalId": row["goal_id"],
        "goalTaskId": row["goal_task_id"],
        "height": row["height"],
        "color": row["color"],
        "time": {"hour": row["time_hour"], "minute": row["time_minute"]},
        "reminderMinutesBefore": row["reminder_minutes_before"],
        "repeat": row["repeat"],
        "repeatUntil": row["repeat_until"],
    }


def _normalize_schedule_values(
    payload: dict[str, object],
) -> tuple[object, ...]:
    schedule_id = str(_first_non_none(payload, "id", default=uuid.uuid4().hex))
    day = _parse_date(payload.get("day"))
    title = str(_first_non_none(payload, "title", default=""))
    tag = str(_first_non_none(payload, "tag", default=""))
    load_value = _first_non_none(payload, "load")
    load = None if load_value is None else str(load_value)
    goal_id_value = _first_non_none(payload, "goalId", "goal_id")
    goal_task_id_value = _first_non_none(payload, "goalTaskId", "goal_task_id")
    goal_id = None if goal_id_value is None else str(goal_id_value)
    goal_task_id = None if goal_task_id_value is None else str(goal_task_id_value)
    height = _parse_float(_first_non_none(payload, "height", default=60.0), 60.0)
    color = _parse_int(_first_non_none(payload, "color", default=0), 0)
    hour, minute = _parse_time(payload.get("time") or {})
    reminder_minutes_before = _parse_int(
        _first_non_none(payload, "reminderMinutesBefore", "reminder_minutes_before", default=10),
        10,
    )
    repeat = str(_first_non_none(payload, "repeat", default="none"))
    repeat_until = _parse_date(_first_non_none(payload, "repeatUntil", "repeat_until"))
    return (
        schedule_id,
        day,
        title,
        tag,
        load,
        goal_id,
        goal_task_id,
        height,
        color,
        hour,
        minute,
        reminder_minutes_before,
        repeat,
        repeat_until,
    )


def upsert_schedule(db_path: str | Path | None, user_id: str, payload: dict[str, object]) -> dict[str, object]:
    (
        schedule_id,
        day,
        title,
        tag,
        load,
        goal_id,
        goal_task_id,
        height,
        color,
        hour,
        minute,
        reminder_minutes_before,
        repeat,
        repeat_until,
    ) = _normalize_schedule_values(payload)
    now = _now()

    with _connect(db_path) as connection:
        existing = connection.execute(
            "SELECT id FROM schedules WHERE id = ? AND user_id = ?",
            (schedule_id, user_id),
        ).fetchone()
        if existing is None:
            connection.execute(
                """
                INSERT INTO schedules (
                    id, user_id, day, title, tag, load, goal_id, goal_task_id, height, color,
                    time_hour, time_minute, reminder_minutes_before, repeat, repeat_until,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    schedule_id,
                    user_id,
                    day,
                    title,
                    tag,
                    load,
                    goal_id,
                    goal_task_id,
                    height,
                    color,
                    hour,
                    minute,
                    reminder_minutes_before,
                    repeat,
                    repeat_until,
                    now,
                    now,
                ),
            )
        else:
            connection.execute(
                """
                UPDATE schedules
                SET day = ?, title = ?, tag = ?, load = ?, goal_id = ?, goal_task_id = ?, height = ?,
                    color = ?, time_hour = ?, time_minute = ?, reminder_minutes_before = ?, repeat = ?,
                    repeat_until = ?, updated_at = ?
                WHERE id = ? AND user_id = ?
                """,
                (
                    day,
                    title,
                    tag,
                    load,
                    goal_id,
                    goal_task_id,
                    height,
                    color,
                    hour,
                    minute,
                    reminder_minutes_before,
                    repeat,
                    repeat_until,
                    now,
                    schedule_id,
                    user_id,
                ),
            )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM schedules WHERE id = ? AND user_id = ?",
            (schedule_id, user_id),
        ).fetchone()
        return _schedule_row_to_dict(row)


def list_schedules(db_path: str | Path | None, user_id: str) -> list[dict[str, object]]:
    with _connect(db_path) as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM schedules
            WHERE user_id = ?
            ORDER BY
                CASE WHEN day IS NULL THEN 1 ELSE 0 END,
                day,
                time_hour,
                time_minute,
                updated_at DESC,
                id DESC
            """,
            (user_id,),
        ).fetchall()
        return [_schedule_row_to_dict(row) for row in rows]


def delete_schedule(db_path: str | Path | None, user_id: str, schedule_id: str) -> None:
    with _connect(db_path) as connection:
        connection.execute(
            "DELETE FROM schedules WHERE id = ? AND user_id = ?",
            (schedule_id, user_id),
        )
        connection.commit()


def _microtask_row_to_dict(row: sqlite3.Row) -> dict[str, object]:
    return {
        "id": row["id"],
        "title": row["title"],
        "tag": row["tag"],
        "minutes": row["minutes"],
        "priority": row["priority"],
        "requirement": row["requirement"],
        "done": bool(row["done"]),
    }


def upsert_microtask(db_path: str | Path | None, user_id: str, payload: dict[str, object]) -> dict[str, object]:
    microtask_id = str(_first_non_none(payload, "id", default=uuid.uuid4().hex))
    title = str(_first_non_none(payload, "title", default=""))
    tag = str(_first_non_none(payload, "tag", default=""))
    minutes = _parse_int(_first_non_none(payload, "minutes", default=0), 0)
    priority = _parse_int(_first_non_none(payload, "priority", default=3), 3)
    priority = max(1, min(5, priority))
    requirement_value = _first_non_none(payload, "requirement")
    requirement = None if requirement_value is None else str(requirement_value)
    done = 1 if _parse_bool(_first_non_none(payload, "done", default=False), False) else 0
    now = _now()

    with _connect(db_path) as connection:
        existing = connection.execute(
            "SELECT id FROM microtasks WHERE id = ? AND user_id = ?",
            (microtask_id, user_id),
        ).fetchone()
        if existing is None:
            connection.execute(
                """
                INSERT INTO microtasks (
                    id, user_id, title, tag, minutes, priority, requirement, done, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (microtask_id, user_id, title, tag, minutes, priority, requirement, done, now, now),
            )
        else:
            connection.execute(
                """
                UPDATE microtasks
                SET title = ?, tag = ?, minutes = ?, priority = ?, requirement = ?, done = ?, updated_at = ?
                WHERE id = ? AND user_id = ?
                """,
                (title, tag, minutes, priority, requirement, done, now, microtask_id, user_id),
            )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM microtasks WHERE id = ? AND user_id = ?",
            (microtask_id, user_id),
        ).fetchone()
        return _microtask_row_to_dict(row)


def list_microtasks(db_path: str | Path | None, user_id: str) -> list[dict[str, object]]:
    with _connect(db_path) as connection:
        rows = connection.execute(
            """
            SELECT *
            FROM microtasks
            WHERE user_id = ?
            ORDER BY done ASC, priority DESC, updated_at DESC, id DESC
            """,
            (user_id,),
        ).fetchall()
        return [_microtask_row_to_dict(row) for row in rows]


def delete_microtask(db_path: str | Path | None, user_id: str, microtask_id: str) -> None:
    with _connect(db_path) as connection:
        connection.execute(
            "DELETE FROM microtasks WHERE id = ? AND user_id = ?",
            (microtask_id, user_id),
        )
        connection.commit()


def _task_event_row_to_dict(row: sqlite3.Row | None) -> dict[str, object] | None:
    if row is None:
        return None
    return {
        "id": row["id"],
        "taskId": row["task_id"],
        "title": row["title"],
        "tag": row["tag"],
        "load": row["load"],
        "at": row["at"],
        "type": row["type"],
        "plannedMinutes": row["planned_minutes"],
        "energy": row["energy"],
        "actualMinutes": row["actual_minutes"],
        "interruptions": row["interruptions"],
        "reason": row["reason"],
    }


_TASK_EVENT_UPSERT_SQL = """
    INSERT INTO task_events (
        id, user_id, task_id, title, tag, load, at, type,
        planned_minutes, energy, actual_minutes, interruptions,
        reason, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
        task_id = excluded.task_id,
        title = excluded.title,
        tag = excluded.tag,
        load = excluded.load,
        at = excluded.at,
        type = excluded.type,
        planned_minutes = excluded.planned_minutes,
        energy = excluded.energy,
        actual_minutes = excluded.actual_minutes,
        interruptions = excluded.interruptions,
        reason = excluded.reason
    WHERE task_events.user_id = excluded.user_id
    """


def _task_event_values(
    payload: dict[str, object],
    now: str,
) -> tuple[object, ...]:
    return (
        str(payload.get("id") or uuid.uuid4()),
        str(_first_non_none(payload, "taskId", "task_id", default="")),
        str(payload.get("title") or ""),
        str(payload.get("tag") or ""),
        _first_non_none(payload, "load"),
        str(payload.get("at") or now),
        str(payload.get("type") or "start"),
        _parse_int(_first_non_none(payload, "plannedMinutes", "planned_minutes"), 0),
        _first_non_none(payload, "energy"),
        _first_non_none(payload, "actualMinutes", "actual_minutes"),
        _first_non_none(payload, "interruptions"),
        _first_non_none(payload, "reason"),
        now,
    )


def _upsert_task_event_on_connection(
    connection: sqlite3.Connection,
    user_id: str,
    payload: dict[str, object],
    now: str,
) -> str:
    values = _task_event_values(payload, now)
    event_id = str(values[0])
    existing = connection.execute(
        "SELECT user_id FROM task_events WHERE id = ?",
        (event_id,),
    ).fetchone()
    if existing is not None and existing["user_id"] != user_id:
        raise TaskEventConflictError(f"Task event id already belongs to another user: {event_id}")

    connection.execute(
        _TASK_EVENT_UPSERT_SQL,
        (event_id, user_id, *values[1:]),
    )
    stored = connection.execute(
        "SELECT user_id FROM task_events WHERE id = ?",
        (event_id,),
    ).fetchone()
    if stored is None or stored["user_id"] != user_id:
        raise TaskEventConflictError(f"Task event id already belongs to another user: {event_id}")
    return event_id


def upsert_task_event(
    db_path: str | Path | None,
    user_id: str,
    payload: dict[str, object],
) -> dict[str, object]:
    with _connect(db_path) as connection:
        event_id = _upsert_task_event_on_connection(
            connection,
            user_id,
            payload,
            _now(),
        )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM task_events WHERE id = ? AND user_id = ?",
            (event_id, user_id),
        ).fetchone()
        return _task_event_row_to_dict(row) or {}


def upsert_task_events(
    db_path: str | Path | None,
    user_id: str,
    payloads: list[dict[str, object]],
) -> list[dict[str, object]]:
    seen_ids: set[str] = set()
    for payload in payloads:
        event_id = str(payload.get("id") or "")
        if not event_id.strip():
            raise TaskEventBatchValidationError("Task event IDs must not be blank.")
        if event_id in seen_ids:
            raise TaskEventBatchValidationError(
                f"Duplicate task event id in batch: {event_id}"
            )
        seen_ids.add(event_id)

    with _connect(db_path) as connection:
        for event_id in seen_ids:
            existing = connection.execute(
                "SELECT user_id FROM task_events WHERE id = ?",
                (event_id,),
            ).fetchone()
            if existing is not None and existing["user_id"] != user_id:
                raise TaskEventConflictError(
                    f"Task event id already belongs to another user: {event_id}"
                )

        event_ids = [
            _upsert_task_event_on_connection(connection, user_id, payload, _now())
            for payload in payloads
        ]
        connection.commit()
        return [
            _task_event_row_to_dict(
                connection.execute(
                    "SELECT * FROM task_events WHERE id = ? AND user_id = ?",
                    (event_id, user_id),
                ).fetchone()
            )
            or {}
            for event_id in event_ids
        ]


def list_task_events(
    db_path: str | Path | None,
    user_id: str,
    from_at: str | None = None,
    to_at: str | None = None,
) -> list[dict[str, object]]:
    clauses = ["user_id = ?"]
    params: list[object] = [user_id]
    if from_at is not None:
        clauses.append("at >= ?")
        params.append(from_at)
    if to_at is not None:
        clauses.append("at < ?")
        params.append(to_at)

    with _connect(db_path) as connection:
        rows = connection.execute(
            f"""
            SELECT * FROM task_events
            WHERE {' AND '.join(clauses)}
            ORDER BY at ASC, id ASC
            """,
            params,
        ).fetchall()
        return [_task_event_row_to_dict(row) or {} for row in rows]


def default_scheduling_tuning() -> dict[str, object]:
    return {
        "defaultDurationMultiplier": 1.0,
        "tagDurationMultiplier": {},
        "highLoadPenaltyWhenLowEnergy": 1.0,
    }


def get_scheduling_tuning(
    db_path: str | Path | None,
    user_id: str,
) -> dict[str, object]:
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT scheduling_tuning_json FROM settings WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        if row is None:
            return default_scheduling_tuning()
        try:
            raw = json.loads(row["scheduling_tuning_json"])
        except json.JSONDecodeError:
            return default_scheduling_tuning()
        if not isinstance(raw, dict):
            return default_scheduling_tuning()
        return {
            **default_scheduling_tuning(),
            **raw,
            "tagDurationMultiplier": raw.get("tagDurationMultiplier") or {},
        }


def set_scheduling_tuning(
    db_path: str | Path | None,
    user_id: str,
    tuning: dict[str, object],
) -> dict[str, object]:
    normalized = {
        "defaultDurationMultiplier": _parse_float(
            _first_non_none(tuning, "defaultDurationMultiplier", "default_duration_multiplier", default=1.0),
            1.0,
        ),
        "tagDurationMultiplier": tuning.get("tagDurationMultiplier")
        if isinstance(tuning.get("tagDurationMultiplier"), dict)
        else {},
        "highLoadPenaltyWhenLowEnergy": _parse_float(
            _first_non_none(
                tuning,
                "highLoadPenaltyWhenLowEnergy",
                "high_load_penalty_when_low_energy",
                default=1.0,
            ),
            1.0,
        ),
    }
    normalized["tagDurationMultiplier"] = {
        str(key): _parse_float(value, 1.0)
        for key, value in dict(normalized["tagDurationMultiplier"]).items()
    }
    now = _now()
    with _connect(db_path) as connection:
        connection.execute(
            """
            INSERT INTO settings (user_id, scheduling_tuning_json, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                scheduling_tuning_json = excluded.scheduling_tuning_json,
                updated_at = excluded.updated_at
            """,
            (user_id, json.dumps(normalized, ensure_ascii=False), now),
        )
        connection.commit()
    return normalized


def _iso_day(value: object | None) -> str:
    if isinstance(value, datetime):
        return value.date().isoformat()
    text = str(value or "").strip()
    if "T" in text:
        return text.split("T", 1)[0]
    if len(text) >= 10:
        return text[:10]
    return text


def _check_global_owner(
    connection: sqlite3.Connection,
    table: str,
    item_id: str,
    user_id: str,
    label: str,
) -> sqlite3.Row | None:
    row = connection.execute(
        f"SELECT user_id FROM {table} WHERE id = ?",
        (item_id,),
    ).fetchone()
    if row is not None and row["user_id"] != user_id:
        raise RepositoryConflictError(f"{label} id already belongs to another user: {item_id}")
    return row


def _emotion_row_to_dict(row: sqlite3.Row | None) -> dict[str, object] | None:
    if row is None:
        return None
    return {
        "id": row["id"],
        "at": row["at"],
        "state": row["state"],
        "note": row["note"],
    }


def default_emotion_status() -> dict[str, object]:
    return {
        "id": None,
        "at": None,
        "state": "stable",
        "note": "No emotion check-in yet; using stable default.",
    }


def upsert_emotion_checkin(
    db_path: str | Path | None,
    user_id: str,
    payload: dict[str, object],
) -> dict[str, object]:
    checkin_id = str(payload.get("id") or uuid.uuid4().hex)
    at = str(payload.get("at") or _now())
    state = str(payload.get("state") or "stable")
    note_value = payload.get("note")
    note = None if note_value is None else str(note_value)
    day = _iso_day(at)
    now = _now()

    with _connect(db_path) as connection:
        _check_global_owner(connection, "emotion_checkins", checkin_id, user_id, "Emotion check-in")
        connection.execute(
            """
            DELETE FROM emotion_checkins
            WHERE user_id = ? AND substr(at, 1, 10) = ? AND id <> ?
            """,
            (user_id, day, checkin_id),
        )
        connection.execute(
            """
            INSERT INTO emotion_checkins (id, user_id, at, state, note, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                at = excluded.at,
                state = excluded.state,
                note = excluded.note,
                updated_at = excluded.updated_at
            WHERE emotion_checkins.user_id = excluded.user_id
            """,
            (checkin_id, user_id, at, state, note, now, now),
        )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM emotion_checkins WHERE id = ? AND user_id = ?",
            (checkin_id, user_id),
        ).fetchone()
        return _emotion_row_to_dict(row) or default_emotion_status()


def list_emotion_checkins(
    db_path: str | Path | None,
    user_id: str,
    day: str,
) -> list[dict[str, object]]:
    with _connect(db_path) as connection:
        rows = connection.execute(
            """
            SELECT * FROM emotion_checkins
            WHERE user_id = ? AND substr(at, 1, 10) = ?
            ORDER BY at ASC, id ASC
            """,
            (user_id, day),
        ).fetchall()
        return [_emotion_row_to_dict(row) or {} for row in rows]


def get_current_emotion(
    db_path: str | Path | None,
    user_id: str,
) -> dict[str, object]:
    with _connect(db_path) as connection:
        row = connection.execute(
            """
            SELECT * FROM emotion_checkins
            WHERE user_id = ?
            ORDER BY at DESC, updated_at DESC, id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        return _emotion_row_to_dict(row) or default_emotion_status()


def get_latest_emotion_for_day(
    db_path: str | Path | None,
    user_id: str,
    day: str,
) -> dict[str, object] | None:
    with _connect(db_path) as connection:
        row = connection.execute(
            """
            SELECT * FROM emotion_checkins
            WHERE user_id = ? AND substr(at, 1, 10) = ?
            ORDER BY at DESC, updated_at DESC, id DESC
            LIMIT 1
            """,
            (user_id, day),
        ).fetchone()
        return _emotion_row_to_dict(row)


def _energy_row_to_dict(row: sqlite3.Row | None) -> dict[str, object] | None:
    if row is None:
        return None
    return {
        "id": row["id"],
        "at": row["at"],
        "level": row["level"],
        "status": row["status"],
        "description": row["description"],
        "batteryPercent": row["battery_percent"],
        "emotion": row["emotion"],
        "flowState": row["flow_state"],
        "source": row["source"],
    }


def default_energy_status() -> dict[str, object]:
    return {
        "id": None,
        "at": None,
        "level": "medium",
        "status": "flow",
        "description": "No recent energy sample; using balanced default.",
        "batteryPercent": 85,
        "emotion": "stable",
        "flowState": "normal",
        "source": "default",
    }


def upsert_energy_sample(
    db_path: str | Path | None,
    user_id: str,
    payload: dict[str, object],
) -> dict[str, object]:
    sample_id = str(payload.get("id") or uuid.uuid4().hex)
    at = str(payload.get("at") or _now())
    level = str(payload.get("level") or "medium")
    status_value = str(payload.get("status") or "flow")
    description = str(payload.get("description") or "")
    battery_percent = _parse_int(
        _first_non_none(payload, "batteryPercent", "battery_percent", default=85),
        85,
    )
    emotion = str(payload.get("emotion") or "stable")
    flow_state = str(_first_non_none(payload, "flowState", "flow_state", default="normal"))
    source = str(payload.get("source") or "manual")
    now = _now()

    with _connect(db_path) as connection:
        _check_global_owner(connection, "energy_samples", sample_id, user_id, "Energy sample")
        connection.execute(
            """
            INSERT INTO energy_samples (
                id, user_id, at, level, status, description, battery_percent,
                emotion, flow_state, source, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                at = excluded.at,
                level = excluded.level,
                status = excluded.status,
                description = excluded.description,
                battery_percent = excluded.battery_percent,
                emotion = excluded.emotion,
                flow_state = excluded.flow_state,
                source = excluded.source,
                updated_at = excluded.updated_at
            WHERE energy_samples.user_id = excluded.user_id
            """,
            (
                sample_id,
                user_id,
                at,
                level,
                status_value,
                description,
                battery_percent,
                emotion,
                flow_state,
                source,
                now,
                now,
            ),
        )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM energy_samples WHERE id = ? AND user_id = ?",
            (sample_id, user_id),
        ).fetchone()
        return _energy_row_to_dict(row) or default_energy_status()


def get_current_energy(
    db_path: str | Path | None,
    user_id: str,
) -> dict[str, object]:
    with _connect(db_path) as connection:
        row = connection.execute(
            """
            SELECT * FROM energy_samples
            WHERE user_id = ?
            ORDER BY at DESC, updated_at DESC, id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        return _energy_row_to_dict(row) or default_energy_status()


def get_energy_profile(
    db_path: str | Path | None,
    user_id: str,
) -> dict[str, object]:
    with _connect(db_path) as connection:
        aggregate = connection.execute(
            """
            SELECT COUNT(*) AS sample_count, AVG(battery_percent) AS average_battery_percent
            FROM energy_samples
            WHERE user_id = ?
            """,
            (user_id,),
        ).fetchone()
        latest = connection.execute(
            """
            SELECT level FROM energy_samples
            WHERE user_id = ?
            ORDER BY at DESC, updated_at DESC, id DESC
            LIMIT 1
            """,
            (user_id,),
        ).fetchone()
        count = int(aggregate["sample_count"] if aggregate else 0)
        average = aggregate["average_battery_percent"] if aggregate else None
        return {
            "sampleCount": count,
            "latestLevel": latest["level"] if latest is not None else "medium",
            "averageBatteryPercent": int(round(float(average))) if average is not None else 85,
        }


def _depends_on_list(value: object | None) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if str(item).strip()]


def _goal_task_row_to_dict(row: sqlite3.Row) -> dict[str, object]:
    try:
        depends_on_raw = json.loads(row["depends_on_json"])
    except json.JSONDecodeError:
        depends_on_raw = []
    return {
        "id": row["id"],
        "title": row["title"],
        "durationMinutes": row["duration_minutes"],
        "load": row["load"],
        "tag": row["tag"],
        "done": bool(row["done"]),
        "dependsOn": _depends_on_list(depends_on_raw),
    }


def _list_goal_tasks_on_connection(
    connection: sqlite3.Connection,
    user_id: str,
    goal_id: str,
) -> list[dict[str, object]]:
    rows = connection.execute(
        """
        SELECT * FROM goal_tasks
        WHERE user_id = ? AND goal_id = ?
        ORDER BY position ASC, created_at ASC, id ASC
        """,
        (user_id, goal_id),
    ).fetchall()
    return [_goal_task_row_to_dict(row) for row in rows]


def _goal_row_to_dict(
    connection: sqlite3.Connection,
    row: sqlite3.Row,
) -> dict[str, object]:
    return {
        "id": row["id"],
        "title": row["title"],
        "due": row["due"],
        "priority": row["priority"],
        "tasks": _list_goal_tasks_on_connection(connection, row["user_id"], row["id"]),
    }


def _normalize_goal_task_payload(payload: dict[str, object], task_id: str | None = None) -> dict[str, object]:
    resolved_id = str(task_id or payload.get("id") or uuid.uuid4().hex)
    return {
        "id": resolved_id,
        "title": str(payload.get("title") or ""),
        "durationMinutes": _parse_int(
            _first_non_none(payload, "durationMinutes", "duration_minutes", default=30),
            30,
        ),
        "load": str(payload.get("load") or "medium"),
        "tag": str(payload.get("tag") or "Goal"),
        "done": _parse_bool(payload.get("done"), False),
        "dependsOn": _depends_on_list(_first_non_none(payload, "dependsOn", "depends_on", default=[])),
    }


def _validate_goal_tasks(tasks: list[dict[str, object]]) -> None:
    ids = [str(task["id"]) for task in tasks]
    if len(ids) != len(set(ids)):
        raise RepositoryValidationError("Goal task IDs must be unique within a goal.")
    id_set = set(ids)
    graph: dict[str, list[str]] = {}
    for task in tasks:
        task_id = str(task["id"])
        deps = _depends_on_list(task.get("dependsOn"))
        if task_id in deps:
            raise RepositoryValidationError("Goal task cannot depend on itself.")
        missing = [dep for dep in deps if dep not in id_set]
        if missing:
            raise RepositoryValidationError(f"Goal task depends on missing task: {missing[0]}")
        graph[task_id] = deps

    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(node: str) -> None:
        if node in visiting:
            raise RepositoryValidationError("Goal task dependencies must not contain cycles.")
        if node in visited:
            return
        visiting.add(node)
        for dep in graph.get(node, []):
            visit(dep)
        visiting.remove(node)
        visited.add(node)

    for task_id in ids:
        visit(task_id)


def _insert_goal_tasks(
    connection: sqlite3.Connection,
    user_id: str,
    goal_id: str,
    tasks: list[dict[str, object]],
    now: str,
    *,
    validate: bool = True,
    start_position: int = 0,
) -> None:
    if validate:
        _validate_goal_tasks(tasks)
    for offset, task in enumerate(tasks):
        position = start_position + offset
        task_id = str(task["id"])
        existing = connection.execute(
            "SELECT user_id, goal_id FROM goal_tasks WHERE id = ?",
            (task_id,),
        ).fetchone()
        if existing is not None and (
            existing["user_id"] != user_id or existing["goal_id"] != goal_id
        ):
            raise RepositoryConflictError(f"Goal task id already exists: {task_id}")
        connection.execute(
            """
            INSERT INTO goal_tasks (
                id, goal_id, user_id, title, duration_minutes, load, tag, done,
                depends_on_json, position, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                duration_minutes = excluded.duration_minutes,
                load = excluded.load,
                tag = excluded.tag,
                done = excluded.done,
                depends_on_json = excluded.depends_on_json,
                position = excluded.position,
                updated_at = excluded.updated_at
            WHERE goal_tasks.user_id = excluded.user_id AND goal_tasks.goal_id = excluded.goal_id
            """,
            (
                task_id,
                goal_id,
                user_id,
                str(task.get("title") or ""),
                _parse_int(task.get("durationMinutes"), 30),
                str(task.get("load") or "medium"),
                str(task.get("tag") or "Goal"),
                1 if _parse_bool(task.get("done"), False) else 0,
                json.dumps(_depends_on_list(task.get("dependsOn")), ensure_ascii=False),
                position,
                now,
                now,
            ),
        )


def list_goals(db_path: str | Path | None, user_id: str) -> list[dict[str, object]]:
    with _connect(db_path) as connection:
        rows = connection.execute(
            """
            SELECT * FROM goals
            WHERE user_id = ?
            ORDER BY priority DESC, due ASC, updated_at DESC, id ASC
            """,
            (user_id,),
        ).fetchall()
        return [_goal_row_to_dict(connection, row) for row in rows]


def upsert_goal(
    db_path: str | Path | None,
    user_id: str,
    payload: dict[str, object],
) -> dict[str, object]:
    goal_id = str(payload.get("id") or uuid.uuid4().hex)
    title = str(payload.get("title") or "")
    due = str(payload.get("due") or _now())
    priority = max(1, min(5, _parse_int(payload.get("priority"), 3)))
    tasks_payload = payload.get("tasks")
    tasks = [
        _normalize_goal_task_payload(dict(task))
        for task in tasks_payload
        if isinstance(task, dict)
    ] if isinstance(tasks_payload, list) else []
    now = _now()

    with _connect(db_path) as connection:
        _check_global_owner(connection, "goals", goal_id, user_id, "Goal")
        connection.execute(
            """
            INSERT INTO goals (id, user_id, title, due, priority, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title,
                due = excluded.due,
                priority = excluded.priority,
                updated_at = excluded.updated_at
            WHERE goals.user_id = excluded.user_id
            """,
            (goal_id, user_id, title, due, priority, now, now),
        )
        connection.execute(
            "DELETE FROM goal_tasks WHERE goal_id = ? AND user_id = ?",
            (goal_id, user_id),
        )
        _insert_goal_tasks(connection, user_id, goal_id, tasks, now)
        connection.commit()
        row = connection.execute(
            "SELECT * FROM goals WHERE id = ? AND user_id = ?",
            (goal_id, user_id),
        ).fetchone()
        if row is None:
            raise RepositoryNotFoundError(f"Goal not found: {goal_id}")
        return _goal_row_to_dict(connection, row)


def delete_goal(db_path: str | Path | None, user_id: str, goal_id: str) -> None:
    with _connect(db_path) as connection:
        connection.execute(
            "DELETE FROM goals WHERE id = ? AND user_id = ?",
            (goal_id, user_id),
        )
        connection.commit()


def add_goal_task(
    db_path: str | Path | None,
    user_id: str,
    goal_id: str,
    payload: dict[str, object],
) -> dict[str, object]:
    now = _now()
    with _connect(db_path) as connection:
        goal = connection.execute(
            "SELECT * FROM goals WHERE id = ? AND user_id = ?",
            (goal_id, user_id),
        ).fetchone()
        if goal is None:
            if connection.execute("SELECT user_id FROM goals WHERE id = ?", (goal_id,)).fetchone() is not None:
                raise RepositoryConflictError(f"Goal belongs to another user: {goal_id}")
            raise RepositoryNotFoundError(f"Goal not found: {goal_id}")

        task = _normalize_goal_task_payload(payload)
        existing = connection.execute(
            "SELECT user_id, goal_id FROM goal_tasks WHERE id = ?",
            (task["id"],),
        ).fetchone()
        if existing is not None:
            raise RepositoryConflictError(f"Goal task id already exists: {task['id']}")

        tasks = _list_goal_tasks_on_connection(connection, user_id, goal_id)
        tasks.append(task)
        _validate_goal_tasks(tasks)
        _insert_goal_tasks(
            connection,
            user_id,
            goal_id,
            [task],
            now,
            validate=False,
            start_position=len(tasks) - 1,
        )
        connection.commit()
        return _goal_row_to_dict(connection, goal)


def update_goal_task(
    db_path: str | Path | None,
    user_id: str,
    goal_id: str,
    task_id: str,
    payload: dict[str, object],
) -> dict[str, object]:
    now = _now()
    with _connect(db_path) as connection:
        goal = connection.execute(
            "SELECT * FROM goals WHERE id = ? AND user_id = ?",
            (goal_id, user_id),
        ).fetchone()
        if goal is None:
            if connection.execute("SELECT user_id FROM goals WHERE id = ?", (goal_id,)).fetchone() is not None:
                raise RepositoryConflictError(f"Goal belongs to another user: {goal_id}")
            raise RepositoryNotFoundError(f"Goal not found: {goal_id}")

        existing_task = connection.execute(
            "SELECT user_id, goal_id FROM goal_tasks WHERE id = ?",
            (task_id,),
        ).fetchone()
        if existing_task is None or existing_task["goal_id"] != goal_id or existing_task["user_id"] != user_id:
            if existing_task is not None and existing_task["user_id"] != user_id:
                raise RepositoryConflictError(f"Goal task belongs to another user: {task_id}")
            raise RepositoryNotFoundError(f"Goal task not found: {task_id}")

        updated_task = _normalize_goal_task_payload(payload, task_id=task_id)
        tasks = [
            updated_task if task["id"] == task_id else task
            for task in _list_goal_tasks_on_connection(connection, user_id, goal_id)
        ]
        _validate_goal_tasks(tasks)
        connection.execute(
            """
            UPDATE goal_tasks
            SET title = ?, duration_minutes = ?, load = ?, tag = ?, done = ?,
                depends_on_json = ?, updated_at = ?
            WHERE id = ? AND goal_id = ? AND user_id = ?
            """,
            (
                str(updated_task.get("title") or ""),
                _parse_int(updated_task.get("durationMinutes"), 30),
                str(updated_task.get("load") or "medium"),
                str(updated_task.get("tag") or "Goal"),
                1 if _parse_bool(updated_task.get("done"), False) else 0,
                json.dumps(_depends_on_list(updated_task.get("dependsOn")), ensure_ascii=False),
                now,
                task_id,
                goal_id,
                user_id,
            ),
        )
        connection.commit()
        return _goal_row_to_dict(connection, goal)


def _filter_busy_by_day(busy: object, day: str | None = None) -> list[dict[str, object]]:
    if not isinstance(busy, list):
        return []
    out: list[dict[str, object]] = []
    for item in busy:
        if not isinstance(item, dict):
            continue
        mapped = dict(item)
        if day is not None and _iso_day(mapped.get("day")) != day:
            continue
        out.append(mapped)
    return out


def _team_member_row_to_dict(row: sqlite3.Row, day: str | None = None) -> dict[str, object]:
    try:
        busy = json.loads(row["busy_json"])
    except json.JSONDecodeError:
        busy = []
    return {
        "memberId": row["id"],
        "displayName": row["display_name"],
        "role": row["role"],
        "energy": row["energy"],
        "permission": row["permission"],
        "busy": _filter_busy_by_day(busy, day),
    }


def upsert_team_member(
    db_path: str | Path | None,
    user_id: str,
    payload: dict[str, object],
    member_id: str | None = None,
) -> dict[str, object]:
    resolved_id = str(member_id or _first_non_none(payload, "memberId", "member_id") or uuid.uuid4().hex)
    display_name = str(_first_non_none(payload, "displayName", "display_name", default=""))
    role = str(payload.get("role") or "")
    energy = str(payload.get("energy") or "medium")
    permission = str(payload.get("permission") or "freeBusy")
    busy = payload.get("busy") if isinstance(payload.get("busy"), list) else []
    now = _now()

    with _connect(db_path) as connection:
        _check_global_owner(connection, "team_members", resolved_id, user_id, "Team member")
        connection.execute(
            """
            INSERT INTO team_members (
                id, user_id, display_name, role, energy, permission, busy_json, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                display_name = excluded.display_name,
                role = excluded.role,
                energy = excluded.energy,
                permission = excluded.permission,
                busy_json = excluded.busy_json,
                updated_at = excluded.updated_at
            WHERE team_members.user_id = excluded.user_id
            """,
            (
                resolved_id,
                user_id,
                display_name,
                role,
                energy,
                permission,
                json.dumps(busy, ensure_ascii=False),
                now,
                now,
            ),
        )
        connection.commit()
        row = connection.execute(
            "SELECT * FROM team_members WHERE id = ? AND user_id = ?",
            (resolved_id, user_id),
        ).fetchone()
        if row is None:
            raise RepositoryNotFoundError(f"Team member not found: {resolved_id}")
        return _team_member_row_to_dict(row)


def list_team_members(
    db_path: str | Path | None,
    user_id: str,
    day: str | None = None,
) -> list[dict[str, object]]:
    with _connect(db_path) as connection:
        rows = connection.execute(
            """
            SELECT * FROM team_members
            WHERE user_id = ?
            ORDER BY display_name ASC, id ASC
            """,
            (user_id,),
        ).fetchall()
        return [_team_member_row_to_dict(row, day) for row in rows]


def update_team_member_permission(
    db_path: str | Path | None,
    user_id: str,
    member_id: str,
    permission: str,
) -> dict[str, object]:
    with _connect(db_path) as connection:
        row = connection.execute(
            "SELECT * FROM team_members WHERE id = ? AND user_id = ?",
            (member_id, user_id),
        ).fetchone()
        if row is None:
            if connection.execute("SELECT user_id FROM team_members WHERE id = ?", (member_id,)).fetchone() is not None:
                raise RepositoryConflictError(f"Team member belongs to another user: {member_id}")
            raise RepositoryNotFoundError(f"Team member not found: {member_id}")
        connection.execute(
            """
            UPDATE team_members
            SET permission = ?, updated_at = ?
            WHERE id = ? AND user_id = ?
            """,
            (permission, _now(), member_id, user_id),
        )
        connection.commit()
        updated = connection.execute(
            "SELECT * FROM team_members WHERE id = ? AND user_id = ?",
            (member_id, user_id),
        ).fetchone()
        if updated is None:
            raise RepositoryNotFoundError(f"Team member not found: {member_id}")
        return _team_member_row_to_dict(updated)


def delete_team_member(db_path: str | Path | None, user_id: str, member_id: str) -> None:
    with _connect(db_path) as connection:
        connection.execute(
            "DELETE FROM team_members WHERE id = ? AND user_id = ?",
            (member_id, user_id),
        )
        connection.commit()


# --- Remote schedule-rescue transaction (P1 item 4) ---


def _insert_schedule_on_connection(
    connection: sqlite3.Connection,
    user_id: str,
    payload: dict[str, object],
    now: str,
) -> dict[str, object]:
    (
        schedule_id,
        day,
        title,
        tag,
        load,
        goal_id,
        goal_task_id,
        height,
        color,
        hour,
        minute,
        reminder_minutes_before,
        repeat,
        repeat_until,
    ) = _normalize_schedule_values(payload)
    _check_global_owner(connection, "schedules", schedule_id, user_id, "Schedule")
    try:
        connection.execute(
            """
            INSERT INTO schedules (
                id, user_id, day, title, tag, load, goal_id, goal_task_id, height, color,
                time_hour, time_minute, reminder_minutes_before, repeat, repeat_until,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                schedule_id,
                user_id,
                day,
                title,
                tag,
                load,
                goal_id,
                goal_task_id,
                height,
                color,
                hour,
                minute,
                reminder_minutes_before,
                repeat,
                repeat_until,
                now,
                now,
            ),
        )
    except sqlite3.IntegrityError as exc:
        raise RepositoryConflictError(f"Schedule id already exists: {schedule_id}") from exc
    row = connection.execute(
        "SELECT * FROM schedules WHERE id = ? AND user_id = ?",
        (schedule_id, user_id),
    ).fetchone()
    return _schedule_row_to_dict(row)


def _delete_schedules_for_day_on_connection(
    connection: sqlite3.Connection,
    user_id: str,
    day_iso: str,
) -> None:
    connection.execute(
        "DELETE FROM schedules WHERE user_id = ? AND day = ?",
        (user_id, day_iso),
    )


def _insert_rescue_snapshot_on_connection(
    connection: sqlite3.Connection,
    snapshot_id: str,
    user_id: str,
    day_iso: str,
    strategy: str,
    baseline_hash: str,
    urgent_json: str | None,
    before_json: str,
    now: str,
) -> None:
    connection.execute(
        """
        INSERT INTO rescue_snapshots (
            id, user_id, day, strategy, baseline_hash, urgent_json, before_json,
            status, created_at, undone_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'active', ?, NULL)
        """,
        (snapshot_id, user_id, day_iso, strategy, baseline_hash, urgent_json, before_json, now),
    )


def apply_rescue(
    db_path: str | Path | None,
    user_id: str,
    day_iso: str,
    strategy: str,
    baseline_hash: str,
    after_payloads: list[dict[str, object]],
    event_payload: dict[str, object],
    urgent_payload: dict[str, object] | None,
) -> dict[str, object]:
    """Atomically apply one rescue option for a single day.

    Verifies the baseline hash against the current database rows, then in one
    transaction: replaces the day's schedules, writes the `rescue_accept:`
    task event and saves the pre-apply snapshot. Any failure rolls back every
    write; a stale baseline raises RepositoryConflictError before any write.
    """
    with _connect(db_path) as connection:
        connection.execute("BEGIN IMMEDIATE")
        rows = connection.execute(
            "SELECT * FROM schedules WHERE user_id = ? AND day = ? ORDER BY id",
            (user_id, day_iso),
        ).fetchall()
        before = [_schedule_row_to_dict(row) for row in rows]
        if compute_baseline_hash(before, day_iso) != baseline_hash:
            raise RepositoryConflictError("Schedule baseline changed; regenerate rescue options")
        _delete_schedules_for_day_on_connection(connection, user_id, day_iso)
        now = _now()
        for payload in after_payloads:
            _insert_schedule_on_connection(connection, user_id, payload, now)
        event_payload = dict(event_payload)
        event_payload.update({"type": "interrupt", "reason": f"rescue_accept:{strategy}", "at": now})
        event_id = _upsert_task_event_on_connection(connection, user_id, event_payload, now)
        snapshot_id = uuid.uuid4().hex
        _insert_rescue_snapshot_on_connection(
            connection,
            snapshot_id,
            user_id,
            day_iso,
            strategy,
            baseline_hash,
            json.dumps(urgent_payload, ensure_ascii=False) if urgent_payload else None,
            json.dumps(before, ensure_ascii=False),
            now,
        )
        connection.commit()
    stored = list_schedules(db_path, user_id)
    return {
        "snapshotId": snapshot_id,
        "entries": [entry for entry in stored if entry.get("day") == day_iso],
        "eventId": event_id,
    }


def undo_rescue(
    db_path: str | Path | None,
    user_id: str,
    snapshot_id: str,
    event_id: str | None,
) -> dict[str, object]:
    """Atomically undo an applied rescue option.

    Restores the pre-apply snapshot in one transaction and writes the
    `rescue_undo:` task event. On failure the current plan is kept and the
    snapshot stays `active`, so the client can retry.
    """
    with _connect(db_path) as connection:
        connection.execute("BEGIN IMMEDIATE")
        row = connection.execute(
            "SELECT * FROM rescue_snapshots WHERE id = ?",
            (snapshot_id,),
        ).fetchone()
        if row is None or row["user_id"] != user_id:
            raise RepositoryNotFoundError(f"Rescue snapshot not found: {snapshot_id}")
        if row["status"] != "active":
            raise RepositoryConflictError(f"Rescue snapshot already undone: {snapshot_id}")
        day_iso = str(row["day"])
        strategy = str(row["strategy"])
        try:
            before = json.loads(row["before_json"])
        except (TypeError, ValueError):
            before = []
        urgent = None
        if row["urgent_json"]:
            try:
                urgent = json.loads(row["urgent_json"])
            except (TypeError, ValueError):
                urgent = None
        _delete_schedules_for_day_on_connection(connection, user_id, day_iso)
        now = _now()
        for payload in before:
            _insert_schedule_on_connection(connection, user_id, payload, now)
        event_payload = build_rescue_event(urgent, event_id, "medium")
        event_payload.update({"type": "interrupt", "reason": f"rescue_undo:{strategy}", "at": now})
        saved_event_id = _upsert_task_event_on_connection(connection, user_id, event_payload, now)
        connection.execute(
            "UPDATE rescue_snapshots SET status = 'undone', undone_at = ? WHERE id = ?",
            (now, snapshot_id),
        )
        connection.commit()
    stored = list_schedules(db_path, user_id)
    return {
        "entries": [entry for entry in stored if entry.get("day") == day_iso],
        "eventId": saved_event_id,
    }
