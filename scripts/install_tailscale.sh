#!/bin/sh

# install tailscale
# ubuntu/debian, x64/arm64
#
# Uses the official installer, which adds the apt repo and registers the
# tailscaled systemd service. Requires sudo. Idempotent: skips if already
# installed.
#
# Exit node mode (TAILSCALE_EXIT_NODE=1):
#   Enables IP forwarding and UDP GRO optimisation so this machine can act as a
#   Tailscale exit node (VPN-like routing for other devices).
#   After running, approve the exit node in the Tailscale admin console and run:
#     sudo tailscale up --advertise-exit-node

set -e

if command -v tailscale >/dev/null 2>&1; then
  echo "tailscale already installed: $(tailscale version | head -1)"
else
  echo "Installing tailscale (official installer)"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# Enable + start the daemon via systemd when available.
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now tailscaled 2>/dev/null \
    || echo "Could not enable tailscaled via systemd (is systemd running?)."
fi

# Enable IP forwarding for exit node / subnet router use.
if [ "${TAILSCALE_EXIT_NODE:-0}" = "1" ]; then
  echo "Enabling IP forwarding for Tailscale exit node"
  SYSCTL_CONF=/etc/sysctl.d/99-tailscale.conf
  if [ ! -f "$SYSCTL_CONF" ]; then
    printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' \
      | sudo tee "$SYSCTL_CONF" >/dev/null
    sudo sysctl -p "$SYSCTL_CONF"
  else
    echo "IP forwarding already configured ($SYSCTL_CONF exists)"
  fi

  # UDP GRO forwarding — improves throughput on the primary NIC.
  # Detect the default route interface instead of hardcoding (e.g. ens3, eth0).
  DEF_IFACE=$(ip route show default 2>/dev/null | awk '/^default/ {print $5; exit}')
  if [ -n "$DEF_IFACE" ]; then
    echo "Enabling UDP GRO forwarding on $DEF_IFACE"
    sudo ethtool -K "$DEF_IFACE" rx-udp-gro-forwarding on rx-gro-list off 2>/dev/null \
      || echo "ethtool UDP GRO config failed (may not be supported on this NIC)"

    # Persist across reboots via networkd-dispatcher if available.
    DISPATCHER_DIR=/etc/networkd-dispatcher/routable.d
    DISPATCHER_SCRIPT="$DISPATCHER_DIR/50-tailscale"
    if [ -d "$DISPATCHER_DIR" ] && [ ! -f "$DISPATCHER_SCRIPT" ]; then
      printf '#!/bin/sh\nethtool -K %s rx-udp-gro-forwarding on rx-gro-list off\n' "$DEF_IFACE" \
        | sudo tee "$DISPATCHER_SCRIPT" >/dev/null
      sudo chmod +x "$DISPATCHER_SCRIPT"
      echo "UDP GRO persistence script written to $DISPATCHER_SCRIPT"
    fi
  else
    echo "Could not detect default interface; skip UDP GRO config"
  fi

  echo "Done. After authenticating, run: sudo tailscale up --advertise-exit-node"
  echo "Then approve the exit node at: https://login.tailscale.com/admin/machines"
fi

# Grant the current user operator rights so non-root tooling (e.g. Kiro Crew
# mobile access via `tailscale serve`) can change serve config without sudo.
# Only applies once the node is authenticated; otherwise we just note it.
if tailscale status >/dev/null 2>&1; then
  echo "Granting tailscale operator rights to '$USER'"
  sudo tailscale set --operator="$USER" \
    || echo "Could not set tailscale operator (is the node authenticated?)."
else
  echo "Node not authenticated yet; after 'sudo tailscale up' run:"
  echo "  sudo tailscale set --operator=\$USER"
fi

echo "tailscale installed. Run 'sudo tailscale up' to authenticate this machine."
