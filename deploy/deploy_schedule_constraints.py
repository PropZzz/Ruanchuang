"""Deploy reviewed schedule API increments with source and SQLite backups."""
import argparse
import getpass
import hashlib
import json
from pathlib import Path
import subprocess

import paramiko


ROOT = Path(__file__).resolve().parents[1]
FILES = ["schemas.py", "repositories.py", "routers_schedule.py", "services_rescue.py"]


def run(client, source):
    stdin, stdout, stderr = client.exec_command("python3 -", timeout=120)
    stdin.write(source)
    stdin.channel.shutdown_write()
    output, error = stdout.read().decode(), stderr.read().decode()
    code = stdout.channel.recv_exit_status()
    if error:
        print(error)
    if code:
        raise RuntimeError(output + error)
    return output


def prepare(previous, stage, base_directory=None, resolved_directory=None):
    """Merge this change onto the inspected server source, retaining its other differences."""
    stage.mkdir(parents=True, exist_ok=True)
    normalize = lambda data: data.replace(b"\r\n", b"\n").replace(b"\r", b"")
    for name in FILES:
        source = normalize((previous / name).read_bytes())
        resolved = resolved_directory / name if resolved_directory else None
        if resolved and resolved.is_file():
            if normalize(resolved.with_suffix('.py.before').read_bytes()) != source:
                raise RuntimeError("Server changed since manual merge: " + name)
            merged = normalize(resolved.read_bytes())
        elif name == "routers_schedule.py" and base_directory is None:
            text = source.decode("utf-8")
            assert text.count('model_dump(mode="json", by_alias=True)') == 3
            text = text.replace('payload.model_dump(mode="json", by_alias=True)', 'payload.persistence_payload()')
            text = text.replace('item.model_dump(mode="json", by_alias=True)', 'item.persistence_payload()')
            merged = text.encode("utf-8")
        else:
            before, base, local = [stage / (name + suffix) for suffix in (".before", ".base", ".local")]
            before.write_bytes(source)
            baseline = ((base_directory / name).read_bytes() if base_directory else
                        subprocess.check_output(["git", "show", "HEAD:backend/" + name], cwd=ROOT))
            base.write_bytes(normalize(baseline))
            local.write_bytes(normalize((ROOT / "backend" / name).read_bytes()))
            result = subprocess.run(["git", "merge-file", "-p", str(before), str(base), str(local)], capture_output=True)
            if result.returncode:
                raise RuntimeError("Server merge conflict: " + name)
            merged = result.stdout
        compile(merged, str(stage / name), "exec")
        (stage / name).write_bytes(merged)


def main():
    global FILES
    parser = argparse.ArgumentParser()
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--change", choices=["schedule-constraints", "calendar-import"], default="schedule-constraints")
    parser.add_argument("--base-directory", type=Path, help="Source snapshot from before the current incremental change")
    parser.add_argument("--resolved-directory", type=Path, help="Reviewed merges plus matching .py.before server snapshots")
    args = parser.parse_args()
    if args.change == "calendar-import":
        FILES = [*FILES, "routers_rescue.py"]
        if not args.inspect and args.base_directory is None:
            parser.error("calendar-import requires --base-directory with the pre-change local source")
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.connect("8.133.250.216", username="root", password=getpass.getpass("SSH password: "),
                   look_for_keys=False, allow_agent=False, timeout=15)
    try:
        facts = json.loads(run(client, r'''
import hashlib, json, pathlib, subprocess
service = 'ruanchuang.service'
def prop(name):
    return subprocess.check_output(['systemctl', 'show', service, '--property='+name, '--value'], text=True).strip()
root = pathlib.Path(prop('WorkingDirectory')).resolve()
pid = int(prop('MainPID'))
assert pid > 0 and (root / 'backend/main.py').is_file(), 'Unexpected backend service layout'
env = dict(item.split(b'=',1) for item in pathlib.Path(f'/proc/{pid}/environ').read_bytes().split(b'\0') if b'=' in item)
db = pathlib.Path(env.get(b'SHIXUZHIPEI_DB_PATH', str(root / 'backend/data/shixuzhipei.db').encode()).decode()).resolve()
print(json.dumps({'root': str(root), 'database': str(db), 'service': service,
                  'executable': str(pathlib.Path(f'/proc/{pid}/exe').resolve()),
                  'python': pathlib.Path(f'/proc/{pid}/cmdline').read_bytes().split(b'\0')[0].decode(),
                  'files': {name: hashlib.sha256((root/'backend'/name).read_bytes()).hexdigest()
                            for name in ['schemas.py','repositories.py','routers_schedule.py','services_rescue.py']}}))
'''))
        with client.open_sftp() as sftp:
            facts['files'] = {name: hashlib.sha256(sftp.open(f"{facts['root']}/backend/{name}", 'rb').read()).hexdigest()
                              for name in FILES}
        print(json.dumps(facts), flush=True)
        previous = ROOT / "build" / ("server-backend-before-" + args.change)
        previous.mkdir(parents=True, exist_ok=True)
        with client.open_sftp() as sftp:
            for name in FILES:
                sftp.get(f"{facts['root']}/backend/{name}", str(previous / name))
        if args.inspect:
            return
        stage = ROOT / "build" / ("backend-" + args.change + "-stage")
        prepare(previous, stage, args.base_directory, args.resolved_directory)
        upload = "/tmp/ruanchuang-" + args.change
        with client.open_sftp() as sftp:
            try:
                sftp.mkdir(upload)
            except IOError:
                pass
            for name in FILES:
                sftp.put(str(stage / name), upload + "/" + name)
        settings = {**facts, "upload": upload, "change": args.change,
                    "next": {name: hashlib.sha256((stage/name).read_bytes()).hexdigest() for name in FILES}}
        result = run(client, "settings = " + repr(settings) + "\n" + REMOTE_DEPLOY)
        print(result)
        (ROOT / "build" / ("backend-" + args.change + "-deployment.json")).write_text(result, encoding="utf-8")
    finally:
        client.close()


REMOTE_DEPLOY = r'''
import datetime, hashlib, json, os, pathlib, shutil, sqlite3, subprocess, tempfile, time, urllib.request
root = pathlib.Path(settings['root'])
assert root.is_relative_to('/opt/ruanchuang/releases')
backend = root / 'backend'
upload = pathlib.Path(settings['upload'])
for name, digest in settings['next'].items():
    assert hashlib.sha256((upload/name).read_bytes()).hexdigest() == digest, name
    assert hashlib.sha256((backend/name).read_bytes()).hexdigest() == settings['files'][name], 'Server changed: '+name
python = settings['python']
assert pathlib.Path(python).is_file()
with tempfile.TemporaryDirectory(prefix='schedule-constraints-', dir='/opt/ruanchuang') as directory:
    isolated = pathlib.Path(directory)
    shutil.copytree(backend, isolated/'backend', ignore=shutil.ignore_patterns('data','__pycache__','tests'))
    if (root/'contracts').exists(): (isolated/'contracts').symlink_to(root/'contracts', target_is_directory=True)
    for name in settings['next']: shutil.copy2(upload/name, isolated/'backend'/name)
    smoke = """
from pathlib import Path
from pydantic import ValidationError
from backend.main import create_app
from backend.schemas import ScheduleEntryIn
from backend.repositories import init_db, create_user, upsert_schedule, list_schedules
db = Path('isolated.sqlite3')
init_db(db)
user = create_user(db, 'smoke@isolated.local', 'Smoke', 'isolated-only')
for flexible, locked in [(False,False),(False,True),(True,False)]:
    item = ScheduleEntryIn(title='Smoke',tag='Work',rescheduleFlexible=flexible,hardLocked=locked)
    saved = upsert_schedule(db,user['id'],item.persistence_payload())
    assert saved['rescheduleFlexible'] is flexible and saved['hardLocked'] is locked
    old = ScheduleEntryIn(id=saved['id'],title='Updated',tag='Work')
    updated = upsert_schedule(db,user['id'],old.persistence_payload())
    assert updated['rescheduleFlexible'] is flexible and updated['hardLocked'] is locked
assert len(list_schedules(db,user['id'])) == 3
try:
    ScheduleEntryIn(title='Invalid',tag='Work',rescheduleFlexible=True,hardLocked=True)
except ValidationError:
    pass
else:
    raise AssertionError('Both constraints must not be enabled')
assert 'hardLocked' in create_app(db).openapi()['components']['schemas']['ScheduleEntryIn']['properties']
"""
    if settings['change'] == 'calendar-import':
        smoke += """
from backend.repositories import upsert_schedules_batch
item = ScheduleEntryIn(id='import-smoke', title='Course', tag='Study', description='Teacher / Room')
created = upsert_schedules_batch(db, user['id'], [item.persistence_payload()], create_only=True)
assert len(created) == 1 and created[0]['description'] == 'Teacher / Room'
edited = ScheduleEntryIn(id='import-smoke', title='Edited', tag='Study', description='Keep notes')
upsert_schedule(db, user['id'], edited.persistence_payload())
assert upsert_schedules_batch(db, user['id'], [item.persistence_payload()], create_only=True) == []
legacy = ScheduleEntryIn(id='import-smoke', title='Legacy', tag='Study')
assert upsert_schedule(db, user['id'], legacy.persistence_payload())['description'] == 'Keep notes'
schema = create_app(db).openapi()
assert 'description' in schema['components']['schemas']['ScheduleEntryIn']['properties']
assert any(p['name'] == 'createOnly' for p in schema['paths']['/schedule/batch']['post']['parameters'])
"""
    subprocess.run([python,'-c',smoke],cwd=isolated,check=True,capture_output=True)
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup = pathlib.Path('/opt/ruanchuang/backups') / (settings['change']+'-'+stamp)
backup.mkdir(parents=True, mode=0o700)
for name in settings['next']: shutil.copy2(backend/name,backup/name)
subprocess.run(['systemctl','stop',settings['service']],check=True)
try:
    with sqlite3.connect(settings['database']) as db, sqlite3.connect(backup/'database.sqlite3') as target:
        db.backup(target)
        assert target.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        counts = {table: db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0] for table in ['users','schedules']}
    for name in settings['next']:
        destination = backend/name
        info = destination.stat()
        pending = destination.with_suffix('.py.constraints-next')
        shutil.copyfile(upload/name,pending)
        os.chmod(pending,info.st_mode)
        os.chown(pending,info.st_uid,info.st_gid)
        os.replace(pending,destination)
    subprocess.run([python,'-c','from backend.repositories import init_db; init_db()'],cwd=root,
                   env={**os.environ,'SHIXUZHIPEI_DB_PATH':settings['database']},check=True,capture_output=True)
    with sqlite3.connect(settings['database']) as db:
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert counts == {table: db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0] for table in counts}
    subprocess.run(['systemctl','start',settings['service']],check=True)
    for attempt in range(30):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8000/health',timeout=3) as response:
                assert json.load(response)['ok'] is True
            with urllib.request.urlopen('http://127.0.0.1:8000/openapi.json',timeout=3) as response:
                fields = json.load(response)['components']['schemas']['ScheduleEntryIn']['properties']
                assert fields['hardLocked']['type'] == fields['rescheduleFlexible']['type'] == 'boolean'
                if settings['change'] == 'calendar-import': assert 'description' in fields
            break
        except Exception:
            if attempt == 29: raise
            time.sleep(.5)
except BaseException:
    subprocess.run(['systemctl','stop',settings['service']],check=True)
    for name in settings['next']: shutil.copy2(backup/name,backend/name)
    subprocess.run(['systemctl','start',settings['service']],check=True)
    raise
result = {'backup':str(backup),'source':str(root),'verifiedFiles':settings['next'],
          'isolatedServerSmoke':'passed','databaseIntegrity':'ok','countsPreserved':counts,'health':'ok'}
(backup/'result.json').write_text(json.dumps(result,indent=2))
print(json.dumps(result))
'''


if __name__ == "__main__":
    main()
