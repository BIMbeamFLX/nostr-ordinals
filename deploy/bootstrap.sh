#!/usr/bin/env bash
# One-shot, idempotent server bootstrap for the NORD prototype - designed
# to run in a SINGLE ssh session (hardware-key holders touch once):
#
#   ssh root@sec1.citadel-resources.com 'bash -s' < bootstrap.sh
#
# Installs docker if missing, clones/updates the repo under /opt/nord,
# writes a .env on first run (fresh NOSTR_SECRET_KEY via openssl), wires
# the single-host Caddyfile, and brings the stack up. Safe to re-run:
# existing .env and volumes are never touched.
#
# NOT done here, by design: `lncli create` - the wallet seed belongs in
# the operator's head and on their paper, not in a bootstrap log. The
# script prints the two commands to finish with.

set -euo pipefail

DOMAIN="${DOMAIN:-sec1.citadel-resources.com}"
REPO="https://github.com/BIMbeamFLX/nostr-ordinals"
DIR=/opt/nord

if ! command -v docker >/dev/null 2>&1; then
    echo "== installing docker =="
    curl -fsSL https://get.docker.com | sh
fi

if [ -d "$DIR/.git" ]; then
    git -C "$DIR" pull --ff-only
else
    git clone "$REPO" "$DIR"
fi
cd "$DIR/deploy"

if [ ! -f .env ]; then
    echo "== writing .env (first run) =="
    cat > .env <<EOF
DOMAIN=$DOMAIN
BASE_URL=https://$DOMAIN
USERNAME=mint
TITLE=600B mint
DESCRIPTION=NORD prototype - pay to mint a bearer note.
VERIFY_ENABLED=true
MIN_SENDABLE_MSAT=1000
MAX_SENDABLE_MSAT=21000000
NOSTR_SECRET_KEY=$(openssl rand -hex 32)
NOSTR_RELAYS=wss://$DOMAIN/relay
EOF
fi

# single-host routing (mint at /, relay at /relay, blossom at /blossom)
# unless the operator already switched to the subdomain Caddyfile
if ! grep -q "handle_path /relay" Caddyfile 2>/dev/null; then
    cp Caddyfile.singlehost Caddyfile
fi
mkdir -p blossom

echo "== bringing the stack up =="
docker compose up -d --build

echo
echo "== stack =="
docker compose ps
echo
echo "== finish by hand (wallet seed stays with you) =="
echo "  docker compose -f $DIR/deploy/docker-compose.yml exec lnd lncli create"
echo "  docker compose -f $DIR/deploy/docker-compose.yml exec lnd sh -c 'echo \"<wallet password>\" > /root/.lnd/unlock.txt'"
echo "  docker compose -f $DIR/deploy/docker-compose.yml restart lnd mint"
echo "  # then import the starters:"
echo "  docker compose -f $DIR/deploy/docker-compose.yml cp $DIR/deploy/set-600b-starters.json mint:/tmp/set.json"
echo "  docker compose -f $DIR/deploy/docker-compose.yml exec mint python -m lnurl_mint.assets import /tmp/set.json"
echo
echo "mint one-pager: https://$DOMAIN/  ·  relay: wss://$DOMAIN/relay  ·  blossom: https://$DOMAIN/blossom/<sha256>"
