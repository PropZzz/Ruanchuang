import os
from pathlib import Path
import sqlite3


DEFAULT_DB_PATH = Path(__file__).resolve().parent / "data" / "shixuzhipei.db"
DB_PATH_ENV_VAR = "SHIXUZHIPEI_DB_PATH"
CONNECT_TIMEOUT_SECONDS = 5.0
BUSY_TIMEOUT_MS = 5000


def get_database_path() -> Path:
    override = os.getenv(DB_PATH_ENV_VAR)
    if override:
        return Path(override).expanduser()
    return DEFAULT_DB_PATH


def _configure_connection(connection: sqlite3.Connection) -> sqlite3.Connection:
    """统一设置锁等待与日志模式。

    - ``timeout`` / ``busy_timeout``：并发写入时等待锁而不是立刻抛
      ``database is locked``；
    - ``journal_mode=WAL``：读写互不阻塞，符合后端守则“单实例写入 + WAL”的约定；
    - ``synchronous=NORMAL``：WAL 下的常规取舍，避免每次提交都强制刷盘。

    只读介质或内存库不支持 WAL 时保持默认日志模式，不影响读取。
    """
    connection.execute(f"PRAGMA busy_timeout = {BUSY_TIMEOUT_MS}")
    try:
        connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = NORMAL")
    except sqlite3.DatabaseError:
        pass
    return connection


def get_connection(db_path: str | Path | None = None) -> sqlite3.Connection:
    path = Path(db_path) if db_path is not None else get_database_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(path, timeout=CONNECT_TIMEOUT_SECONDS)
    return _configure_connection(connection)
