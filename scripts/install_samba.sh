#!/bin/sh

# install samba (SMB/CIFS file sharing — the "NAS" protocol)
# ubuntu/debian, x64/arm64 ; Linux only
#
# SMB is the broadest-compatibility share protocol: Windows, macOS and Linux all
# mount it natively, so it is the right default for a mixed-client NAS. This
# installs the server (smbd/nmbd) and the client tools, enables the service, and
# stops there -- it does NOT create any shares or users, because a share path is
# host-specific (often a ZFS dataset). Define shares afterwards either in
# /etc/samba/smb.conf, or from the Cockpit "File Sharing" web UI
# (scripts/install_cockpit.sh).
#
# Requires sudo. Idempotent: skips the install if smbd already exists.
# Create an SMB login for an existing system user later with:
#     sudo smbpasswd -a <username>

set -e

if command -v smbd >/dev/null 2>&1; then
  echo "samba already installed: $(smbd --version 2>/dev/null | head -1)"
else
  echo "Installing samba (server + client tools)"
  sudo apt-get update
  # samba        = smbd/nmbd server. cifs-utils = mount.cifs client helper.
  sudo apt-get install -y samba cifs-utils
fi

# cockpit-file-sharing stores the SMB shares it manages in Samba's *registry*
# (a TDB DB) via `net conf`, not as text in smb.conf — that is what lets the web
# UI add/remove shares safely. For Samba to actually serve those shares, the
# [global] section must contain `include = registry`; without it the File
# Sharing panel warns "Samba is Misconfigured" and cannot manage SMB shares.
# We add the line only when Cockpit is (or is being) installed, so a plain Samba
# box without the web UI keeps a stock smb.conf. Idempotent: added once.
SMB_CONF="/etc/samba/smb.conf"
cockpit_present() {
  command -v cockpit-bridge >/dev/null 2>&1 || [ -d /usr/share/cockpit/file-sharing ]
}
if [ -f "$SMB_CONF" ] && cockpit_present \
   && ! grep -qE '^[[:space:]]*include[[:space:]]*=[[:space:]]*registry' "$SMB_CONF"; then
  echo "Enabling Samba registry shares for Cockpit File Sharing (include = registry)"
  sudo cp -a "$SMB_CONF" "$SMB_CONF.bak.$(date +%Y%m%d%H%M%S)"
  # Insert the include right after the first [global] header.
  if grep -qE '^\[global\]' "$SMB_CONF"; then
    sudo sed -i '0,/^\[global\]/s//[global]\n   include = registry/' "$SMB_CONF"
  else
    # No [global] section at all: append one.
    printf '\n[global]\n   include = registry\n' | sudo tee -a "$SMB_CONF" >/dev/null
  fi
  # Validate before reloading; roll back if testparm rejects the file.
  if sudo testparm -s "$SMB_CONF" >/dev/null 2>&1; then
    sudo systemctl reload smbd 2>/dev/null || sudo systemctl restart smbd 2>/dev/null || true
  else
    echo "WARNING: testparm rejected $SMB_CONF after adding include=registry; restoring backup."
    last_bak="$(ls -1t "$SMB_CONF".bak.* 2>/dev/null | head -1)"
    [ -n "$last_bak" ] && sudo cp -a "$last_bak" "$SMB_CONF"
  fi
fi

# Enable the SMB + NetBIOS name services so they start on boot.
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now smbd 2>/dev/null \
    || echo "Could not enable smbd via systemd (is systemd running?)."
  # nmbd (NetBIOS name resolution) is optional; enable it if the unit exists.
  sudo systemctl enable --now nmbd 2>/dev/null || true
fi

echo "samba installed (no shares defined yet)."
echo "  Add a share in /etc/samba/smb.conf or via the Cockpit File Sharing UI,"
echo "  then create an SMB password for a user:  sudo smbpasswd -a <username>"
