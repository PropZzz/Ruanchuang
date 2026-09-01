import os
from pathlib import Path
import sqlite3


DEFAULT_DB_PATH = Path(__file__).resolve().parent / "data" / "shixuzhipei.db"
DB_PATH_ENV_VAR = "SHIXUZHIPEI_DB_PATH"


def get_database_path() -> Path:
    override = os.getenv(DB_PATH_ENV_VAR)
    if override:
        return Path(override).expanduser()
    return DEFAULT_DB_PATH


def get_connection(db_path: str | Path | None = None) -> sqlite3.Connection:
    path = Path(db_path) if db_path is not None else get_database_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    return sqlite3.connect(path)
