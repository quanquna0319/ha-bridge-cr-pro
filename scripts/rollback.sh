#!/bin/sh
# rollback.sh -- return to the pristine upstream container (no runtime hook).
set -eu

ROOT=${HA_BRIDGE_ROOT:-/vol1/1000/docker/ha-bridge}
CNAME=${CONTAINER_NAME:-ha-bridge}
PORT=${APP_PORT:-18080}

cd "$ROOT"
docker compose -p "$CNAME" -f compose.yaml up -d --force-recreate
i=0
c=000
while [ "$i" -lt 60 ]; do
  c=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$PORT/health/ready" || true)
  [ "$c" = "200" ] && break
  i=$((i+1)); sleep 1
done
echo "health/ready=$c"
curl -s -m 8 "http://127.0.0.1:$PORT/api/v1/license/availability" | head -c 400; echo
echo "rolled back: the hook mount is gone, availability should read UNACTIVATED"
