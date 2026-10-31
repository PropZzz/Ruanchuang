"""Small, explicit runtime configuration shared by application boundaries."""

from __future__ import annotations

from dataclasses import dataclass
import os
from urllib.parse import urlsplit


DEFAULT_SESSION_TTL_SECONDS = 7 * 24 * 60 * 60
DEFAULT_CORS_ORIGINS = (
    "http://8.133.250.216",
    "http://127.0.0.1:5353",
    "http://localhost:5353",
)


@dataclass(frozen=True)
class BackendSettings:
    session_ttl_seconds: int
    cors_origins: tuple[str, ...]


def load_settings() -> BackendSettings:
    ttl = int(os.getenv("SHIXUZHIPEI_SESSION_TTL_SECONDS", str(DEFAULT_SESSION_TTL_SECONDS)))
    if ttl <= 0:
        raise ValueError("SHIXUZHIPEI_SESSION_TTL_SECONDS must be a positive integer")

    configured = os.getenv("SHIXUZHIPEI_CORS_ORIGINS")
    candidates = DEFAULT_CORS_ORIGINS if configured is None else configured.split(",")
    origins: list[str] = []
    for raw in candidates:
        origin = raw.strip().rstrip("/")
        parsed = urlsplit(origin)
        if (
            parsed.scheme not in {"http", "https"} or not parsed.hostname
            or "*" in origin or parsed.path or parsed.query or parsed.fragment
            or parsed.username is not None or parsed.password is not None
        ):
            raise ValueError("SHIXUZHIPEI_CORS_ORIGINS must contain explicit HTTP(S) origins")
        # Validate the port as well as the URL shape.
        _ = parsed.port
        if origin not in origins:
            origins.append(origin)
    return BackendSettings(session_ttl_seconds=ttl, cors_origins=tuple(origins))
