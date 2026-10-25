#!/bin/sh

# install cockpit (lightweight web admin UI)
# ubuntu/debian, x64/arm64 ; Linux only (no macOS)
#
# Cockpit is a thin, system-native web console: it is socket-activated (it only
# runs while a browser is connected, so it costs almost no RAM idle), keeps no
# state DB of its own, and exposes the OS's own systemd / networkd / journald /
# storage directly. That makes it a good fit for a memory-constrained box that
# just needs a NAS/admin UI without the weight of a full appliance OS.
#
# We also install cockpit-file-sharing (45Drives): a Cockpit plugin that manages
# Samba (SMB) and NFS shares from the web UI, including ZFS-backed paths. It is
# the piece that turns Cockpit into a NAS share manager.
#
# Requires sudo. Idempotent: skips the install if cockpit is already present.
# Listens on https://<host>:9090 once enabled.

set -e

# 45Drives GitHub releases API — we resolve the right .deb from it at runtime,
# because the asset name is version- AND distro-codename-specific
# (e.g. cockpit-file-sharing_4.6.3-1trixie_all.deb). A hardcoded URL 404s the
# moment they cut a new release, so don't hardcode one.
SHARING_API="https://api.github.com/repos/45Drives/cockpit-file-sharing/releases/latest"

if command -v cockpit-bridge >/dev/null 2>&1; then
  echo "cockpit already installed: $(cockpit-bridge --version 2>/dev/null | head -1)"
else
  echo "Installing cockpit (+ storage plugin)"
  sudo apt-get update
  # cockpit          = the web console + session broker (pulls cockpit-ws/-system)
  # cockpit-storaged = disk / filesystem management panel (ZFS mounts show here)
  sudo apt-get install -y cockpit cockpit-storaged
fi

# cockpit-file-sharing: Samba + NFS share manager plugin. Packaged by 45Drives,
# not in Debian's repos, so install the .deb if the module directory is absent.
# We pick the asset matching this box's distro codename (trixie/bookworm/jammy/
# focal); if none matches we fall back to any *_all.deb in the release.
if [ ! -d /usr/share/cockpit/file-sharing ]; then
  echo "Installing cockpit-file-sharing (Samba/NFS web manager)"
  codename="$( . /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-}" )"
  # Prefer this codename's .deb; else any Debian/Ubuntu .deb in the release.
  deb_url="$(curl -fsSL "$SHARING_API" 2>/dev/null \
    | grep -oE 'https://[^"]+\.deb' \
    | grep -E "(_${codename}_all\.deb|bookworm|trixie|jammy|focal)" \
    | grep -iE "${codename}" | head -1)"
  [ -n "$deb_url" ] || deb_url="$(curl -fsSL "$SHARING_API" 2>/dev/null \
    | grep -oE 'https://[^"]+_all\.deb' | head -1)"
  if [ -n "$deb_url" ]; then
    tmp="$(mktemp -d)"
    if curl -fsSL -o "$tmp/cockpit-file-sharing.deb" "$deb_url"; then
      # apt resolves the .deb's own deps (samba, nfs-kernel-server helpers).
      sudo apt-get install -y "$tmp/cockpit-file-sharing.deb" \
        || echo "cockpit-file-sharing install reported an issue (get it from https://github.com/45Drives/cockpit-file-sharing/releases)."
    else
      echo "Could not download cockpit-file-sharing from $deb_url; skipping."
    fi
    rm -rf "$tmp"
  else
    echo "No cockpit-file-sharing .deb found in the latest release; skipping (see https://github.com/45Drives/cockpit-file-sharing/releases)."
  fi
else
  echo "cockpit-file-sharing already present; skipping."
fi

# Verify the plugin actually landed. The download/install steps above swallow
# their own errors (|| echo) so one bad run does not abort the whole bootstrap;
# but that also means a silent skip once left Cockpit installed WITHOUT the
# share manager, and `chezmoi apply` still reported success. So check the end
# state explicitly and say so loudly if file-sharing is still missing, instead
# of letting it pass unnoticed.
if [ ! -d /usr/share/cockpit/file-sharing ]; then
  echo "WARNING: cockpit-file-sharing is NOT installed (the Samba/NFS share" >&2
  echo "         manager will be absent from the Cockpit UI). Re-run this" >&2
  echo "         script, or install the .deb for your distro codename from" >&2
  echo "         https://github.com/45Drives/cockpit-file-sharing/releases" >&2
fi

# cockpit-file-sharing manages SMB shares through Samba's registry (via
# `net conf`), which Samba only serves when `include = registry` is in the
# [global] section of /etc/samba/smb.conf. Without it the File Sharing panel
# shows "Samba is Misconfigured". Samba may be installed before OR after
# Cockpit, so guarantee the line here too whenever smb.conf exists. Idempotent.
SMB_CONF="/etc/samba/smb.conf"
if [ -d /usr/share/cockpit/file-sharing ] && [ -f "$SMB_CONF" ] \
   && ! grep -qE '^[[:space:]]*include[[:space:]]*=[[:space:]]*registry' "$SMB_CONF"; then
  echo "Enabling Samba registry shares for Cockpit File Sharing (include = registry)"
  sudo cp -a "$SMB_CONF" "$SMB_CONF.bak.$(date +%Y%m%d%H%M%S)"
  if grep -qE '^\[global\]' "$SMB_CONF"; then
    sudo sed -i '0,/^\[global\]/s//[global]\n   include = registry/' "$SMB_CONF"
  else
    printf '\n[global]\n   include = registry\n' | sudo tee -a "$SMB_CONF" >/dev/null
  fi
  if sudo testparm -s "$SMB_CONF" >/dev/null 2>&1; then
    sudo systemctl reload smbd 2>/dev/null || sudo systemctl restart smbd 2>/dev/null || true
  else
    echo "WARNING: testparm rejected $SMB_CONF after adding include=registry; restoring backup." >&2
    last_bak="$(ls -1t "$SMB_CONF".bak.* 2>/dev/null | head -1)"
    [ -n "$last_bak" ] && sudo cp -a "$last_bak" "$SMB_CONF"
  fi
fi

# Socket-activate cockpit: the .socket listens and spawns cockpit-ws on demand,
# so nothing runs until someone connects (the whole point of the "light" story).
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now cockpit.socket 2>/dev/null \
    || echo "Could not enable cockpit.socket via systemd (is systemd running?)."
fi

host="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo "cockpit installed. Open the web console at:  https://${host:-<this-host>}:9090"
echo "  (log in with your system user; it uses a self-signed cert on first run.)"
