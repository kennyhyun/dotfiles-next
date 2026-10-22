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

echo "tailscale installed. Run 'sudo tailscale up' to authenticate this machine."
