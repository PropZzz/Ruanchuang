from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Header, Request, status

from .auth import current_user_id, extract_bearer_token, issue_token, resolve_token, revoke_token
from .repositories import (
    create_user,
    find_user_by_id,
    RepositoryNotFoundError,
    RepositoryValidationError,
    update_user_profile,
    verify_user,
)
from .schemas import ProfileUpdate, TokenResponse, UserCreate, UserLogin, UserOut


router = APIRouter(prefix="/auth", tags=["auth"])


def _db_path(request: Request):
    return getattr(request.app.state, "db_path", None)


def _public_user(user: dict[str, object]) -> UserOut:
    return UserOut.model_validate(user)


def _current_user(request: Request, authorization: str | None) -> UserOut:
    token = extract_bearer_token(authorization)
    if token is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing bearer token")

    user_id = resolve_token(token)
    if user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")

    user = find_user_by_id(_db_path(request), user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unknown user")
    return _public_user(user)


@router.post("/register", response_model=TokenResponse)
def register(payload: UserCreate, request: Request) -> TokenResponse:
    try:
        user = create_user(
            _db_path(request),
            payload.contact_address,
            payload.display_name,
            payload.password,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc

    token = issue_token(str(user["id"]))
    return TokenResponse(access_token=token, user=_public_user(user))


@router.post("/login", response_model=TokenResponse)
def login(payload: UserLogin, request: Request) -> TokenResponse:
    user = verify_user(_db_path(request), payload.contact_address, payload.password)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")

    token = issue_token(str(user["id"]))
    return TokenResponse(access_token=token, user=_public_user(user))


@router.get("/me", response_model=UserOut)
def me(request: Request, authorization: str | None = Header(default=None)) -> UserOut:
    return _current_user(request, authorization)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(authorization: str | None = Header(default=None)) -> None:
    token = extract_bearer_token(authorization)
    if token is None or resolve_token(token) is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    revoke_token(token)


@router.put("/profile", response_model=UserOut)
def profile(
    payload: ProfileUpdate,
    request: Request,
    user_id: str = Depends(current_user_id),
) -> UserOut:
    try:
        user = update_user_profile(_db_path(request), user_id, payload.display_name)
    except RepositoryNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    except RepositoryValidationError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc)) from exc
    return _public_user(user)
