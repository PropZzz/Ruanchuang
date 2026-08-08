from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response, status

from .auth import current_user_id
from .repositories import delete_microtask, list_microtasks, upsert_microtask
from .schemas import (
    CrystalRecommendationOut,
    CrystalRecommendationRequest,
    MicroTaskIn,
    MicroTaskOut,
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
