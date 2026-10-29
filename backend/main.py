from contextlib import asynccontextmanager
from pathlib import Path
from typing import AsyncIterator

from fastapi import FastAPI, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .repositories import (
    RepositoryConflictError,
    RepositoryNotFoundError,
    RepositoryValidationError,
    init_db,
)
from .routers_auth import router as auth_router
from .routers_emotion import router as emotion_router
from .routers_events import router as events_router
from .routers_goals import router as goals_router
from .routers_microtasks import router as microtasks_router
from .routers_platform import router as platform_router
from .routers_rescue import router as rescue_router
from .routers_reserved import router as reserved_router
from .routers_review import router as review_router
from .routers_schedule import router as schedule_router
from .routers_settings import router as settings_router
from .routers_team import router as team_router
from .routers_sync import router as sync_router


VERSION = "0.1.0"


def _domain_error_handler(status_code: int):
    """把仓库层领域异常稳定映射为 404/409/422，避免个别路由漏接时冒泡成 500。

    只处理三个明确的领域异常类型，不接管 HTTPException 或普通 ValueError，
    因此不会掩盖真正的服务端缺陷。
    """

    async def handler(_: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(status_code=status_code, content={"detail": str(exc)})

    return handler


def create_app(db_path: str | Path | None = None) -> FastAPI:
    resolved_db_path = Path(db_path) if db_path is not None else None

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        init_db(resolved_db_path)
        yield

    app = FastAPI(title="Ruanchuang Backend", lifespan=lifespan)
    app.state.db_path = resolved_db_path
    app.add_exception_handler(
        RepositoryNotFoundError,
        _domain_error_handler(status.HTTP_404_NOT_FOUND),
    )
    app.add_exception_handler(
        RepositoryConflictError,
        _domain_error_handler(status.HTTP_409_CONFLICT),
    )
    app.add_exception_handler(
        RepositoryValidationError,
        _domain_error_handler(status.HTTP_422_UNPROCESSABLE_ENTITY),
    )
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
    app.include_router(platform_router)
    app.include_router(events_router)
    app.include_router(schedule_router)
    app.include_router(settings_router)
    app.include_router(rescue_router)
    app.include_router(microtasks_router)
    app.include_router(review_router)
    app.include_router(emotion_router)
    app.include_router(goals_router)
    app.include_router(team_router)
    app.include_router(sync_router)
    app.include_router(reserved_router)

    return app


app = create_app()
