#!/bin/sh
# cr-pro deploy: bring ha-bridge up with the runtime license unlock mounted in.
set -e
DIR=/vol1/1000/docker/ha-bridge
cd "$DIR"
echo "[1/3] verifying hook payloads"
test -f cr-pro/ha_bridge_pro.py || { echo "missing cr-pro/ha_bridge_pro.py"; exit 1; }
test -f cr-pro/zzz_ha_bridge_pro.pth || { echo "missing cr-pro/zzz_ha_bridge_pro.pth"; exit 1; }
test -f cr-pro/compose.override.yaml || { echo "missing cr-pro/compose.override.yaml"; exit 1; }
chmod 0644 cr-pro/ha_bridge_pro.py cr-pro/zzz_ha_bridge_pro.pth cr-pro/compose.override.yaml
grep -q 'sys.path.insert(0,_r)' cr-pro/zzz_ha_bridge_pro.pth || { echo "FATAL: .pth lost its quoting, patch would be silently skipped"; exit 1; }
echo "[2/3] recreating container with override"
docker compose -f compose.yaml -f cr-pro/compose.override.yaml up -d --force-recreate
i=0
while [ $i -lt 60 ]; do
  c=$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://127.0.0.1:18080/health/ready || true)
  [ "$c" = "200" ] && break
  i=$((i+1)); sleep 1
done
echo "health/ready=$c"
echo "[3/3] making the gate log writable by the app user"
docker exec ha-bridge sh -lc 'touch /data/cr-license-calls.log; chown ha-bridge:ha-bridge /data/cr-license-calls.log; chmod 0640 /data/cr-license-calls.log' 2>/dev/null || true
curl -s -m 8 http://127.0.0.1:18080/api/v1/license/availability; echo
