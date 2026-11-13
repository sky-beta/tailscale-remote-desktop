#!/usr/bin/env bash
set -uo pipefail
work="$HOME/.sky-workflow-services"
: "${TUNNEL_TOKEN:?missing tunnel token}"
started_file="$RUNNER_TEMP/sky-job-started-at"
test -r "$started_file" || { echo 'Missing job start timestamp'; exit 1; }
deadline=$(( $(cat "$started_file") + ${SKY_MONITOR_SECONDS:-21180} ))
failures=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  if ! curl -fsS --max-time 5 http://127.0.0.1:5244/api/public/settings >/dev/null; then
    echo 'AList is not responding; restarting.'
    pkill -u "$(id -u)" -f '[a]list server --data' || true
    nohup "$work/alist" server --data "$work/alist-data" >"$work/alist.log" 2>&1 </dev/null &
  fi
  if ! nc -z -w 3 127.0.0.1 3837 >/dev/null 2>&1; then
    echo 'VLESS listener is not responding; restarting.'
    pkill -u "$(id -u)" -f '[x]ray run -config' || true
    nohup "$work/xray" run -config "$work/xray.json" >"$work/xray.log" 2>&1 </dev/null &
  fi
  if ! pgrep -u "$(id -u)" -f '[c]loudflared tunnel --no-autoupdate run' >/dev/null; then
    echo 'Cloudflare tunnel is not running; restarting.'
    nohup "$work/cloudflared" tunnel --no-autoupdate run >"$work/cloudflared.log" 2>&1 </dev/null &
  fi
  sleep 5
  if curl -fsS --max-time 5 http://127.0.0.1:5244/api/public/settings >/dev/null && nc -z -w 3 127.0.0.1 3837 >/dev/null 2>&1 && pgrep -u "$(id -u)" -f '[c]loudflared tunnel --no-autoupdate run' >/dev/null; then
    failures=0
  else
    failures=$((failures+1))
    echo "Local service health failure $failures/3."
    if [ "$failures" -ge 3 ]; then exit 1; fi
  fi
  sleep 25
done
echo 'Session reached its planned renewal time.'
