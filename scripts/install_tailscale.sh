#!/bin/sh

# install tailscale
# ubuntu/debian, x64/arm64
#
# Uses the official installer, which adds the apt repo and registers the
# tailscaled systemd service. Requires sudo. Idempotent: skips if already
# installed.

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
