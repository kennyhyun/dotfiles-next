#!/bin/sh

# install suricata (network IDS / IPS)
# ubuntu/debian, x64/arm64 ; macOS via brew
#
# Suricata watches live network traffic and alerts on known-bad patterns
# (its ruleset). It does NOT scan files -- that is clamav's job. This script
# installs Suricata and fetches a ruleset (suricata-update, which pulls the
# free Emerging Threats Open set by default), but it does NOT start monitoring
# on its own: the interface to watch is host-specific, so you choose it.
#
# After install, point it at an interface and run:
#     sudo suricata-update                 # refresh rules (also done here)
#     ip -o link                           # list interface names
#     sudo suricata -i <iface> -D          # start as a daemon on <iface>
# Alerts land in /var/log/suricata/ (fast.log, eve.json).
# Requires sudo. Idempotent: skips the install if suricata already exists.

set -e

if command -v suricata >/dev/null 2>&1; then
  echo "suricata already installed: $(suricata --build-info 2>/dev/null | grep -i '^This is Suricata version' || suricata -V 2>/dev/null | head -1)"
else
  OS=$(uname -s)
  if [ "$OS" = "Darwin" ]; then
    echo "Installing suricata (brew)"
    brew install suricata
  else
    echo "Installing suricata"
    sudo apt-get update
    # suricata-update ships inside the suricata package on current Debian/Ubuntu.
    sudo apt-get install -y suricata
  fi
fi

# Fetch / refresh the ruleset so the engine has something to match against.
# This does NOT start any monitoring.
if command -v suricata-update >/dev/null 2>&1; then
  echo "Fetching Suricata ruleset (suricata-update)"
  sudo suricata-update 2>/dev/null \
    || echo "suricata-update reported an issue (you can re-run 'sudo suricata-update' later)."
fi

echo "suricata installed (NOT monitoring yet)."
echo "Start on an interface with:  ip -o link   then   sudo suricata -i <iface> -D"
