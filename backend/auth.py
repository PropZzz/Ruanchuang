from __future__ import annotations

from pathlib import Path

from fastapi import Header, HTTPException, Request, status

from .session_store import SessionStore
from .settings import DEFAULT_SESSION_TTL_SECONDS


def issue_token(
    user_id: str, db_path: str | Path | None = None,
    *, ttl_seconds: int = DEFAULT_SESSION_TTL_SECONDS,
) -> str:
    return SessionStore(db_path).issue(user_id, ttl_seconds)


def resolve_token(token: str, db_path: str | Path | None = None) -> str | None:
    return SessionStore(db_path).resolve(token)


def revoke_token(token: str, db_path: str | Path | None = None) -> None:
    SessionStore(db_path).revoke(token)


def current_user_id(request: Request, authorization: str | None = Header(default=None)) -> str:
    token = extract_bearer_token(authorization)
    if token is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    user_id = resolve_token(token, getattr(request.app.state, "db_path", None))
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
