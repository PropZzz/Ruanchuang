from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .repositories import init_db
from .routers_auth import router as auth_router
from .routers_emotion import router as emotion_router
from .routers_events import router as events_router
from .routers_goals import router as goals_router
from .routers_microtasks import router as microtasks_router
from .routers_rescue import router as rescue_router
from .routers_reserved import router as reserved_router
from .routers_review import router as review_router
from .routers_schedule import router as schedule_router
from .routers_team import router as team_router


VERSION = "0.1.0"


def create_app(db_path: str | Path | None = None) -> FastAPI:
    resolved_db_path = Path(db_path) if db_path is not None else None

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        init_db(resolved_db_path)
        yield

    app = FastAPI(title="Ruanchuang Backend", lifespan=lifespan)
    app.state.db_path = resolved_db_path
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/health")
    def health() -> dict[str, object]:
        return {"ok": True, "version": VERSION, "database": "sqlite"}

    app.include_router(auth_router)
    app.include_router(events_router)
    app.include_router(schedule_router)
    app.include_router(rescue_router)
    app.include_router(microtasks_router)
    app.include_router(review_router)
    app.include_router(emotion_router)
    app.include_router(goals_router)
    app.include_router(team_router)
    app.include_router(reserved_router)

    return app


app = create_app()
