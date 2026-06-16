#!/usr/bin/env bash
#
# Build a production release and deploy it to the gameserver over ssh.
#
# Usage:
#   bin/deploy.sh                 # full build + deploy
#   bin/deploy.sh --config-only   # only push config/runtime.exs and restart
#
# Override the target with env vars:
#   DEPLOY_HOST=root@1.2.3.4 DEPLOY_DIR=/opt/zombi SERVICE=zombi bin/deploy.sh
#
set -euo pipefail

HOST="${DEPLOY_HOST:-root@167.235.65.196}"
DIR="${DEPLOY_DIR:-/opt/zombi}"
SERVICE="${SERVICE:-zombi}"
RELEASE_VSN="${RELEASE_VSN:-0.1.0}"
TARBALL="/tmp/zombi-release.tar.gz"

cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--config-only" ]]; then
  echo "==> Pushing config/runtime.exs only"
  scp config/runtime.exs "$HOST:$DIR/releases/$RELEASE_VSN/runtime.exs"
  ssh "$HOST" "systemctl restart $SERVICE && sleep 3 && systemctl is-active $SERVICE"
  echo "==> Done"
  exit 0
fi

echo "==> Building release (MIX_ENV=prod)"
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release --overwrite

echo "==> Packaging"
tar -czf "$TARBALL" -C _build/prod/rel/zombi .

echo "==> Copying to $HOST"
scp "$TARBALL" "$HOST:$TARBALL"

echo "==> Swapping in release and restarting $SERVICE"
ssh "$HOST" bash -se <<REMOTE
set -euo pipefail
systemctl stop $SERVICE
rm -rf $DIR/lib $DIR/releases $DIR/erts-* $DIR/bin
tar -xzf $TARBALL -C $DIR
systemctl start $SERVICE
sleep 5
systemctl is-active $SERVICE
REMOTE

echo "==> Deployed"
