#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${ALIST_RESTORE_JSON:?missing AList backup}"
: "${ALIST_BOOTSTRAP_PASSWORD:?missing AList password}"
: "${VLESS_WORKFLOW_UUID:?missing VLESS UUID}"
: "${TUNNEL_TOKEN:?missing tunnel token}"
work="$HOME/.sky-workflow-services"
mkdir -p "$work/alist-data"
printf '%s' "$ALIST_RESTORE_JSON" > "$work/backup.json"
export ALIST_BACKUP_PATH="$work/backup.json"
cd "$work"
tar -xzf "$RUNNER_TEMP/alist.tar.gz" alist
chmod 700 alist

# Initialize the database without exposing the generated password to Actions logs.
./alist server --data "$work/alist-data" >"$work/alist.log" 2>&1 &
alist_pid=$!
for i in $(seq 1 60); do [ -f "$work/alist-data/data.db" ] && break; sleep 1; done
test -f "$work/alist-data/data.db"
kill "$alist_pid" || true
wait "$alist_pid" || true
./alist admin set "$ALIST_BOOTSTRAP_PASSWORD" --data "$work/alist-data" >"$work/admin-init.log" 2>&1
nohup ./alist server --data "$work/alist-data" >"$work/alist.log" 2>&1 </dev/null &
python3 "$GITHUB_WORKSPACE/sky-workflow-services/restore.py"

if [ "${SKIP_NETWORK_TEST:-0}" = 1 ]; then
  echo 'Isolated restore test finished.'
else
  bash "$GITHUB_WORKSPACE/sky-workflow-services/start-network.sh"
fi
