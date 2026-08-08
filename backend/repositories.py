from __future__ import annotations

from datetime import date, datetime
import hashlib
from pathlib import Path
import sqlite3
import uuid

from .database import get_connection


class TaskEventConflictError(Exception):
    pass


class TaskEventBatchValidationError(ValueError):
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


def upsert_schedule(db_path: str | Path | None, user_id: str, payload: dict[str, object]) -> dict[str, object]:
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
