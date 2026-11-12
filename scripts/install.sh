#!/bin/sh
# install.sh -- one-shot installer for HA Bridge 0.8.6 + cr-pro runtime unlock
#
# Usage:  sudo sh scripts/install.sh
#
# Env:
#   HA_BRIDGE_ROOT=/opt/ha-bridge   install root            (default /vol1/1000/docker/ha-bridge)
#   APP_PORT=18080                  published port          (default 18080)
#   SKIP_IMAGE=1                    image already present, skip download/load
#   FORCE=1                         overwrite an existing compose.yaml
#   TAG=v0.8.6-cr-pro.1             release tag to fetch the image from
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/.." && pwd)

ROOT=${HA_BRIDGE_ROOT:-/vol1/1000/docker/ha-bridge}
DATA="$ROOT/data"
SECRETS="$ROOT/secrets"
CRPRO="$ROOT/cr-pro"
PORT=${APP_PORT:-18080}
TAG=${TAG:-v0.8.6-cr-pro.1}
REPO=${REPO:-quanquna0319/ha-bridge-cr-pro}
IMG_TARBALL=ha_bridge_0.8.6_amd64.tar.gz
IMAGE_REF=crpi-w1apw3w3zzp43y80.cn-shanghai.personal.cr.aliyuncs.com/weidaye1122/ha_bridge:latest
SP_DEFAULT=/opt/venv/lib/python3.12/site-packages

say() { printf "[cr-pro] %s\n" "$*"; }
die() { printf "[cr-pro] ERROR: %s\n" "$*" >&2; exit 1; }

# ---------- 0. preflight ----------
[ "$(id -u)" = "0" ] || die "run as root: sudo sh scripts/install.sh"
command -v docker >/dev/null 2>&1 || die "docker not found"
docker compose version >/dev/null 2>&1 || die "docker compose plugin not found"
command -v curl >/dev/null 2>&1 || die "curl not found"
for f in "$SRC/patches/ha_bridge_pro.py" "$SRC/patches/zzz_ha_bridge_pro.pth" \
         "$SRC/scripts/deploy.sh" "$SRC/scripts/rollback.sh" "$SRC/scripts/restore-admin.sh"; do
  [ -f "$f" ] || die "missing $f -- run this from the cloned repository"
done
say "install root: $ROOT  port: $PORT"

# ---------- 1. image ----------
IMG_OK=0
if docker image inspect "$IMAGE_REF" >/dev/null 2>&1; then
  IMG_OK=1; say "image already present: $IMAGE_REF"
fi
if [ "$IMG_OK" = "0" ] && [ "${SKIP_IMAGE:-0}" != "1" ]; then
  TMP=$(mktemp -d)
  URL="https://github.com/$REPO/releases/download/$TAG/$IMG_TARBALL"
  say "downloading $URL"
  if curl -fL --retry 3 --retry-delay 2 -o "$TMP/$IMG_TARBALL" "$URL"; then
    say "verifying sha256"
    ( cd "$TMP" && curl -fsSL -o SHA256SUMS \
        "https://github.com/$REPO/releases/download/$TAG/SHA256SUMS" \
      && sha256sum -c SHA256SUMS --ignore-missing ) || die "checksum verification failed"
    say "docker load"
    docker load -i "$TMP/$IMG_TARBALL" && IMG_OK=1 || true
    rm -rf "$TMP"
  else
    rm -rf "$TMP"
    say "release download failed, trying the upstream registry"
    docker pull "$IMAGE_REF" && IMG_OK=1 || true
  fi
fi
[ "$IMG_OK" = "1" ] || die "no usable image -- pull $IMAGE_REF manually, then rerun with SKIP_IMAGE=1"

# ---------- 2. directories ----------
mkdir -p "$DATA" "$SECRETS" "$CRPRO"
chmod 0700 "$DATA" "$SECRETS" 2>/dev/null || true

# ---------- 3. compose.yaml ----------
if [ -f "$ROOT/compose.yaml" ] && [ "${FORCE:-0}" != "1" ]; then
  say "keeping existing $ROOT/compose.yaml"
  cp -p "$ROOT/compose.yaml" "$ROOT/compose.yaml.cr-bak.$(date +%Y%m%d-%H%M%S)"
else
  [ -f "$ROOT/compose.yaml" ] && cp -p "$ROOT/compose.yaml" "$ROOT/compose.yaml.cr-bak" || true
  cat > "$ROOT/compose.yaml" <<YAML
services:
  ha-bridge:
    image: crpi-w1apw3w3zzp43y80.cn-shanghai.personal.cr.aliyuncs.com/weidaye1122/ha_bridge:latest
    container_name: ha-bridge
    user: root
    restart: unless-stopped
    network_mode: host
    environment:
      APP_PORT: 18080
    volumes:
      - /vol1/1000/docker/ha-bridge/data:/data
      - /vol1/1000/docker/ha-bridge/secrets:/run/secrets
YAML
  say "wrote $ROOT/compose.yaml"
fi

# honour a custom root by rewriting the two volume paths
if [ "$ROOT" != "/vol1/1000/docker/ha-bridge" ]; then
  sed -i "s#/vol1/1000/docker/ha-bridge#$ROOT#g" "$ROOT/compose.yaml"
fi

# ---------- 4. patch payload ----------
cp "$SRC/patches/ha_bridge_pro.py"      "$CRPRO/ha_bridge_pro.py"
cp "$SRC/patches/zzz_ha_bridge_pro.pth" "$CRPRO/zzz_ha_bridge_pro.pth"
for s in deploy.sh rollback.sh restore-admin.sh; do
  cp "$SRC/scripts/$s" "$CRPRO/$s"
done
chmod 0644 "$CRPRO/ha_bridge_pro.py" "$CRPRO/zzz_ha_bridge_pro.pth"
chmod 0755 "$CRPRO/deploy.sh" "$CRPRO/rollback.sh" "$CRPRO/restore-admin.sh"

# ---------- 5. site-packages probe ----------
SP="$SP_DEFAULT"
DETECTED=$(docker run --rm --entrypoint python "$IMAGE_REF" -c \
  'import sys;print([p for p in sys.path if p.endswith("site-packages")][0])' 2>/dev/null || true)
if [ -n "${DETECTED:-}" ]; then SP="$DETECTED"; fi
say "site-packages: $SP"

cat > "$CRPRO/compose.override.yaml" <<YAML
services:
  ha-bridge:
    volumes:
      - $CRPRO/ha_bridge_pro.py:$SP/ha_bridge_pro.py:ro
      - $CRPRO/zzz_ha_bridge_pro.pth:$SP/zzz_ha_bridge_pro.pth:ro
YAML
say "patch files installed into $CRPRO"

# ---------- 6. deploy ----------
sh "$CRPRO/deploy.sh"

say "ready: http://127.0.0.1:$PORT/login"
say "rollback: sh $CRPRO/rollback.sh"
