"""Back up and restore SQLite through its online backup API, including WAL."""

from __future__ import annotations

import argparse
from contextlib import closing
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import time


def inspect_database(database: Path) -> dict:
    database = Path(database).resolve(strict=True)
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)) as connection:
        integrity = [row[0] for row in connection.execute("PRAGMA integrity_check")]
        if integrity != ["ok"]:
            raise ValueError("SQLite integrity check failed")
        names = [row[0] for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )]
        counts = {}
        for name in names:
            quoted = '"' + name.replace('"', '""') + '"'
            counts[name] = connection.execute("SELECT count(*) FROM " + quoted).fetchone()[0]
    return {"database": str(database), "integrity": "ok", "counts": counts}


def _copy_database(source: Path, target: Path, timeout_seconds: float) -> None:
    if timeout_seconds <= 0:
        raise ValueError("Backup timeout must be positive")
    deadline = time.monotonic() + timeout_seconds

    def progress(_status: int, _remaining: int, _total: int) -> None:
        if time.monotonic() > deadline:
            raise TimeoutError("SQLite backup exceeded its time budget")

    with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)) as reader:
        with closing(sqlite3.connect(target, timeout=min(1.0, timeout_seconds))) as writer:
            reader.backup(writer, pages=256, progress=progress, sleep=0.01)


def backup_database(database: Path, directory: Path, *, timeout_seconds: float = 30.0) -> dict:
    database = Path(database).resolve(strict=True)
    directory = Path(directory).resolve()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    descriptor, filename = tempfile.mkstemp(prefix=f"{database.stem}-{stamp}-", suffix=".sqlite3", dir=directory)
    os.close(descriptor)
    target = Path(filename).resolve()
    if not target.is_relative_to(directory):
        raise ValueError("Backup target must stay inside the requested directory")
    try:
        _copy_database(database, target, timeout_seconds)
        return inspect_database(target)
    except BaseException:
        target.unlink(missing_ok=True)
        raise


def restore_database(
    backup: Path, database: Path, *, backup_directory: Path | None = None,
    timeout_seconds: float = 30.0,
) -> dict:
    backup = Path(backup).resolve(strict=True)
    database = Path(database).resolve()
    if backup == database:
        raise ValueError("Restore source and target must be different files")
    expected = inspect_database(backup)
    previous = None
    if database.exists():
        previous = backup_database(
            database, backup_directory or database.parent / "restore-backups",
            timeout_seconds=timeout_seconds,
        )
    database.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        _copy_database(backup, database, timeout_seconds)
        restored = inspect_database(database)
        if restored["counts"] != expected["counts"]:
            raise ValueError("Restored table counts differ from the validated backup")
    except BaseException:
        if previous is not None:
            _copy_database(Path(previous["database"]), database, timeout_seconds)
        raise
    return {**restored, "source": str(backup), "previousBackup": previous}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    operations = parser.add_subparsers(dest="operation", required=True)
    inspect = operations.add_parser("inspect")
    inspect.add_argument("database", type=Path)
    save = operations.add_parser("backup")
    save.add_argument("database", type=Path)
    save.add_argument("--directory", required=True, type=Path)
    restore = operations.add_parser("restore")
    restore.add_argument("backup", type=Path)
    restore.add_argument("--database", required=True, type=Path)
    restore.add_argument("--backup-directory", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.operation == "inspect":
            result = inspect_database(args.database)
        elif args.operation == "backup":
            result = backup_database(args.database, args.directory)
        else:
            result = restore_database(args.backup, args.database, backup_directory=args.backup_directory)
    except (OSError, sqlite3.Error, ValueError, TimeoutError) as error:
        parser.exit(1, f"Database operation failed: {error}\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
