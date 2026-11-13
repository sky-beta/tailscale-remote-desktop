#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${VLESS_WORKFLOW_UUID:?missing VLESS UUID}"
: "${TUNNEL_TOKEN:?missing tunnel token}"
work="$HOME/.sky-workflow-services"
mkdir -p "$work"
cd "$work"
unzip -oq "$RUNNER_TEMP/xray.zip" xray
cp "$RUNNER_TEMP/cloudflared" ./cloudflared
chmod 700 xray cloudflared
python3 - <<'PY'
import json, os
cfg = {
    'log': {'loglevel': 'warning'},
    'inbounds': [{'listen':'0.0.0.0','port':3837,'protocol':'vless',
        'settings':{'clients':[{'id':os.environ['VLESS_WORKFLOW_UUID']}], 'decryption':'none'},
        'streamSettings':{'network':'ws','security':'none','wsSettings':{'path':'/vless'}}}],
    'outbounds':[{'protocol':'freedom','tag':'direct'}]
}
with open(os.path.expanduser('~/.sky-workflow-services/xray.json'),'w') as f: json.dump(cfg,f)
PY
./xray run -test -config "$work/xray.json"
nohup ./xray run -config "$work/xray.json" >"$work/xray.log" 2>&1 </dev/null &
nohup ./cloudflared tunnel --no-autoupdate run >"$work/cloudflared.log" 2>&1 </dev/null &
for port in 5244 3837; do
  ready=0
  for i in $(seq 1 20); do if nc -z 127.0.0.1 "$port"; then ready=1; break; fi; sleep 1; done
  [ "$ready" -eq 1 ] || { echo "Port $port did not start"; exit 1; }
done
echo 'AList and VLESS listeners are running.'
