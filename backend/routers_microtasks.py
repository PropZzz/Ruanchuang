from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request, Response, status

from .auth import current_user_id
from .repositories import (
    RepositoryConflictError,
    RepositoryNotFoundError,
    RepositoryValidationError,
    batch_complete_microtasks,
    batch_schedule_microtasks,
    delete_microtask,
    import_microtasks,
    list_microtasks,
    upsert_microtask,
)
from .schemas import (
    CrystalRecommendationOut,
    CrystalRecommendationRequest,
    MicroTaskIn,
    MicroTaskOut,
    MicroTaskBatchCompleteRequest,
    MicroTaskBatchScheduleRequest,
    MicroTaskImportRequest,
)
from .services_microtask import recommend_crystals


router = APIRouter(prefix="/microtasks", tags=["microtasks"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


@router.get("", response_model=list[MicroTaskOut])
def get_microtasks(request: Request, user_id: str = Depends(current_user_id)) -> list[dict[str, object]]:
    return list_microtasks(_db_path(request), user_id)


@router.post("", response_model=MicroTaskOut)
def create_microtask(
    payload: MicroTaskIn,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    return upsert_microtask(_db_path(request), user_id, payload.model_dump(mode="json", by_alias=True))


@router.put("/{task_id}", response_model=MicroTaskOut)
def update_microtask(
    task_id: str,
    payload: MicroTaskIn,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> dict[str, object]:
    data = payload.model_dump(mode="json", by_alias=True)
    data["id"] = task_id
    return upsert_microtask(_db_path(request), user_id, data)


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def remove_microtask(
    task_id: str,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> Response:
    delete_microtask(_db_path(request), user_id, task_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/recommend-crystals", response_model=list[CrystalRecommendationOut])
def recommend(payload: CrystalRecommendationRequest, user_id: str = Depends(current_user_id)) -> list[dict[str, object]]:
    return recommend_crystals(payload.model_dump(mode="json", by_alias=True))


def _map_error(exc: Exception) -> HTTPException:
    if isinstance(exc, RepositoryNotFoundError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    if isinstance(exc, RepositoryConflictError):
        return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
    return HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))


@router.post("/batch-complete", response_model=list[MicroTaskOut])
def batch_complete(payload: MicroTaskBatchCompleteRequest, request: Request, user_id: str = Depends(current_user_id)) -> list[dict[str, object]]:
    try:
        return batch_complete_microtasks(_db_path(request), user_id, payload.task_ids, payload.done)
    except (RepositoryNotFoundError, RepositoryConflictError) as exc:
        raise _map_error(exc) from exc


@router.post("/batch-schedule", response_model=list[dict[str, object]])
def batch_schedule(payload: MicroTaskBatchScheduleRequest, request: Request, user_id: str = Depends(current_user_id)) -> list[dict[str, object]]:
    try:
        return batch_schedule_microtasks(_db_path(request), user_id, payload.task_ids, payload.day.isoformat(), payload.start.model_dump())
    except (RepositoryNotFoundError, RepositoryConflictError) as exc:
        raise _map_error(exc) from exc


@router.post("/import", response_model=list[MicroTaskOut])
def import_tasks(payload: MicroTaskImportRequest, request: Request, user_id: str = Depends(current_user_id)) -> list[dict[str, object]]:
    try:
        return import_microtasks(_db_path(request), user_id, payload.text)
    except RepositoryValidationError as exc:
        raise _map_error(exc) from exc
