#!/bin/sh
# cr-pro rollback: restore the pristine upstream container, no runtime hook.
set -e
DIR=/vol1/1000/docker/ha-bridge
cd "$DIR"
docker compose -f compose.yaml up -d --force-recreate
i=0
while [ $i -lt 60 ]; do
  c=$(curl -s -o /dev/null -m 3 -w '%{http_code}' http://127.0.0.1:18080/health/ready || true)
  [ "$c" = "200" ] && break
  i=$((i+1)); sleep 1
done
echo "health/ready=$c"
curl -s -m 8 http://127.0.0.1:18080/api/v1/license/availability; echo
