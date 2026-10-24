#!/bin/sh

# install nfs server (NFS file sharing — fast Linux/Unix-native NAS protocol)
# ubuntu/debian, x64/arm64 ; Linux only
#
# NFS is lighter and faster than SMB between Linux/Unix hosts, and is the usual
# datastore protocol for Proxmox / ESXi. Prefer it when every client is Linux;
# use Samba (scripts/install_samba.sh) when Windows/macOS clients are involved.
#
# This installs the kernel NFS server and enables it, but defines NO exports --
# an export path is host-specific (often a ZFS dataset). Add exports afterwards
# in /etc/exports (then `sudo exportfs -ra`), or from the Cockpit "File Sharing"
# web UI (scripts/install_cockpit.sh). Example /etc/exports line:
#     /tank/share  192.168.0.0/24(rw,sync,no_subtree_check)
#
# Requires sudo. Idempotent: skips the install if the server is already present.

set -e

if dpkg -s nfs-kernel-server >/dev/null 2>&1; then
  echo "nfs-kernel-server already installed."
else
  echo "Installing nfs-kernel-server"
  sudo apt-get update
  sudo apt-get install -y nfs-kernel-server
fi

# Enable the server so it starts on boot. (The service is a no-op until
# /etc/exports lists at least one export.)
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now nfs-server 2>/dev/null \
    || echo "Could not enable nfs-server via systemd (is systemd running?)."
fi

echo "nfs-kernel-server installed (no exports defined yet)."
echo "  Add an export to /etc/exports, then:  sudo exportfs -ra"
echo "  Or manage exports from the Cockpit File Sharing UI."
