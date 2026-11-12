#!/bin/sh
# deploy.sh -- recreate ha-bridge with the cr-pro runtime hook mounted in.
#
# Env (all optional, defaults match the original work order):
#   HA_BRIDGE_ROOT  install root        (default /vol1/1000/docker/ha-bridge)
#   CONTAINER_NAME  container name      (default ha-bridge)
#   APP_PORT        published port      (default 18080)
set -eu

ROOT=${HA_BRIDGE_ROOT:-/vol1/1000/docker/ha-bridge}
CNAME=${CONTAINER_NAME:-ha-bridge}
PORT=${APP_PORT:-18080}
CRPRO="$ROOT/cr-pro"

cd "$ROOT"
echo "[1/3] verifying hook payloads"
test -f "$CRPRO/ha_bridge_pro.py"        || { echo "missing $CRPRO/ha_bridge_pro.py";        exit 1; }
test -f "$CRPRO/zzz_ha_bridge_pro.pth"   || { echo "missing $CRPRO/zzz_ha_bridge_pro.pth";   exit 1; }
test -f "$CRPRO/compose.override.yaml"   || { echo "missing $CRPRO/compose.override.yaml";   exit 1; }
chmod 0644 "$CRPRO/ha_bridge_pro.py" "$CRPRO/zzz_ha_bridge_pro.pth" "$CRPRO/compose.override.yaml"
# the hook line must stay one valid Python statement -- if quoting is lost, site.py
# silently skips the whole .pth and the container starts "unpatched" with no error.
grep -q 'sys.path.insert(0,_r)' "$CRPRO/zzz_ha_bridge_pro.pth" || {
  echo "FATAL: $CRPRO/zzz_ha_bridge_pro.pth lost its quoting; the hook would be skipped"; exit 1; }

echo "[2/3] recreating $CNAME with the override"
docker compose -p "$CNAME" -f compose.yaml -f cr-pro/compose.override.yaml up -d --force-recreate
i=0
c=000
while [ "$i" -lt 60 ]; do
  c=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$PORT/health/ready" || true)
  [ "$c" = "200" ] && break
  i=$((i+1)); sleep 1
done
echo "health/ready=$c"

echo "[3/3] making the gate log writable by the app user"
docker exec "$CNAME" sh -lc 'touch /data/cr-license-calls.log; chown ha-bridge:ha-bridge /data/cr-license-calls.log; chmod 0640 /data/cr-license-calls.log' 2>/dev/null || true
curl -s -m 8 "http://127.0.0.1:$PORT/api/v1/license/availability" | head -c 400; echo
