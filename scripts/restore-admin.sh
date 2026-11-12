#!/bin/sh
# restore the original admin-account.json captured before the password reset
set -e
D=/vol1/1000/docker/ha-bridge/data
test -f "$D/admin-account.json.cr-bak" || { echo "no backup present"; exit 1; }
cp -a "$D/admin-account.json.cr-bak" "$D/admin-account.json"
chown ha-bridge:ha-bridge "$D/admin-account.json" 2>/dev/null || true
chmod 600 "$D/admin-account.json"
docker restart ha-bridge >/dev/null
echo restored
