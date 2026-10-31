#!/usr/bin/env bash
# Bootstrap a NEW Linux backend host from a clean, reviewed Git checkout.
set -euo pipefail

source_root="$(realpath "${1:?Usage: sudo bash deploy/bootstrap_backend.sh SOURCE_ROOT [PREFIX]}")"
prefix="$(realpath -m "${2:-/opt/ruanchuang}")"
service_file=/etc/systemd/system/ruanchuang.service
if [[ "$(id -u)" != 0 ]]; then
  printf '%s\n' 'Run this bootstrap as root on the target Linux host.' >&2
  exit 1
fi
if [[ "$prefix" =~ [[:space:]] || -e "$service_file" ]]; then
  printf '%s\n' 'Use an application prefix without spaces; an existing backend service requires the reviewed update procedure.' >&2
  exit 1
fi
case "$prefix" in
  /opt/*|/srv/*|/var/lib/*) ;;
  *) printf '%s\n' 'Choose an application directory under /opt, /srv, or /var/lib.' >&2; exit 1 ;;
esac
python3 -c 'import sys; assert sys.version_info >= (3, 10), "Python 3.10+ is required"'
test -f "$source_root/backend/main.py"
test -d "$source_root/contracts/scheduling"
if [[ -n "$(git -C "$source_root" status --porcelain --untracked-files=normal)" ]]; then
  printf '%s\n' 'Commit and review the source checkout before creating a deployment release.' >&2
  exit 1
fi
revision="$(git -C "$source_root" rev-parse HEAD)"
release="$prefix/releases/$revision"
test ! -e "$release"
install -d -m 755 "$release" "$prefix/releases"
git -C "$source_root" archive --format=tar HEAD backend contracts deploy/database_maintenance.py | tar -xf - -C "$release"
python3 -m venv "$release/.venv"
"$release/.venv/bin/python" -m pip install -r "$release/backend/requirements.txt"
if ! getent group ruanchuang >/dev/null 2>&1; then
  groupadd --system ruanchuang
fi
if ! id ruanchuang >/dev/null 2>&1; then
  useradd --system --gid ruanchuang --no-create-home --home-dir "$prefix" --shell /usr/sbin/nologin ruanchuang
fi
install -d -m 700 -o ruanchuang -g ruanchuang "$prefix/data" "$prefix/backups"
test ! -e "$prefix/backend.env"
cat > "$prefix/backend.env" <<EOF
SHIXUZHIPEI_DB_PATH=$prefix/data/shixuzhipei.db
SHIXUZHIPEI_SESSION_TTL_SECONDS=604800
SHIXUZHIPEI_CORS_ORIGINS=http://8.133.250.216,http://127.0.0.1:5353,http://localhost:5353
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
EOF
chmod 600 "$prefix/backend.env"
cat > "$service_file" <<EOF
[Unit]
Description=Ruanchuang FastAPI backend
After=network.target

[Service]
User=ruanchuang
Group=ruanchuang
WorkingDirectory=$release
EnvironmentFile=$prefix/backend.env
ExecStart=$release/.venv/bin/python -m uvicorn backend.main:app --host 127.0.0.1 --port 8000 --workers 1
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$prefix/data $prefix/backups

[Install]
WantedBy=multi-user.target
EOF
systemd-analyze verify "$service_file"
systemctl daemon-reload
systemctl enable --now ruanchuang.service
if ! "$release/.venv/bin/python" -c 'import json,time,urllib.request
for attempt in range(30):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8000/health",timeout=2) as response:
            assert json.load(response)["ok"] is True
        break
    except Exception:
        if attempt == 29: raise
        time.sleep(1)
'; then
  systemctl stop ruanchuang.service
  printf '%s\n' 'Initial health check failed; the service is stopped. Inspect journalctl -u ruanchuang.service.' >&2
  exit 1
fi
printf 'Backend ready: revision=%s database=%s\n' "$revision" "$prefix/data/shixuzhipei.db"
