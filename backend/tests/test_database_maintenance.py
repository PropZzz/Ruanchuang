from __future__ import annotations

from contextlib import closing
from pathlib import Path
import sqlite3

import pytest
from starlette.testclient import TestClient

from backend.main import create_app
from deploy.database_maintenance import backup_database, inspect_database, restore_database


def test_backup_restores_wal_data_business_rows_and_login(tmp_path):
    database = tmp_path / "live.sqlite3"
    account = {"contactAddress": "backup@example.test", "displayName": "Backup", "password": "secret123"}
    with TestClient(create_app(database)) as client:
        auth = client.post("/auth/register", json=account).json()
        headers = {"Authorization": f"Bearer {auth['accessToken']}"}
        entry = {"id": "backup-task", "title": "Original", "tag": "Work", "time": {"hour": 9, "minute": 0}}
        assert client.post("/schedule", json=entry, headers=headers).status_code == 200
        with closing(sqlite3.connect(database)) as writer:
            writer.execute("PRAGMA journal_mode=WAL")
            writer.execute("PRAGMA wal_autocheckpoint=0")
            writer.execute("CREATE TABLE backup_probe(value TEXT NOT NULL)")
            writer.execute("INSERT INTO backup_probe VALUES ('committed-in-wal')")
            writer.commit()
            assert Path(str(database) + "-wal").stat().st_size > 0
            saved = backup_database(database, tmp_path / "backups")
        assert saved["counts"]["users"] == 1
        assert saved["counts"]["schedules"] == 1
        assert saved["counts"]["auth_sessions"] == 1
        assert saved["counts"]["backup_probe"] == 1
        assert client.delete("/schedule/backup-task", headers=headers).status_code == 204

    restored = restore_database(Path(saved["database"]), database)
    assert restored["previousBackup"]["counts"]["schedules"] == 0
    assert restored["counts"] == saved["counts"]
    with TestClient(create_app(database)) as restarted:
        assert restarted.get("/auth/me", headers=headers).status_code == 200
        assert restarted.get("/schedule", headers=headers).json()[0]["title"] == "Original"
        assert restarted.post("/auth/login", json={"contactAddress": account["contactAddress"], "password": account["password"]}).status_code == 200


def test_invalid_restore_source_does_not_change_existing_database(tmp_path):
    database = tmp_path / "existing.sqlite3"
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE keep(value TEXT)")
        connection.execute("INSERT INTO keep VALUES ('unchanged')")
    before = inspect_database(database)
    corrupt = tmp_path / "corrupt.sqlite3"
    corrupt.write_bytes(b"not a sqlite database")

    with pytest.raises(sqlite3.DatabaseError):
        restore_database(corrupt, database)

    assert inspect_database(database) == before
    with sqlite3.connect(database) as connection:
        assert connection.execute("SELECT value FROM keep").fetchone()[0] == "unchanged"


def test_restore_rejects_using_the_destination_as_its_source(tmp_path):
    database = tmp_path / "same.sqlite3"
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE data(value TEXT)")
    with pytest.raises(ValueError, match="different"):
        restore_database(database, database)


def test_failed_restore_recovers_the_pre_operation_state(tmp_path, monkeypatch):
    import deploy.database_maintenance as maintenance

    source = tmp_path / "restore-source.sqlite3"
    database = tmp_path / "destination.sqlite3"
    for path, value in [(source, "backup"), (database, "current")]:
        with sqlite3.connect(path) as connection:
            connection.execute("CREATE TABLE data(value TEXT)")
            connection.execute("INSERT INTO data VALUES (?)", (value,))
    copy_database = maintenance._copy_database

    def fail_after_partial_write(reader, writer, timeout_seconds):
        if reader == source:
            with sqlite3.connect(writer) as connection:
                connection.execute("UPDATE data SET value = 'partial'")
            raise OSError("injected restore failure")
        return copy_database(reader, writer, timeout_seconds)

    monkeypatch.setattr(maintenance, "_copy_database", fail_after_partial_write)
    with pytest.raises(OSError, match="injected"):
        restore_database(source, database)
    with sqlite3.connect(database) as connection:
        assert connection.execute("SELECT value FROM data").fetchone()[0] == "current"
