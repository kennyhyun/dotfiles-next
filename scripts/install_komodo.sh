#!/bin/sh
# Komodo Container Management Platform — optional installer
# Usage: install_komodo.sh [--uninstall]
#
# Config dir: ~/.config/komodo/
#   komodo.env, komodo-periphery.env, compose.yml

set -e

SERVICE_NAME="komodo"
KOMODO_DIR="$HOME/.config/komodo"
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

# ── ~/.config/komodo + compose.yml ───────────────────────────────────────────
install -d "$KOMODO_DIR"

CURRENT_UID="$(id -u)"

cat > "$COMPOSE_PATH" <<COMPOSE
name: komodo

services:
  traefik:
    image: traefik:v3
    container_name: traefik
    restart: unless-stopped
    command:
      - "--providers.docker=true"
      - "--providers.docker.endpoint=unix:///run/podman/podman.sock"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=ingress"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.web.http.redirections.entrypoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.scheme=https"
    environment:
      - DOCKER_HOST=unix:///run/podman/podman.sock
    volumes:
      - /run/user/$CURRENT_UID/podman/podman.sock:/run/podman/podman.sock:ro
    ports:
      - "80:80"
      - "443:443"
    networks:
      - ingress

  komodo-core:
    image: ghcr.io/moghtech/komodo-core:latest
    container_name: komodo-core
    restart: unless-stopped
    depends_on:
      - komodo-db
    env_file: $KOMODO_DIR/komodo.env
    ports:
      - "9120:9120"
    volumes:
      - komodo-data:/data
    networks:
      - ingress
      - komodo-internal

  komodo-periphery:
    image: ghcr.io/moghtech/komodo-periphery:latest
    container_name: komodo-periphery
    restart: unless-stopped
    env_file: $KOMODO_DIR/komodo-periphery.env
    environment:
      - DOCKER_HOST=unix:///run/podman/podman.sock
      - PERIPHERY_SSL_ENABLED=false
    volumes:
      - /run/user/$CURRENT_UID/podman/podman.sock:/run/podman/podman.sock:ro
      - $KOMODO_DIR:$KOMODO_DIR:ro
    networks:
      - komodo-internal

  komodo-db:
    image: docker.io/mongo:7
    container_name: komodo-db
    restart: unless-stopped
    volumes:
      - komodo-db:/data/db
    networks:
      - komodo-internal

networks:
  ingress:
    name: ingress
  komodo-internal:
    name: komodo-internal
    internal: true

volumes:
  komodo-data:
    name: komodo-data
  komodo-db:
    name: komodo-db
COMPOSE

echo "    compose.yml -> $COMPOSE_PATH"

# ── Check for missing env files ───────────────────────────────────────────────
ENV_MISSING=false
for f in komodo.env komodo-periphery.env; do
  [ ! -f "$KOMODO_DIR/$f" ] && ENV_MISSING=true
done

# ── podman socket (required for periphery to manage containers) ───────────────
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
timeout 5 systemctl --user enable --now podman.socket 2>/dev/null || true

# ── komodo network ────────────────────────────────────────────────────────────
podman network exists ingress 2>/dev/null || podman network create ingress

# ── systemd user service ──────────────────────────────────────────────────────
echo ">>> Installing systemd user service..."
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_FILE" <<UNIT
[Unit]
Description=Komodo Container Management Platform
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=-/usr/bin/podman network create komodo
ExecStart=/usr/bin/podman compose -f $COMPOSE_PATH up -d --remove-orphans
ExecStop=/usr/bin/podman compose -f $COMPOSE_PATH down
TimeoutStartSec=300

[Install]
WantedBy=default.target
UNIT

loginctl enable-linger "$(id -un)"

# Create enable symlink directly — no D-Bus needed, works in non-login shells
mkdir -p "$SERVICE_DIR/default.target.wants"
ln -sf "$SERVICE_FILE" "$SERVICE_DIR/default.target.wants/$SERVICE_NAME.service"

# Best-effort: reload systemd if user session is already running
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
timeout 5 systemctl --user daemon-reload 2>/dev/null || true

if $ENV_MISSING; then
  echo ">>> Service installed but NOT started — env files are missing."
  echo ""
  echo "    1. Create $KOMODO_DIR/komodo.env:"
  echo ""
  echo "       cat > $KOMODO_DIR/komodo.env <<'EOF'"
  echo "       KOMODO_HOST=http://<tailscale-ip>:9120"
  echo "       KOMODO_DATABASE_ADDRESS=komodo-db:27017"
  echo "       KOMODO_PASSKEY=<strong-passkey>"
  echo "       EOF"
  echo ""
  echo "    2. Create $KOMODO_DIR/komodo-periphery.env:"
  echo ""
  echo "       cat > $KOMODO_DIR/komodo-periphery.env <<'EOF'"
  echo "       PERIPHERY_PASSKEYS=<same-passkey>"
  echo "       PERIPHERY_ALLOWED_IPS=komodo-core"
  echo "       EOF"
  echo ""
  echo "    3. Start the service:"
  echo ""
  echo "       systemctl --user start $SERVICE_NAME"
  echo "       journalctl --user -u $SERVICE_NAME -f"
  echo ""
else
  timeout 30 systemctl --user start "$SERVICE_NAME" 2>/dev/null || \
    podman compose -f "$COMPOSE_PATH" up -d --remove-orphans
  echo ""
  echo ">>> Komodo installed!"
  echo "    Status: systemctl --user status $SERVICE_NAME"
  echo "    Logs:   journalctl --user -u $SERVICE_NAME -f"
  echo "    UI:     http://localhost:9120"
fi
