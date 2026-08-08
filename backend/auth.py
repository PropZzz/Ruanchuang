from __future__ import annotations

from secrets import token_urlsafe
from threading import RLock

from fastapi import Header, HTTPException, status


_TOKEN_TO_USER_ID: dict[str, str] = {}
_LOCK = RLock()


def issue_token(user_id: str) -> str:
    token = token_urlsafe(32)
    with _LOCK:
        _TOKEN_TO_USER_ID[token] = user_id
    return token


def resolve_token(token: str) -> str | None:
    with _LOCK:
        return _TOKEN_TO_USER_ID.get(token)


def reset_token_store() -> None:
    with _LOCK:
        _TOKEN_TO_USER_ID.clear()


def current_user_id(authorization: str | None = Header(default=None)) -> str:
    token = extract_bearer_token(authorization)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    user_id = resolve_token(token)
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )
    return user_id


def extract_bearer_token(authorization: str | None) -> str | None:
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return None
    return token.strip()
