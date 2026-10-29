#!/bin/sh
# Komodo Container Management Platform — optional installer
# Usage: install_komodo.sh [--uninstall]
#
# Prerequisite: /etc/homelab/komodo/compose.yml must exist.
#   Clone the homelab repo and run this script, or place the compose.yml manually.
#
# Env files required in /etc/homelab/ before starting the service:
#   komodo.env, komodo-periphery.env  (see homelab/komodo/komodo.env.example)

set -e

SERVICE_NAME="komodo"
COMPOSE_PATH="/etc/homelab/komodo/compose.yml"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/$SERVICE_NAME.service"

UNINSTALL=false
for arg in "$@"; do
  case $arg in
    --uninstall) UNINSTALL=true ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--uninstall]

  --uninstall  서비스 중지 및 제거
EOF
      exit 0 ;;
    *) echo "알 수 없는 옵션: $arg"; exit 1 ;;
  esac
done

# ── 제거 ─────────────────────────────────────────────────────────────────────
if $UNINSTALL; then
  echo ">>> Komodo 서비스 제거 중..."
  systemctl --user disable --now "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl --user daemon-reload
  echo ">>> 완료."
  echo "    볼륨은 수동 제거: podman compose -f $COMPOSE_PATH down -v"
  exit 0
fi

# ── 의존성 확인 ───────────────────────────────────────────────────────────────
for cmd in podman systemctl loginctl; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "ERROR: $cmd 미설치"; exit 1
  fi
done

if ! podman compose version > /dev/null 2>&1; then
  echo "ERROR: 'podman compose' 미지원 — podman-compose 패키지 설치 필요"
  exit 1
fi

# ── compose.yml 확인 ─────────────────────────────────────────────────────────
if [ ! -f "$COMPOSE_PATH" ]; then
  echo "ERROR: $COMPOSE_PATH 없음"
  echo "       homelab 리포를 클론하고 compose.yml 을 배치하세요:"
  echo "       sudo install -d /etc/homelab/komodo"
  echo "       sudo cp <homelab-repo>/komodo/compose.yml $COMPOSE_PATH"
  exit 1
fi

# 환경 파일 경고
for f in komodo.env komodo-periphery.env; do
  if [ ! -f "/etc/homelab/$f" ]; then
    echo "WARNING: /etc/homelab/$f 없음 — 서비스 시작 전 설정 필요"
  fi
done

# UID 불일치 경고
CURRENT_UID="$(id -u)"
if grep -q "run/user/1000" "$COMPOSE_PATH" 2>/dev/null && [ "$CURRENT_UID" != "1000" ]; then
  echo "WARNING: compose.yml 의 /run/user/1000 경로가 현재 UID($CURRENT_UID)와 다름"
  echo "         수동으로 수정: sudo sed -i 's|/run/user/1000|/run/user/$CURRENT_UID|g' $COMPOSE_PATH"
fi

# ── homelab 네트워크 ─────────────────────────────────────────────────────────
podman network exists homelab 2>/dev/null || podman network create homelab

# ── systemd 유저 서비스 설치 ──────────────────────────────────────────────────
echo ">>> systemd 유저 서비스 설치 중..."
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

systemctl --user enable --now "$SERVICE_NAME"

echo ""
echo ">>> Komodo 설치 완료!"
echo "    상태:  systemctl --user status $SERVICE_NAME"
echo "    로그:  journalctl --user -u $SERVICE_NAME -f"
echo "    UI:    http://localhost:9120"
