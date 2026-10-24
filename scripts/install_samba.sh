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
