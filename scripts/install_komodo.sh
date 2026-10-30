#!/bin/sh
# Komodo Container Management Platform — optional installer
# Usage: install_komodo.sh [--uninstall]
#
# Env files required in /etc/homelab/ before starting the service:
#   komodo.env, komodo-periphery.env

set -e

SERVICE_NAME="komodo"
HOMELAB_DIR="/etc/homelab"
KOMODO_DIR="$HOMELAB_DIR/komodo"
COMPOSE_PATH="$KOMODO_DIR/compose.yml"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME.service"

UNINSTALL=false
for arg in "$@"; do
  case $arg in
    --uninstall) UNINSTALL=true ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--uninstall]

  --uninstall  Stop and remove the service
EOF
      exit 0 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

# ── Uninstall ────────────────────────────────────────────────────────────────
if $UNINSTALL; then
  echo ">>> Removing Komodo service..."
  systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl --user daemon-reload
  echo ">>> Done."
  echo "    To remove volumes: podman compose -f $COMPOSE_PATH down -v"
  exit 0
fi

# ── Dependency check ─────────────────────────────────────────────────────────
for cmd in podman systemctl loginctl; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "ERROR: $cmd is not installed"; exit 1
  fi
done

if ! podman compose version > /dev/null 2>&1; then
  echo "ERROR: 'podman compose' not supported — install podman-compose package"
  exit 1
fi

# ── /etc/homelab/komodo + compose.yml ────────────────────────────────────────
sudo install -d "$KOMODO_DIR"

sudo tee "$COMPOSE_PATH" > /dev/null <<'COMPOSE'
name: komodo

services:
  komodo-core:
    image: ghcr.io/moghtech/komodo-core:latest
    container_name: komodo-core
    restart: unless-stopped
    depends_on:
      - komodo-db
    env_file: /etc/homelab/komodo.env
    ports:
      - "9120:9120"
    volumes:
      - komodo-data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.komodo.rule=Host(`komodo.yeoyou.net`)"
      - "traefik.http.routers.komodo.tls=true"
      - "traefik.http.services.komodo.loadbalancer.server.port=9120"
    networks:
      - homelab

  komodo-periphery:
    image: ghcr.io/moghtech/komodo-periphery:latest
    container_name: komodo-periphery
    restart: unless-stopped
    env_file: /etc/homelab/komodo-periphery.env
    volumes:
      - /run/user/1000/podman/podman.sock:/run/podman/podman.sock:ro
      - /etc/homelab:/etc/homelab:ro
    networks:
      - homelab

  komodo-db:
    image: mongo:7
    container_name: komodo-db
    restart: unless-stopped
    volumes:
      - komodo-db:/data/db
    networks:
      - homelab

networks:
  homelab:
    name: homelab
    external: true

volumes:
  komodo-data:
    name: komodo-data
  komodo-db:
    name: komodo-db
COMPOSE

echo "    compose.yml -> $COMPOSE_PATH"

# Check for missing env files
ENV_MISSING=false
for f in komodo.env komodo-periphery.env; do
  if [ ! -f "$HOMELAB_DIR/$f" ]; then
    echo "WARNING: $HOMELAB_DIR/$f not found"
    ENV_MISSING=true
  fi
done
if $ENV_MISSING; then
  echo ""
  echo "    Create the missing env files before starting the service."
  echo "    Minimal example for $HOMELAB_DIR/komodo.env:"
  echo "      KOMODO_HOST=https://komodo.yeoyou.net"
  echo "      KOMODO_PASSKEY=<strong-passkey>"
  echo "    Minimal example for $HOMELAB_DIR/komodo-periphery.env:"
  echo "      PERIPHERY_PASSKEYS=<same-passkey>"
  echo "      PERIPHERY_ALLOWED_IPS=komodo-core"
  echo ""
fi

# Fix podman socket path if UID != 1000
CURRENT_UID="$(id -u)"
if [ "$CURRENT_UID" != "1000" ]; then
  sudo sed -i "s|/run/user/1000|/run/user/$CURRENT_UID|g" "$COMPOSE_PATH"
  echo "    Patched podman socket path to /run/user/$CURRENT_UID"
fi

# ── homelab network ───────────────────────────────────────────────────────────
podman network exists homelab 2>/dev/null || podman network create homelab

# ── systemd user service ──────────────────────────────────────────────────────
echo ">>> Installing systemd user service..."
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_FILE" <<'UNIT'
[Unit]
Description=Komodo Container Management Platform
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/podman network create homelab
ExecStart=/usr/bin/podman compose -f /etc/homelab/komodo/compose.yml up -d --remove-orphans
ExecStop=/usr/bin/podman compose -f /etc/homelab/komodo/compose.yml down
TimeoutStartSec=300

[Install]
WantedBy=default.target
UNIT

systemctl --user daemon-reload
loginctl enable-linger "$(id -un)"
systemctl --user enable "$SERVICE_NAME"

if $ENV_MISSING; then
  echo ">>> Service installed but NOT started (env files missing)."
  echo "    After creating the env files, run:"
  echo "      systemctl --user start $SERVICE_NAME"
else
  systemctl --user start "$SERVICE_NAME"
  echo ""
  echo ">>> Komodo installed!"
  echo "    Status: systemctl --user status $SERVICE_NAME"
  echo "    Logs:   journalctl --user -u $SERVICE_NAME -f"
  echo "    UI:     http://localhost:9120"
fi
