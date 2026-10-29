import getpass
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile

import paramiko

PROJECT_ROOT = Path(__file__).resolve().parents[1]

build = json.loads(subprocess.check_output(['node', str(PROJECT_ROOT / 'tools/build_stitch_web.mjs')], cwd=PROJECT_ROOT, text=True))
release = build['release']
output = Path(build['output'])
archive = PROJECT_ROOT / 'build' / f'stitch-{release}.tar.gz'
with tarfile.open(archive, 'w:gz') as tar:
    for file in sorted(output.rglob('*')):
        if file.is_file():
            tar.add(file, arcname=file.relative_to(output).as_posix())
archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
client = paramiko.SSHClient()
client.load_system_host_keys()
client.connect('8.133.250.216', username='root', password=getpass.getpass('SSH password: '), look_for_keys=False, allow_agent=False, timeout=15)
try:
    remote_archive = f'/tmp/ruanchuang-{release}.tar.gz'
    remote_config = f'/tmp/ruanchuang-{release}.nginx.conf'
    with client.open_sftp() as sftp:
        sftp.put(str(archive), remote_archive)
        sftp.put(str(PROJECT_ROOT / 'deploy/nginx-ruanchuang.conf'), remote_config)
    print(f'Uploaded release {release} ({archive.stat().st_size} bytes)', flush=True)
    settings = dict(release=release, archive=remote_archive, archive_hash=archive_hash, config=remote_config)
    remote = 'settings = ' + repr(settings) + '\n' + r'''
import datetime, hashlib, json, os, pathlib, shutil, subprocess, time, urllib.request
release = settings['release']
base = pathlib.Path('/opt/ruanchuang/web')
current = base / 'current'
assert current.is_symlink(), 'Current web root must be a symlink for atomic deployment'
previous = str(current.resolve())
archive = pathlib.Path(settings['archive'])
assert hashlib.sha256(archive.read_bytes()).hexdigest() == settings['archive_hash'], 'Upload checksum mismatch'
target = base / 'releases' / ('stitch-' + release)
if not target.exists():
    target.mkdir()
    subprocess.run(['tar', '-xzf', str(archive), '-C', str(target)], check=True)
manifest = json.loads((target / 'release.json').read_text())
assert manifest['release'] == release
for name, digest in manifest['files'].items():
    file = (target / name).resolve()
    assert file.is_relative_to(target), name
    assert hashlib.sha256(file.read_bytes()).hexdigest() == digest, name
config = pathlib.Path('/etc/nginx/sites-enabled/ruanchuang.conf').resolve()
stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
backup = base / 'backups' / (stamp + '-' + release)
backup.mkdir(parents=True)
shutil.copy2(config, backup / 'nginx.conf')
(backup / 'previous-release.txt').write_text(previous + '\n')
next_link = base / ('current.next-' + release)
try:
    shutil.copyfile(settings['config'], str(config) + '.next')
    os.replace(str(config) + '.next', config)
    subprocess.run(['nginx', '-t'], check=True)
    os.symlink(target, next_link)
    os.replace(next_link, current)
    subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
    for attempt in range(10):
        with urllib.request.urlopen('http://127.0.0.1/release.json', timeout=10) as response:
            observed_release = json.load(response)['release']
            observed_cache = response.headers.get('Cache-Control')
        if observed_release == release and observed_cache == 'no-store':
            break
        print('Waiting for Nginx workers:', observed_release, observed_cache, flush=True)
        time.sleep(0.5)
    else:
        raise RuntimeError(f'Release not ready: {observed_release}, Cache-Control={observed_cache}')
    with urllib.request.urlopen('http://127.0.0.1/health', timeout=10) as response:
        assert json.load(response)['ok'] is True
except BaseException:
    shutil.copy2(backup / 'nginx.conf', config)
    if next_link.is_symlink(): next_link.unlink()
    os.symlink(previous, next_link)
    os.replace(next_link, current)
    subprocess.run(['nginx', '-t'], check=True)
    subprocess.run(['systemctl', 'reload', 'nginx'], check=True)
    raise
print(json.dumps({'release': release, 'current': str(target), 'previous': previous, 'backup': str(backup), 'verified_files': len(manifest['files']), 'health': 'ok'}))
'''
    inp, out, err = client.exec_command('python3 -', timeout=60)
    inp.write(remote)
    inp.channel.shutdown_write()
    stdout = out.read().decode()
    stderr = err.read().decode()
    code = out.channel.recv_exit_status()
    print(stdout)
    print(stderr)
    (PROJECT_ROOT / 'build/deployment-result.txt').write_text(stdout + stderr, encoding='utf8')
    if code:
        raise SystemExit(code)
finally:
    client.close()
