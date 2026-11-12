#!/bin/sh
# restore-admin.sh -- restore the admin-account.json captured before the password reset.
set -eu

ROOT=${HA_BRIDGE_ROOT:-/vol1/1000/docker/ha-bridge}
CNAME=${CONTAINER_NAME:-ha-bridge}
D="$ROOT/data"
BAK="$D/admin-account.json.cr-bak"
test -f "$BAK" || { echo "no backup at $BAK"; exit 1; }
cp -a "$BAK" "$D/admin-account.json"
chown ha-bridge:ha-bridge "$D/admin-account.json" 2>/dev/null || true
chmod 600 "$D/admin-account.json"
docker restart "$CNAME" >/dev/null
echo "restored $D/admin-account.json from $BAK and restarted $CNAME"
