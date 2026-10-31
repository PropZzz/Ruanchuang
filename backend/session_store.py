"""Persistent opaque bearer sessions, scoped to one application database."""

from __future__ import annotations

from contextlib import contextmanager
import hashlib
from pathlib import Path
from secrets import token_urlsafe
import sqlite3
import time
from typing import Iterator

from .database import get_connection
from .settings import DEFAULT_SESSION_TTL_SECONDS


def initialize_sessions(connection: sqlite3.Connection) -> None:
    connection.execute("""
        CREATE TABLE IF NOT EXISTS auth_sessions (
            token_hash TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    """)
    connection.execute("CREATE INDEX IF NOT EXISTS auth_sessions_expiry ON auth_sessions(expires_at)")


class SessionStore:
    def __init__(self, db_path: str | Path | None = None) -> None:
        self.db_path = db_path

    @contextmanager
    def _connection(self) -> Iterator[sqlite3.Connection]:
        connection = get_connection(self.db_path)
        try:
            connection.execute("PRAGMA foreign_keys = ON")
            initialize_sessions(connection)
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    @staticmethod
    def _hash(token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    def issue(self, user_id: str, ttl_seconds: int = DEFAULT_SESSION_TTL_SECONDS) -> str:
        if isinstance(ttl_seconds, bool) or not isinstance(ttl_seconds, int) or ttl_seconds <= 0:
            raise ValueError("Session lifetime must be a positive integer")
        token = token_urlsafe(32)
        now = int(time.time())
        with self._connection() as connection:
            connection.execute("DELETE FROM auth_sessions WHERE expires_at <= ?", (now,))
            connection.execute(
                "INSERT INTO auth_sessions(token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
                (self._hash(token), user_id, now, now + ttl_seconds),
            )
        return token

    def resolve(self, token: str) -> str | None:
        if not token:
            return None
        token_hash = self._hash(token)
        now = int(time.time())
        with self._connection() as connection:
            row = connection.execute(
                "SELECT user_id, expires_at FROM auth_sessions WHERE token_hash = ?", (token_hash,),
            ).fetchone()
            if row is None:
                return None
            if row[1] <= now:
                connection.execute("DELETE FROM auth_sessions WHERE token_hash = ?", (token_hash,))
                return None
            return str(row[0])

    def revoke(self, token: str) -> None:
        with self._connection() as connection:
            connection.execute("DELETE FROM auth_sessions WHERE token_hash = ?", (self._hash(token),))
