# 时序智配 Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working vertical slice of the recommended FastAPI + SQLite backend and connect the Flutter app to it with remote-first/local-fallback data access.

**Architecture:** Add a `backend/` FastAPI app with SQLite persistence, REST routers, and algorithm services that mirror the existing Flutter domain model. On the Flutter side, add an HTTP client and replace the placeholder `RemoteDataService` with a real implementation while keeping `LocalDataService` as fallback through `CompositeDataService`.

**Tech Stack:** Python 3.10+, FastAPI, Uvicorn, SQLite, pytest, Flutter, Dart `http` package, existing Flutter `DataService` abstraction.

---

## Scope Check

The approved full design covers backend, frontend service wiring, algorithms, UI redesign, and end-to-end verification. That is too large for one safe implementation pass. This Phase 1 plan produces a working, testable slice:

1. Independent backend starts and exposes `/health`.
2. Backend persists users, schedules, microtasks, emotion check-ins, task events, and basic settings in SQLite.
3. Backend exposes scheduling and microtask crystal algorithm endpoints.
4. Flutter can call backend through `ApiClient`.
5. Flutter uses remote-first reads/writes and falls back to local data if backend is unavailable.

Later plans should cover the richer desktop/Web dashboard redesign, mobile polish, team collaboration UI refinements, full review visualization, and final presentation packaging.

## File Structure

Create these backend files under `G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main\backend`:

- `requirements.txt`: backend dependencies.
- `README.md`: run commands and API base URL notes.
- `main.py`: FastAPI app factory and router registration.
- `database.py`: SQLite connection, schema initialization, row helpers.
- `auth.py`: simple token creation and password hashing helpers.
- `schemas.py`: Pydantic request/response models matching Flutter JSON.
- `repositories.py`: small persistence functions for users, schedules, microtasks, emotion, task events, and settings.
- `services_scheduling.py`: backend copy of heuristic scheduling.
- `services_microtask.py`: backend copy of time crystal recommendation.
- `routers_auth.py`: register/login/me.
- `routers_schedule.py`: schedule CRUD and replan.
- `routers_microtasks.py`: microtask CRUD and crystal recommendation.
- `routers_emotion.py`: emotion current/check-in.
- `routers_review.py`: event logging and weekly report.
- `tests/test_health.py`: backend health smoke test.
- `tests/test_scheduling.py`: backend scheduling algorithm test.
- `tests/test_api_flow.py`: register, create schedule, create microtask, recommend crystal.

Modify these Flutter files:

- `pubspec.yaml`: add `http`.
- `lib/config/app_config.dart`: define API base URL.
- `lib/services/api_client.dart`: HTTP helper.
- `lib/services/remote_data_service.dart`: replace placeholder with real remote calls for Phase 1 methods.
- `lib/services/app_services.dart`: use `CompositeDataService` remote-first.
- `test/remote_data_service_test.dart`: unit tests with a fake HTTP client.

Keep these unchanged in Phase 1 unless a test requires a small compatibility fix:

- Existing screen files under `lib/screens/`.
- Existing local persistence files.
- Android Gradle files.

## Task 1: Backend Skeleton and Health Endpoint

**Files:**
- Create: `backend/requirements.txt`
- Create: `backend/README.md`
- Create: `backend/main.py`
- Create: `backend/database.py`
- Test: `backend/tests/test_health.py`

- [ ] **Step 1: Create backend dependency file**

Create `backend/requirements.txt`:

```text
fastapi==0.115.6
uvicorn[standard]==0.34.0
pydantic==2.10.4
pytest==8.3.4
httpx==0.28.1
```

- [ ] **Step 2: Create database module**

Create `backend/database.py`:

```python
from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Iterable

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
DB_PATH = DATA_DIR / "shixuzhipei.db"


def get_connection(path: Path | None = None) -> sqlite3.Connection:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path or DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(conn: sqlite3.Connection) -> None:
    statements: Iterable[str] = [
        """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            account TEXT NOT NULL UNIQUE,
            display_name TEXT NOT NULL,
            password_hash TEXT NOT NULL,
            created_at TEXT NOT NULL
        )
        """,
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
            start_minute INTEGER NOT NULL,
            duration_minutes INTEGER NOT NULL,
            color INTEGER NOT NULL,
            reminder_minutes_before INTEGER NOT NULL DEFAULT 10,
            repeat TEXT NOT NULL DEFAULT 'none',
            repeat_until TEXT,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS microtasks (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            tag TEXT NOT NULL,
            minutes INTEGER NOT NULL,
            priority INTEGER NOT NULL,
            requirement TEXT,
            done INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS emotion_checkins (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            at TEXT NOT NULL,
            state TEXT NOT NULL,
            note TEXT,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """,
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
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS settings (
            user_id TEXT PRIMARY KEY,
            theme_mode TEXT NOT NULL DEFAULT 'system',
            locale TEXT NOT NULL DEFAULT 'zh_CN',
            favorite_device_id TEXT,
            scheduling_tuning_json TEXT NOT NULL DEFAULT '{}',
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
        """,
    ]
    for statement in statements:
        conn.execute(statement)
    conn.commit()
```

- [ ] **Step 3: Create FastAPI app**

Create `backend/main.py`:

```python
from __future__ import annotations

from fastapi import FastAPI

from database import get_connection, init_db

APP_VERSION = "0.1.0"


def create_app() -> FastAPI:
    app = FastAPI(title="时序智配 API", version=APP_VERSION)

    @app.on_event("startup")
    def startup() -> None:
        with get_connection() as conn:
            init_db(conn)

    @app.get("/health")
    def health() -> dict[str, object]:
        with get_connection() as conn:
            init_db(conn)
            conn.execute("SELECT 1").fetchone()
        return {"ok": True, "version": APP_VERSION, "database": "sqlite"}

    return app


app = create_app()
```

- [ ] **Step 4: Add backend README**

Create `backend/README.md`:

```markdown
# 时序智配 Backend

## Install

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

## Run

```powershell
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

## Verify

Open `http://127.0.0.1:8000/docs` or run:

```powershell
.\.venv\Scripts\python.exe -m pytest
```
```

- [ ] **Step 5: Write health test**

Create `backend/tests/test_health.py`:

```python
from fastapi.testclient import TestClient

from main import create_app


def test_health_returns_ok():
    client = TestClient(create_app())
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert response.json()["database"] == "sqlite"
```

- [ ] **Step 6: Run health test**

Run from `G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main\backend`:

```powershell
python -m pytest tests/test_health.py -v
```

Expected: `1 passed`.

- [ ] **Step 7: Commit backend skeleton**

Only run this commit step if the working tree has been isolated or unrelated staged files have been cleared. Use exact paths:

```powershell
git add backend/requirements.txt backend/README.md backend/main.py backend/database.py backend/tests/test_health.py
git commit -m "feat: add FastAPI backend skeleton"
```

## Task 2: Backend Schemas, Auth, and Repositories

**Files:**
- Create: `backend/schemas.py`
- Create: `backend/auth.py`
- Create: `backend/repositories.py`
- Modify: `backend/main.py`
- Create: `backend/routers_auth.py`
- Test: `backend/tests/test_api_flow.py`

- [ ] **Step 1: Create schema models**

Create `backend/schemas.py` with the Phase 1 models:

```python
from __future__ import annotations

from pydantic import BaseModel, Field


class TokenResponse(BaseModel):
    token: str
    user: "UserOut"


class UserCreate(BaseModel):
    account: str = Field(min_length=1)
    password: str = Field(min_length=6)
    displayName: str | None = None


class UserLogin(BaseModel):
    account: str = Field(min_length=1)
    password: str = Field(min_length=6)


class UserOut(BaseModel):
    id: str
    contactAddress: str
    displayName: str


class ScheduleEntryIn(BaseModel):
    id: str | None = None
    day: str | None = None
    title: str
    tag: str
    load: str | None = None
    goalId: str | None = None
    goalTaskId: str | None = None
    height: float = 80.0
    color: int = 0xFF009688
    time: dict[str, int]
    reminderMinutesBefore: int = 10
    repeat: str = "none"
    repeatUntil: str | None = None


class ScheduleEntryOut(ScheduleEntryIn):
    id: str


class MicroTaskIn(BaseModel):
    id: str | None = None
    title: str
    tag: str
    minutes: int
    priority: int = 3
    requirement: str | None = None
    done: bool = False


class MicroTaskOut(MicroTaskIn):
    id: str


class EmotionCheckInIn(BaseModel):
    id: str | None = None
    at: str
    state: str
    note: str | None = None


class EmotionCheckInOut(EmotionCheckInIn):
    id: str


class TimeWindow(BaseModel):
    start: dict[str, int]
    end: dict[str, int]


class PlanTask(BaseModel):
    id: str
    title: str
    durationMinutes: int
    priority: int
    load: str
    tag: str
    due: str | None = None


class SchedulingTuning(BaseModel):
    defaultDurationMultiplier: float = 1.0
    tagDurationMultiplier: dict[str, float] = {}
    highLoadPenaltyWhenLowEnergy: float = 1.0


class SchedulingRequestIn(BaseModel):
    day: str
    tasks: list[PlanTask]
    windows: list[TimeWindow]
    energy: str = "medium"
    tuning: SchedulingTuning = SchedulingTuning()
    fixed: list[ScheduleEntryIn] = []


class SchedulingIssue(BaseModel):
    code: str
    message: str
    taskId: str | None = None


class SchedulingPlanOut(BaseModel):
    entries: list[ScheduleEntryOut]
    issues: list[SchedulingIssue] = []


class CrystalRecommendationRequest(BaseModel):
    schedule: list[ScheduleEntryIn]
    microTasks: list[MicroTaskIn]
    windows: list[TimeWindow]
    energy: str = "medium"
    now: dict[str, int]
    maxRecommendations: int = 5


class CrystalOut(BaseModel):
    start: dict[str, int]
    minutes: int
    bucket: str


class CrystalRecommendationOut(BaseModel):
    crystal: CrystalOut
    task: MicroTaskOut
    score: float


class TaskEventIn(BaseModel):
    id: str
    taskId: str
    title: str
    tag: str
    load: str | None = None
    at: str
    type: str
    plannedMinutes: int | None = None
    energy: str | None = None
    actualMinutes: int | None = None
    interruptions: int | None = None
    reason: str | None = None


class ReviewReportOut(BaseModel):
    weekStart: str
    weekEnd: str
    startedCount: int
    completedCount: int
    completionRate: float
    plannedMinutesTotal: int
    actualMinutesTotal: int
    actualDurationBuckets: dict[str, int]
    delayAttribution: dict[str, int]
    suggestions: list[str]
    tuning: SchedulingTuning
```

- [ ] **Step 2: Create auth helpers**

Create `backend/auth.py`:

```python
from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timezone

from fastapi import Depends, Header, HTTPException

from database import get_connection

_TOKENS: dict[str, str] = {}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_id(prefix: str) -> str:
    return f"{prefix}_{secrets.token_hex(8)}"


def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode("utf-8")).hexdigest()


def create_token(user_id: str) -> str:
    token = secrets.token_urlsafe(32)
    _TOKENS[token] = user_id
    return token


def current_user_id(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing token")
    token = authorization.removeprefix("Bearer ").strip()
    user_id = _TOKENS.get(token)
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token")
    return user_id


def get_db():
    with get_connection() as conn:
        yield conn
```

- [ ] **Step 3: Create repositories**

Create `backend/repositories.py`:

```python
from __future__ import annotations

import sqlite3
from typing import Any

from auth import hash_password, new_id, now_iso


def user_to_out(row: sqlite3.Row) -> dict[str, str]:
    return {
        "id": row["id"],
        "contactAddress": row["account"],
        "displayName": row["display_name"],
    }


def create_user(conn: sqlite3.Connection, account: str, password: str, display_name: str | None) -> dict[str, str]:
    user_id = new_id("usr")
    name = display_name or f"用户_{account[:4]}"
    conn.execute(
        "INSERT INTO users(id, account, display_name, password_hash, created_at) VALUES (?, ?, ?, ?, ?)",
        (user_id, account, name, hash_password(password), now_iso()),
    )
    conn.execute(
        "INSERT OR REPLACE INTO settings(user_id, theme_mode, locale, scheduling_tuning_json) VALUES (?, 'system', 'zh_CN', '{}')",
        (user_id,),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    return user_to_out(row)


def find_user_by_account(conn: sqlite3.Connection, account: str) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM users WHERE account = ?", (account,)).fetchone()


def find_user_by_id(conn: sqlite3.Connection, user_id: str) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()


def verify_user(row: sqlite3.Row, password: str) -> bool:
    return row["password_hash"] == hash_password(password)


def _time_to_start_minute(raw: dict[str, int]) -> int:
    return int(raw.get("hour", 0)) * 60 + int(raw.get("minute", 0))


def _start_minute_to_time(value: int) -> dict[str, int]:
    return {"hour": value // 60, "minute": value % 60}


def _duration_from_height(height: float) -> int:
    return max(1, min(24 * 60, round((height / 80.0) * 60.0)))


def _height_from_duration(minutes: int) -> float:
    return max(20.0, (minutes / 60.0) * 80.0)


def schedule_to_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "day": row["day"],
        "title": row["title"],
        "tag": row["tag"],
        "load": row["load"],
        "goalId": row["goal_id"],
        "goalTaskId": row["goal_task_id"],
        "height": _height_from_duration(row["duration_minutes"]),
        "color": row["color"],
        "time": _start_minute_to_time(row["start_minute"]),
        "reminderMinutesBefore": row["reminder_minutes_before"],
        "repeat": row["repeat"],
        "repeatUntil": row["repeat_until"],
    }


def list_schedules(conn: sqlite3.Connection, user_id: str) -> list[dict[str, Any]]:
    rows = conn.execute(
        "SELECT * FROM schedules WHERE user_id = ? ORDER BY day, start_minute",
        (user_id,),
    ).fetchall()
    return [schedule_to_out(row) for row in rows]


def upsert_schedule(conn: sqlite3.Connection, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    entry_id = payload.get("id") or new_id("sch")
    height = float(payload.get("height") or 80.0)
    conn.execute(
        """
        INSERT OR REPLACE INTO schedules(
            id, user_id, day, title, tag, load, goal_id, goal_task_id,
            start_minute, duration_minutes, color, reminder_minutes_before, repeat, repeat_until
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            entry_id,
            user_id,
            payload.get("day"),
            payload["title"],
            payload["tag"],
            payload.get("load"),
            payload.get("goalId"),
            payload.get("goalTaskId"),
            _time_to_start_minute(payload["time"]),
            _duration_from_height(height),
            int(payload.get("color") or 0xFF009688),
            int(payload.get("reminderMinutesBefore") or 10),
            payload.get("repeat") or "none",
            payload.get("repeatUntil"),
        ),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM schedules WHERE id = ? AND user_id = ?", (entry_id, user_id)).fetchone()
    return schedule_to_out(row)


def delete_schedule(conn: sqlite3.Connection, user_id: str, entry_id: str) -> None:
    conn.execute("DELETE FROM schedules WHERE id = ? AND user_id = ?", (entry_id, user_id))
    conn.commit()


def microtask_to_out(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "id": row["id"],
        "title": row["title"],
        "tag": row["tag"],
        "minutes": row["minutes"],
        "priority": row["priority"],
        "requirement": row["requirement"],
        "done": bool(row["done"]),
    }


def list_microtasks(conn: sqlite3.Connection, user_id: str) -> list[dict[str, Any]]:
    rows = conn.execute(
        "SELECT * FROM microtasks WHERE user_id = ? ORDER BY done, priority DESC, created_at",
        (user_id,),
    ).fetchall()
    return [microtask_to_out(row) for row in rows]


def upsert_microtask(conn: sqlite3.Connection, user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    task_id = payload.get("id") or new_id("mt")
    now = now_iso()
    existing = conn.execute("SELECT created_at FROM microtasks WHERE id = ? AND user_id = ?", (task_id, user_id)).fetchone()
    created_at = existing["created_at"] if existing else now
    conn.execute(
        """
        INSERT OR REPLACE INTO microtasks(
            id, user_id, title, tag, minutes, priority, requirement, done, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            task_id,
            user_id,
            payload["title"],
            payload["tag"],
            int(payload["minutes"]),
            max(1, min(5, int(payload.get("priority") or 3))),
            payload.get("requirement"),
            1 if payload.get("done") else 0,
            created_at,
            now,
        ),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM microtasks WHERE id = ? AND user_id = ?", (task_id, user_id)).fetchone()
    return microtask_to_out(row)


def delete_microtask(conn: sqlite3.Connection, user_id: str, task_id: str) -> None:
    conn.execute("DELETE FROM microtasks WHERE id = ? AND user_id = ?", (task_id, user_id))
    conn.commit()
```

- [ ] **Step 4: Add auth router**

Create `backend/routers_auth.py`:

```python
from __future__ import annotations

import sqlite3

from fastapi import APIRouter, Depends, HTTPException

from auth import create_token, current_user_id, get_db
from repositories import create_user, find_user_by_account, find_user_by_id, user_to_out, verify_user
from schemas import TokenResponse, UserCreate, UserLogin, UserOut

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenResponse)
def register(payload: UserCreate, conn: sqlite3.Connection = Depends(get_db)):
    if find_user_by_account(conn, payload.account):
        raise HTTPException(status_code=409, detail="Account already exists")
    user = create_user(conn, payload.account, payload.password, payload.displayName)
    token = create_token(user["id"])
    return {"token": token, "user": user}


@router.post("/login", response_model=TokenResponse)
def login(payload: UserLogin, conn: sqlite3.Connection = Depends(get_db)):
    row = find_user_by_account(conn, payload.account)
    if row is None or not verify_user(row, payload.password):
        raise HTTPException(status_code=401, detail="Invalid account or password")
    user = user_to_out(row)
    token = create_token(user["id"])
    return {"token": token, "user": user}


@router.get("/me", response_model=UserOut)
def me(user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    row = find_user_by_id(conn, user_id)
    if row is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user_to_out(row)
```

- [ ] **Step 5: Register auth router**

Modify `backend/main.py` to include:

```python
from routers_auth import router as auth_router
```

and inside `create_app()` after the `/health` endpoint definition:

```python
    app.include_router(auth_router)
```

- [ ] **Step 6: Extend API flow test for auth**

Create `backend/tests/test_api_flow.py`:

```python
from fastapi.testclient import TestClient

from main import create_app


def test_register_login_and_me():
    client = TestClient(create_app())
    response = client.post(
        "/auth/register",
        json={"account": "demo@example.com", "password": "123456", "displayName": "Demo"},
    )
    assert response.status_code == 200
    token = response.json()["token"]
    assert response.json()["user"]["displayName"] == "Demo"

    me = client.get("/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["contactAddress"] == "demo@example.com"
```

- [ ] **Step 7: Run auth test**

Run:

```powershell
python -m pytest tests/test_api_flow.py::test_register_login_and_me -v
```

Expected: `1 passed`.

- [ ] **Step 8: Commit auth and repository foundation**

Only run this commit step if unrelated staged files are cleared:

```powershell
git add backend/schemas.py backend/auth.py backend/repositories.py backend/main.py backend/routers_auth.py backend/tests/test_api_flow.py
git commit -m "feat: add backend auth and repositories"
```

## Task 3: Schedule and Microtask API

**Files:**
- Create: `backend/routers_schedule.py`
- Create: `backend/routers_microtasks.py`
- Modify: `backend/main.py`
- Modify: `backend/tests/test_api_flow.py`

- [ ] **Step 1: Create schedule router**

Create `backend/routers_schedule.py`:

```python
from __future__ import annotations

import sqlite3

from fastapi import APIRouter, Depends

from auth import current_user_id, get_db
from repositories import delete_schedule, list_schedules, upsert_schedule
from schemas import ScheduleEntryIn, ScheduleEntryOut

router = APIRouter(prefix="/schedule", tags=["schedule"])


@router.get("", response_model=list[ScheduleEntryOut])
def get_schedule(user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    return list_schedules(conn, user_id)


@router.post("", response_model=ScheduleEntryOut)
def create_schedule(payload: ScheduleEntryIn, user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    return upsert_schedule(conn, user_id, payload.model_dump())


@router.put("/{entry_id}", response_model=ScheduleEntryOut)
def update_schedule(entry_id: str, payload: ScheduleEntryIn, user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    data = payload.model_dump()
    data["id"] = entry_id
    return upsert_schedule(conn, user_id, data)


@router.delete("/{entry_id}")
def remove_schedule(entry_id: str, user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    delete_schedule(conn, user_id, entry_id)
    return {"ok": True}
```

- [ ] **Step 2: Create microtask router**

Create `backend/routers_microtasks.py`:

```python
from __future__ import annotations

import sqlite3

from fastapi import APIRouter, Depends

from auth import current_user_id, get_db
from repositories import delete_microtask, list_microtasks, upsert_microtask
from schemas import MicroTaskIn, MicroTaskOut

router = APIRouter(prefix="/microtasks", tags=["microtasks"])


@router.get("", response_model=list[MicroTaskOut])
def get_microtasks(user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    return list_microtasks(conn, user_id)


@router.post("", response_model=MicroTaskOut)
def create_microtask(payload: MicroTaskIn, user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    return upsert_microtask(conn, user_id, payload.model_dump())


@router.put("/{task_id}", response_model=MicroTaskOut)
def update_microtask(task_id: str, payload: MicroTaskIn, user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    data = payload.model_dump()
    data["id"] = task_id
    return upsert_microtask(conn, user_id, data)


@router.delete("/{task_id}")
def remove_microtask(task_id: str, user_id: str = Depends(current_user_id), conn: sqlite3.Connection = Depends(get_db)):
    delete_microtask(conn, user_id, task_id)
    return {"ok": True}
```

- [ ] **Step 3: Register routers**

Modify `backend/main.py` imports:

```python
from routers_microtasks import router as microtasks_router
from routers_schedule import router as schedule_router
```

Add inside `create_app()`:

```python
    app.include_router(schedule_router)
    app.include_router(microtasks_router)
```

- [ ] **Step 4: Add schedule and microtask API test**

Append to `backend/tests/test_api_flow.py`:

```python
def _token(client: TestClient) -> str:
    response = client.post(
        "/auth/register",
        json={"account": "flow@example.com", "password": "123456", "displayName": "Flow"},
    )
    assert response.status_code == 200
    return response.json()["token"]


def test_schedule_and_microtask_crud():
    client = TestClient(create_app())
    token = _token(client)
    headers = {"Authorization": f"Bearer {token}"}

    schedule = client.post(
        "/schedule",
        headers=headers,
        json={
            "day": "2026-06-14",
            "title": "深度工作",
            "tag": "Deep Work",
            "load": "high",
            "height": 80.0,
            "color": 4278255360,
            "time": {"hour": 9, "minute": 0},
        },
    )
    assert schedule.status_code == 200
    assert schedule.json()["title"] == "深度工作"

    schedules = client.get("/schedule", headers=headers)
    assert schedules.status_code == 200
    assert len(schedules.json()) == 1

    microtask = client.post(
        "/microtasks",
        headers=headers,
        json={"title": "整理笔记", "tag": "低脑力", "minutes": 10, "priority": 3},
    )
    assert microtask.status_code == 200
    assert microtask.json()["minutes"] == 10

    microtasks = client.get("/microtasks", headers=headers)
    assert microtasks.status_code == 200
    assert len(microtasks.json()) == 1
```

- [ ] **Step 5: Run API CRUD test**

Run:

```powershell
python -m pytest tests/test_api_flow.py::test_schedule_and_microtask_crud -v
```

Expected: `1 passed`.

- [ ] **Step 6: Commit schedule and microtask API**

Only run after unrelated staged files are cleared:

```powershell
git add backend/routers_schedule.py backend/routers_microtasks.py backend/main.py backend/tests/test_api_flow.py
git commit -m "feat: add schedule and microtask APIs"
```

## Task 4: Backend Scheduling and Crystal Algorithms

**Files:**
- Create: `backend/services_scheduling.py`
- Create: `backend/services_microtask.py`
- Modify: `backend/routers_schedule.py`
- Modify: `backend/routers_microtasks.py`
- Test: `backend/tests/test_scheduling.py`

- [ ] **Step 1: Create scheduling service**

Create `backend/services_scheduling.py`:

```python
from __future__ import annotations

from datetime import datetime
from typing import Any


def _m(t: dict[str, int]) -> int:
    return int(t.get("hour", 0)) * 60 + int(t.get("minute", 0))


def _tod(minutes: int) -> dict[str, int]:
    minutes = max(0, min(24 * 60 - 1, minutes))
    return {"hour": minutes // 60, "minute": minutes % 60}


def _duration_from_height(height: float) -> int:
    return max(1, min(24 * 60, round((height / 80.0) * 60.0)))


def _height_from_duration(minutes: int) -> float:
    return max(20.0, (minutes / 60.0) * 80.0)


def _same_day(raw: str | None, day: str) -> bool:
    if not raw:
        return False
    return raw.split("T")[0] == day


def _color_for_load(load: str) -> int:
    if load == "high":
        return 0xFF009688
    if load == "medium":
        return 0xFF2196F3
    return 0xFFFF9800


def _subtract(free: list[tuple[int, int]], used: tuple[int, int]) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    us, ue = used
    for s, e in free:
        if ue <= s or us >= e:
            out.append((s, e))
            continue
        if us > s:
            out.append((s, us))
        if ue < e:
            out.append((ue, e))
    return sorted(out)


def _score(start: int, energy: str, load: str, high_load_penalty: float) -> float:
    hour = start // 60
    is_morning = hour < 12
    score = -start / 1000.0
    if energy in ("high", "veryHigh"):
        if load == "high" and is_morning:
            score += 5
        if load == "medium":
            score += 2
    elif energy == "medium":
        if load == "high" and is_morning:
            score += 2
        if load == "medium":
            score += 2
        if load == "low":
            score += 1
    else:
        penalty = max(1.0, min(3.0, high_load_penalty))
        if load == "high":
            score -= 5 * penalty
            if is_morning:
                score -= 2 * (penalty - 1.0)
        if load == "low":
            score += 3
    return score


def plan_schedule(request: dict[str, Any]) -> dict[str, Any]:
    day = request["day"].split("T")[0]
    energy = request.get("energy", "medium")
    tuning = request.get("tuning") or {}
    tag_multipliers = tuning.get("tagDurationMultiplier") or {}
    default_multiplier = float(tuning.get("defaultDurationMultiplier") or 1.0)
    high_load_penalty = float(tuning.get("highLoadPenaltyWhenLowEnergy") or 1.0)

    free: list[tuple[int, int]] = []
    for window in request.get("windows", []):
        s = _m(window["start"])
        e = _m(window["end"])
        if e > s:
            free.append((s, e))

    fixed_entries = list(request.get("fixed") or [])
    for entry in fixed_entries:
        s = _m(entry["time"])
        free = _subtract(free, (s, s + _duration_from_height(float(entry.get("height") or 80.0))))

    tasks = list(request.get("tasks") or [])

    def order_key(task: dict[str, Any]):
        due = task.get("due")
        due_min = 24 * 60 + 1
        if _same_day(due, day):
            dt = datetime.fromisoformat(due.replace("Z", "+00:00"))
            due_min = dt.hour * 60 + dt.minute
        return (due_min, -int(task.get("priority") or 1))

    tasks.sort(key=order_key)

    entries: list[dict[str, Any]] = []
    issues: list[dict[str, Any]] = []

    for task in tasks:
        mult = float(tag_multipliers.get(task.get("tag"), default_multiplier))
        duration = max(1, min(24 * 60, round(int(task["durationMinutes"]) * mult)))
        due_min = None
        if _same_day(task.get("due"), day):
            dt = datetime.fromisoformat(task["due"].replace("Z", "+00:00"))
            due_min = dt.hour * 60 + dt.minute

        best_start = None
        best_score = float("-inf")
        for s, e in free:
            if e - s < duration:
                continue
            if due_min is not None and s + duration > due_min:
                continue
            score = _score(s, energy, task["load"], high_load_penalty)
            if score > best_score:
                best_start = s
                best_score = score

        if best_start is None:
            for s, e in free:
                if e - s >= duration:
                    best_start = s
                    break

        if best_start is None:
            issues.append({"code": "no_slot", "message": f"No available slot for task: {task['title']}", "taskId": task["id"]})
            continue

        free = _subtract(free, (best_start, best_start + duration))
        entries.append({
            "id": task["id"],
            "day": day,
            "title": task["title"],
            "tag": task["tag"],
            "load": task["load"],
            "goalId": None,
            "goalTaskId": None,
            "height": _height_from_duration(duration),
            "color": _color_for_load(task["load"]),
            "time": _tod(best_start),
            "reminderMinutesBefore": 10,
            "repeat": "none",
            "repeatUntil": None,
        })
        if due_min is not None and best_start + duration > due_min:
            issues.append({"code": "miss_due", "message": f"Task scheduled past due time: {task['title']}", "taskId": task["id"]})

    output = fixed_entries + entries
    output.sort(key=lambda entry: _m(entry["time"]))
    return {"entries": output, "issues": issues}
```

- [ ] **Step 2: Create microtask crystal service**

Create `backend/services_microtask.py`:

```python
from __future__ import annotations

from typing import Any


def _m(t: dict[str, int]) -> int:
    return int(t.get("hour", 0)) * 60 + int(t.get("minute", 0))


def _tod(minutes: int) -> dict[str, int]:
    minutes = max(0, min(24 * 60 - 1, minutes))
    return {"hour": minutes // 60, "minute": minutes % 60}


def _duration_from_height(height: float) -> int:
    return max(1, min(24 * 60, round((height / 80.0) * 60.0)))


def _bucket(minutes: int) -> str:
    if minutes <= 15:
        return "short"
    if minutes <= 30:
        return "medium"
    return "long"


def _subtract(window: tuple[int, int], busy: list[tuple[int, int]]) -> list[tuple[int, int]]:
    free: list[tuple[int, int]] = []
    cursor = window[0]
    for s, e in sorted(busy):
        if e <= cursor:
            continue
        if s >= window[1]:
            break
        s = max(s, window[0])
        e = min(e, window[1])
        if s > cursor:
            free.append((cursor, s))
        cursor = max(cursor, e)
    if cursor < window[1]:
        free.append((cursor, window[1]))
    return free


def recommend_crystals(request: dict[str, Any]) -> list[dict[str, Any]]:
    busy = []
    for entry in request.get("schedule", []):
        s = _m(entry["time"])
        busy.append((s, s + _duration_from_height(float(entry.get("height") or 80.0))))

    now = _m(request["now"])
    crystals = []
    for window in request.get("windows", []):
        ws = _m(window["start"])
        we = _m(window["end"])
        if we <= ws:
            continue
        for s, e in _subtract((ws, we), busy):
            s = max(s, now)
            if e > s:
                crystals.append({"start": _tod(s), "minutes": e - s, "bucket": _bucket(e - s)})

    crystals.sort(key=lambda c: c["minutes"])
    tasks = [task for task in request.get("microTasks", []) if not task.get("done")]
    energy = request.get("energy", "medium")
    max_recs = int(request.get("maxRecommendations") or 5)
    recs = []

    for crystal in crystals:
        if len(recs) >= max_recs:
            break
        best = None
        best_score = float("-inf")
        for task in tasks:
            minutes = int(task["minutes"])
            if minutes <= 0 or minutes > crystal["minutes"]:
                continue
            waste = crystal["minutes"] - minutes
            score = (1.0 - waste / crystal["minutes"]) * 10.0 - waste * 0.05
            score += (max(1, min(5, int(task.get("priority") or 3))) - 3) * 0.6
            if energy in ("veryLow", "low") and minutes <= 15:
                score += 2.0
            if score > best_score:
                best_score = score
                best = task
        if best is None:
            continue
        tasks.remove(best)
        recs.append({"crystal": crystal, "task": best, "score": best_score})

    recs.sort(key=lambda rec: _m(rec["crystal"]["start"]))
    return recs
```

- [ ] **Step 3: Add schedule replan endpoint**

Append to `backend/routers_schedule.py`:

```python
from services_scheduling import plan_schedule
from schemas import SchedulingPlanOut, SchedulingRequestIn


@router.post("/replan", response_model=SchedulingPlanOut)
def replan(payload: SchedulingRequestIn, user_id: str = Depends(current_user_id)):
    return plan_schedule(payload.model_dump())
```

- [ ] **Step 4: Add microtask recommendation endpoint**

Append to `backend/routers_microtasks.py`:

```python
from services_microtask import recommend_crystals
from schemas import CrystalRecommendationOut, CrystalRecommendationRequest


@router.post("/recommend-crystals", response_model=list[CrystalRecommendationOut])
def recommend(payload: CrystalRecommendationRequest, user_id: str = Depends(current_user_id)):
    return recommend_crystals(payload.model_dump())
```

- [ ] **Step 5: Add algorithm tests**

Create `backend/tests/test_scheduling.py`:

```python
from services_microtask import recommend_crystals
from services_scheduling import plan_schedule


def test_plan_schedule_places_urgent_before_due():
    plan = plan_schedule({
        "day": "2026-06-14",
        "energy": "high",
        "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 12, "minute": 0}}],
        "fixed": [],
        "tasks": [
            {"id": "a", "title": "Deep", "durationMinutes": 90, "priority": 3, "load": "high", "tag": "Deep Work"},
            {"id": "u", "title": "Urgent", "durationMinutes": 30, "priority": 5, "load": "medium", "tag": "Urgent", "due": "2026-06-14T10:00:00"},
        ],
    })
    urgent = next(e for e in plan["entries"] if e["id"] == "u")
    end = urgent["time"]["hour"] * 60 + urgent["time"]["minute"] + 30
    assert end <= 10 * 60


def test_recommend_crystals_fits_microtask_into_gap():
    recs = recommend_crystals({
        "schedule": [
            {"title": "Busy", "tag": "Work", "height": 80.0, "time": {"hour": 9, "minute": 0}},
        ],
        "microTasks": [
            {"id": "m1", "title": "整理笔记", "tag": "低脑力", "minutes": 10, "priority": 3, "done": False},
        ],
        "windows": [{"start": {"hour": 8, "minute": 0}, "end": {"hour": 10, "minute": 0}}],
        "energy": "low",
        "now": {"hour": 8, "minute": 0},
        "maxRecommendations": 3,
    })
    assert len(recs) == 1
    assert recs[0]["task"]["id"] == "m1"
```

- [ ] **Step 6: Run algorithm tests**

Run:

```powershell
python -m pytest tests/test_scheduling.py -v
```

Expected: `2 passed`.

- [ ] **Step 7: Commit backend algorithms**

Only run after unrelated staged files are cleared:

```powershell
git add backend/services_scheduling.py backend/services_microtask.py backend/routers_schedule.py backend/routers_microtasks.py backend/tests/test_scheduling.py
git commit -m "feat: add backend scheduling algorithms"
```

## Task 5: Flutter ApiClient and RemoteDataService Slice

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/config/app_config.dart`
- Create: `lib/services/api_client.dart`
- Modify: `lib/services/remote_data_service.dart`
- Test: `test/remote_data_service_test.dart`

- [ ] **Step 1: Add HTTP dependency**

Modify `pubspec.yaml` under `dependencies:`:

```yaml
  http: ^1.2.2
```

Then run:

```powershell
flutter pub get
```

Expected: dependency resolution succeeds and `pubspec.lock` updates.

- [ ] **Step 2: Create app config**

Create `lib/config/app_config.dart`:

```dart
import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _definedBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    if (_definedBaseUrl.trim().isNotEmpty) return _definedBaseUrl.trim();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://127.0.0.1:8000';
  }
}
```

- [ ] **Step 3: Create API client**

Create `lib/services/api_client.dart`:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _httpClient = httpClient ?? http.Client(),
        _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');

  final http.Client _httpClient;
  final String _baseUrl;
  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  Uri _uri(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$normalized');
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
  }

  Future<Object?> get(String path) => _send('GET', path);
  Future<Object?> post(String path, Object? body) => _send('POST', path, body: body);
  Future<Object?> put(String path, Object? body) => _send('PUT', path, body: body);
  Future<Object?> delete(String path) => _send('DELETE', path);

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final uri = _uri(path);
    final encoded = body == null ? null : jsonEncode(body);
    final response = await switch (method) {
      'GET' => _httpClient.get(uri, headers: _headers()),
      'POST' => _httpClient.post(uri, headers: _headers(), body: encoded),
      'PUT' => _httpClient.put(uri, headers: _headers(), body: encoded),
      'DELETE' => _httpClient.delete(uri, headers: _headers()),
      _ => throw ApiException('Unsupported method: $method'),
    }.timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.body, statusCode: response.statusCode);
    }
    if (response.body.trim().isEmpty) return null;
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  void close() {
    _httpClient.close();
  }
}
```

- [ ] **Step 4: Replace RemoteDataService for Phase 1**

Modify `lib/services/remote_data_service.dart` so it has a constructor accepting `ApiClient`, stores the token after login/register, and implements these methods using HTTP:

```dart
import '../models/models.dart';
import 'api_client.dart';
import 'data_service.dart';

class RemoteDataException implements Exception {
  final String message;
  RemoteDataException(this.message);

  @override
  String toString() => 'RemoteDataException: $message';
}

class RemoteDataService implements DataService {
  RemoteDataService({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  static final RemoteDataService instance = RemoteDataService();

  final ApiClient _api;
  UserAccount? _currentUser;

  Never _unimplemented(String method) {
    throw RemoteDataException('$method is not available from remote service yet.');
  }

  List<Map<String, Object?>> _listOfMaps(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) => Map<String, Object?>.from(m)).toList();
  }

  Map<String, Object?> _map(Object? raw) {
    if (raw is! Map) throw RemoteDataException('Expected object response.');
    return Map<String, Object?>.from(raw);
  }

  @override
  Future<UserAccount?> getCurrentUser() async {
    if (_currentUser != null) return _currentUser;
    final raw = await _api.get('/auth/me');
    _currentUser = UserAccount.fromJson(_map(raw));
    return _currentUser;
  }

  @override
  Future<bool> login(String account, String password) async {
    final raw = await _api.post('/auth/login', {
      'account': account,
      'password': password,
    });
    final data = _map(raw);
    _api.setToken(data['token'] as String?);
    _currentUser = UserAccount.fromJson(_map(data['user']));
    return true;
  }

  @override
  Future<bool> registerAccount({required String username, required String password}) async {
    final raw = await _api.post('/auth/register', {
      'account': username,
      'password': password,
      'displayName': username,
    });
    final data = _map(raw);
    _api.setToken(data['token'] as String?);
    _currentUser = UserAccount.fromJson(_map(data['user']));
    return true;
  }

  @override
  Future<void> logout() async {
    _api.setToken(null);
    _currentUser = null;
  }

  @override
  Future<List<ScheduleEntry>> getScheduleEntries() async {
    final raw = await _api.get('/schedule');
    return _listOfMaps(raw).map(ScheduleEntry.fromJson).toList();
  }

  @override
  Future<void> addScheduleEntry(ScheduleEntry entry) async {
    if (entry.id == null || entry.id!.isEmpty) {
      await _api.post('/schedule', entry.toJson());
    } else {
      await _api.put('/schedule/${entry.id}', entry.toJson());
    }
  }

  @override
  Future<void> removeScheduleEntry(ScheduleEntry entry) async {
    final id = entry.id;
    if (id == null || id.isEmpty) return;
    await _api.delete('/schedule/$id');
  }

  @override
  Future<List<MicroTask>> getMicroTasks() async {
    final raw = await _api.get('/microtasks');
    return _listOfMaps(raw).map(MicroTask.fromJson).toList();
  }

  @override
  Future<void> addMicroTask(MicroTask task) async {
    await _api.post('/microtasks', task.toJson());
  }

  @override
  Future<void> removeMicroTask(MicroTask task) async {
    final id = task.id;
    if (id == null || id.isEmpty) return;
    await _api.delete('/microtasks/$id');
  }

  @override
  Future<void> updateMicroTask(MicroTask task) async {
    final id = task.id;
    if (id == null || id.isEmpty) {
      await addMicroTask(task);
      return;
    }
    await _api.put('/microtasks/$id', task.toJson());
  }

  @override
  Future<EmotionType> getCurrentEmotion() async => EmotionType.stable;

  @override
  Future<EnergyStatus> getEnergyStatus() async => const EnergyStatus(
        level: 'medium',
        status: '心流',
        description: '后端服务已连接',
        batteryPercent: 85,
      );

  @override
  Future<EmotionState> getEmotionState() async => EmotionState.stable;

  @override
  Future<void> addEmotionCheckIn(EmotionCheckIn checkIn) async => _unimplemented('addEmotionCheckIn');
  @override
  Future<List<EmotionCheckIn>> getEmotionCheckIns(DateTime day) async => _unimplemented('getEmotionCheckIns');
  @override
  Future<List<Goal>> getGoals() async => _unimplemented('getGoals');
  @override
  Future<void> upsertGoal(Goal goal) async => _unimplemented('upsertGoal');
  @override
  Future<void> deleteGoal(String goalId) async => _unimplemented('deleteGoal');
  @override
  Future<Task> getCurrentTask() async => _unimplemented('getCurrentTask');
  @override
  Future<List<Task>> getNextTasks() async => _unimplemented('getNextTasks');
  @override
  Future<List<TeamMember>> getTeamMembers() async => _unimplemented('getTeamMembers');
  @override
  Future<UserProfile> getUserProfile() async => _unimplemented('getUserProfile');
  @override
  Future<void> setFavoriteDevice(String deviceId) async => _unimplemented('setFavoriteDevice');
  @override
  Future<String?> getFavoriteDevice() async => _unimplemented('getFavoriteDevice');
  @override
  Future<String> getThemeMode() async => _unimplemented('getThemeMode');
  @override
  Future<void> setThemeMode(String themeMode) async => _unimplemented('setThemeMode');
  @override
  Future<String> getLocale() async => _unimplemented('getLocale');
  @override
  Future<void> setLocale(String locale) async => _unimplemented('setLocale');
  @override
  Future<void> logTaskEvent(TaskEvent event) async => _unimplemented('logTaskEvent');
  @override
  Future<List<TaskEvent>> getTaskEvents(DateTime from, DateTime to) async => _unimplemented('getTaskEvents');
  @override
  Future<ReviewReport> getWeeklyReport(DateTime weekStart) async => _unimplemented('getWeeklyReport');
  @override
  Future<SchedulingTuning> getSchedulingTuning() async => _unimplemented('getSchedulingTuning');
  @override
  Future<void> setSchedulingTuning(SchedulingTuning tuning) async => _unimplemented('setSchedulingTuning');
  @override
  Future<List<TeamMemberCalendar>> getTeamCalendars(DateTime day) async => _unimplemented('getTeamCalendars');
  @override
  Future<void> updateTeamSharePermission(String memberId, TeamSharePermission permission) async => _unimplemented('updateTeamSharePermission');
  @override
  Future<void> bookTeamMeeting(DateTime day, TeamMeetingRequest request) async => _unimplemented('bookTeamMeeting');
}
```

- [ ] **Step 5: Add remote service test**

Create `test/remote_data_service_test.dart` using `package:http/testing.dart` after adding the `http` package:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shixuzhipei/services/api_client.dart';
import 'package:shixuzhipei/services/remote_data_service.dart';

void main() {
  test('RemoteDataService stores token and reads schedules', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/auth/login') {
        return http.Response(
          jsonEncode({
            'token': 'abc',
            'user': {'contactAddress': 'demo@example.com', 'displayName': 'Demo'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/schedule') {
        expect(request.headers['authorization'], 'Bearer abc');
        return http.Response(
          jsonEncode([
            {
              'id': 'sch_1',
              'day': '2026-06-14',
              'title': '深度工作',
              'tag': 'Deep Work',
              'height': 80.0,
              'color': 4278255360,
              'time': {'hour': 9, 'minute': 0},
              'reminderMinutesBefore': 10,
              'repeat': 'none',
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('not found', 404);
    });

    final service = RemoteDataService(
      apiClient: ApiClient(httpClient: client, baseUrl: 'http://server.test'),
    );

    expect(await service.login('demo@example.com', '123456'), isTrue);
    final entries = await service.getScheduleEntries();
    expect(entries.single.title, '深度工作');
  });
}
```

- [ ] **Step 6: Run remote service test**

Run:

```powershell
flutter test test/remote_data_service_test.dart
```

Expected: test passes.

- [ ] **Step 7: Commit Flutter remote client slice**

Only run after unrelated staged files are cleared:

```powershell
git add pubspec.yaml pubspec.lock lib/config/app_config.dart lib/services/api_client.dart lib/services/remote_data_service.dart test/remote_data_service_test.dart
git commit -m "feat: connect Flutter remote data service"
```

## Task 6: Wire Remote-First Fallback and Smoke Test

**Files:**
- Modify: `lib/services/app_services.dart`
- Modify: `lib/services/composite_data_service.dart`
- Test: `test/app_services_remote_fallback_test.dart`

- [ ] **Step 1: Update AppServices default data service**

Modify imports in `lib/services/app_services.dart`:

```dart
import 'composite_data_service.dart';
import 'remote_data_service.dart';
```

Replace:

```dart
  static final DataService _defaultDataService = LocalDataService.instance;
```

with:

```dart
  static final DataService _defaultDataService = CompositeDataService(
    local: LocalDataService.instance,
    remote: RemoteDataService.instance,
    preferRemoteReads: true,
  );
```

- [ ] **Step 2: Ensure writes fall back when remote fails**

Modify `lib/services/composite_data_service.dart` by adding helper:

```dart
  Future<void> _write(Future<void> Function(DataService s) fn) async {
    if (preferRemoteReads) {
      try {
        await fn(remote);
        return;
      } catch (_) {
        await fn(local);
        return;
      }
    }
    await fn(local);
  }
```

Then change these Phase 1 writes:

```dart
  Future<void> addScheduleEntry(ScheduleEntry entry) =>
      _write((s) => s.addScheduleEntry(entry));

  Future<void> removeScheduleEntry(ScheduleEntry entry) =>
      _write((s) => s.removeScheduleEntry(entry));

  Future<void> addMicroTask(MicroTask task) =>
      _write((s) => s.addMicroTask(task));

  Future<void> removeMicroTask(MicroTask task) =>
      _write((s) => s.removeMicroTask(task));

  Future<void> updateMicroTask(MicroTask task) =>
      _write((s) => s.updateMicroTask(task));
```

- [ ] **Step 3: Add fallback test**

Create `test/app_services_remote_fallback_test.dart` with a fake remote that throws and a fake local that records writes:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shixuzhipei/models/models.dart';
import 'package:shixuzhipei/services/composite_data_service.dart';
import 'package:shixuzhipei/services/mock_data_service.dart';

class ThrowingMockDataService extends MockDataService {
  @override
  Future<List<MicroTask>> getMicroTasks() async => throw Exception('remote down');

  @override
  Future<void> addMicroTask(MicroTask task) async => throw Exception('remote down');
}

void main() {
  test('CompositeDataService falls back to local read and write', () async {
    final local = MockDataService.instance;
    final service = CompositeDataService(
      local: local,
      remote: ThrowingMockDataService(),
      preferRemoteReads: true,
    );

    final before = await service.getMicroTasks();
    await service.addMicroTask(MicroTask(title: 'fallback', tag: 'test', minutes: 5));
    final after = await service.getMicroTasks();

    expect(after.length, greaterThanOrEqualTo(before.length));
  });
}
```

If `MockDataService` cannot be subclassed because of constructor constraints, use `LocalDataService.forPersistence` with an in-memory fake `LocalPersistence` and a tiny `DataService` fake that throws. Keep the test name and expected behavior.

- [ ] **Step 4: Run fallback test**

Run:

```powershell
flutter test test/app_services_remote_fallback_test.dart
```

Expected: test passes.

- [ ] **Step 5: Run existing Flutter tests**

Run:

```powershell
flutter test
```

Expected: all tests pass. If unrelated existing tests fail because of preexisting Chinese text or UI layout issues, capture the exact failing test and fix only the code affected by this phase.

- [ ] **Step 6: Commit remote-first fallback**

Only run after unrelated staged files are cleared:

```powershell
git add lib/services/app_services.dart lib/services/composite_data_service.dart test/app_services_remote_fallback_test.dart
git commit -m "feat: enable remote-first data fallback"
```

## Task 7: End-to-End Local Runbook and Verification

**Files:**
- Create: `G:\study\c.C++\cproject\.dart\lib\时序智配后端联调说明.md`
- Modify: `backend/README.md`

- [ ] **Step 1: Add user-facing runbook**

Create `G:\study\c.C++\cproject\.dart\lib\时序智配后端联调说明.md`:

```markdown
# 时序智配后端联调说明

## 1. 启动后端

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main\backend
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000 --reload
```

浏览器打开：

```text
http://127.0.0.1:8000/docs
```

## 2. 运行后端测试

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main\backend
.\.venv\Scripts\python.exe -m pytest -v
```

## 3. 启动 Flutter Web

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## 4. Android 模拟器

Android 模拟器访问电脑本机后端时使用：

```powershell
flutter run -d emulator --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## 5. 验证流程

1. 启动后端。
2. 启动 Flutter。
3. 注册或登录账号。
4. 添加日程。
5. 添加微任务。
6. 切换智能日程或调用后端排程接口。
7. 关闭后端，再打开页面，确认本地兜底仍能显示基础数据。
```

- [ ] **Step 2: Update backend README with Flutter command**

Append to `backend/README.md`:

```markdown
## Flutter Client

Web:

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Android emulator:

```powershell
flutter run -d emulator --dart-define=API_BASE_URL=http://10.0.2.2:8000
```
```

- [ ] **Step 3: Verify backend docs endpoint manually**

Run:

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main\backend
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Open:

```text
http://127.0.0.1:8000/docs
```

Expected: OpenAPI page loads with auth, schedule, microtasks, and health endpoints.

- [ ] **Step 4: Commit runbook**

Only run after unrelated staged files are cleared:

```powershell
git add backend/README.md "G:\study\c.C++\cproject\.dart\lib\时序智配后端联调说明.md"
git commit -m "docs: add backend integration runbook"
```

## Final Verification

Run these commands from the project root after all tasks:

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main\backend
.\.venv\Scripts\python.exe -m pytest -v
```

Expected: all backend tests pass.

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main
flutter pub get
flutter analyze
flutter test
```

Expected: Flutter dependency resolution succeeds, analyzer has no new errors from Phase 1 files, tests pass.

Manual smoke:

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main\backend
.\.venv\Scripts\python.exe -m uvicorn main:app --host 127.0.0.1 --port 8000
```

Then in another terminal:

```powershell
cd /d G:\study\c.C++\cproject\.dart\lib\Ruanchuang-main
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Expected: Flutter launches, authentication uses the backend, schedule and microtask reads/writes hit the backend, and disabling backend still allows local fallback.

## Self-Review

Spec coverage:

1. Independent FastAPI backend: covered by Tasks 1-4.
2. SQLite persistence: covered by Tasks 1-3.
3. Authentication: covered by Task 2.
4. Schedule and microtask APIs: covered by Task 3.
5. Backend scheduling and crystal algorithms: covered by Task 4.
6. Flutter remote-first service: covered by Tasks 5-6.
7. Local fallback: covered by Task 6.
8. User-facing run instructions in requested outer directory: covered by Task 7.

Deferred to later plans:

1. Full team collaboration backend and UI refinement.
2. Full goals backend.
3. Rich review charts and desktop/mobile visual redesign.
4. ICS backend import/export.
5. Final app packaging and APK rebuild.

Placeholder scan: this plan contains no TBD/TODO placeholders. Every deferred item is explicitly out of Phase 1 and belongs to a later plan.

Type consistency: backend schema names intentionally mirror Flutter JSON names such as `goalId`, `durationMinutes`, `reminderMinutesBefore`, `taskId`, and `actualMinutes` to minimize frontend conversion code.
