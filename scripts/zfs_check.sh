#!/usr/bin/env bash
# zfs_check.sh — can this machine load the ZFS kernel module right now?
#
# Run it before `zpool import` (the install script also runs it after
# installing zfsutils-linux when WITH_ZFS=1).
#
# Why this exists: on Debian, ZFS is built locally by DKMS. With Secure Boot on,
# the kernel refuses a module signed by a key that is not enrolled in the MOK
# list, and `modprobe zfs` fails with "Key was rejected by service" (zpool then
# says "Failed to initialize the libzfs library"). Enrolling the DKMS key takes
# one reboot with console access, so we detect it early and print the steps.
#
# Exit codes:
#   0  ready, or nothing to enroll (see the printed hint)
#   1  action needed — guidance printed
#   2  zfsutils-linux (zpool) is not installed
#
# Override the DKMS public key path with DKMS_MOK_PUB=/path/to/mok.pub.

set -uo pipefail
PATH="$PATH:/usr/sbin:/sbin"

DKMS_PUB="${DKMS_MOK_PUB:-/var/lib/dkms/mok.pub}"

ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
say()  { printf '%s\n' "$*"; }

[ "$(uname -s)" = "Linux" ] || { say "zfs_check: not Linux; nothing to check."; exit 0; }

if ! command -v zpool >/dev/null 2>&1; then
  warn "zfs_check: zpool not found."
  say  "  Install it with: sudo apt-get install zfsutils-linux"
  exit 2
fi

# 1. Already loaded: nothing else to check.
if [ -d /sys/module/zfs ]; then
  ok "ZFS kernel module is loaded. 'sudo zpool import' should work."
  exit 0
fi

# 2. Secure Boot state: read the EFI variable (byte 5 is the flag), else mokutil.
sb_state() {
  [ -d /sys/firmware/efi ] || { echo off; return; }   # legacy BIOS boot
  local v flag
  v="$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -1)"
  if [ -n "$v" ]; then
    flag="$(od -An -t u1 -j4 -N1 "$v" 2>/dev/null | tr -d ' ')"
    case "$flag" in 1) echo on; return ;; 0) echo off; return ;; esac
  fi
  if command -v mokutil >/dev/null 2>&1; then
    case "$(mokutil --sb-state 2>&1)" in
      *"SecureBoot enabled"*)  echo on;  return ;;
      *"SecureBoot disabled"*) echo off; return ;;
    esac
  fi
  echo unknown
}
SB="$(sb_state)"

# 3. Is a module even built for the running kernel?
modpath="$(modinfo -n zfs 2>/dev/null || true)"
if [ -z "$modpath" ]; then
  warn "No zfs kernel module found for kernel $(uname -r)."
  say  "  Build it (needs headers for the running kernel):"
  say  "    sudo apt-get install dkms linux-headers-$(uname -r)"
  say  "    sudo dkms autoinstall"
  exit 1
fi

if [ "$SB" = "off" ]; then
  ok "Secure Boot is off — no signing needed."
  say "  Load it with: sudo modprobe zfs && sudo zpool import"
  exit 0
fi

# 4. Module shipped by the distro (not DKMS) is signed by the distro's key.
case "$modpath" in
  */updates/dkms/*) ;;   # locally built: its key must be enrolled by us
  *)
    ok "ZFS module comes from the distro (already trusted by Secure Boot)."
    say "  Load it with: sudo modprobe zfs && sudo zpool import"
    exit 0 ;;
esac

# 5. Locally built module + Secure Boot on (or unknown): is the DKMS key enrolled?
guidance() {
  warn "ZFS cannot load: Secure Boot is ${SB} and the DKMS signing key is not enrolled."
  say  ""
  say  "Do this once. It needs console access (monitor + keyboard, IPMI or KVM):"
  say  "  1. sudo mokutil --import $DKMS_PUB     (choose a one-time password)"
  say  "  2. sudo reboot"
  say  "  3. At the blue 'MOK management' screen:"
  say  "       Enroll MOK -> Continue -> Yes -> type the password -> Reboot"
  say  "  4. sudo modprobe zfs && sudo zpool import"
  say  ""
  say  "Undo later: sudo mokutil --delete $DKMS_PUB"
}

if [ ! -r "$DKMS_PUB" ]; then
  warn "DKMS signing key not found at $DKMS_PUB (the module may be unsigned)."
  say  "  Rebuild so DKMS creates and uses a key: sudo dkms autoinstall"
  exit 1
fi

if ! command -v mokutil >/dev/null 2>&1; then
  warn "mokutil is not installed, so the key state cannot be checked."
  say  "  sudo apt-get install mokutil"
  guidance
  exit 1
fi

if mokutil --test-key "$DKMS_PUB" 2>&1 | grep -q "already enrolled"; then
  ok "DKMS key is enrolled. Module should load."
  say "  Load it with: sudo modprobe zfs && sudo zpool import"
  exit 0
fi

# Enrollment requested but the MOK screen has not been completed yet?
if mokutil --list-new 2>/dev/null | grep -qiE 'fingerprint|\[key'; then
  warn "A key enrollment is already pending."
  say  "  Reboot, and approve it at the blue 'MOK management' screen:"
  say  "    Enroll MOK -> Continue -> Yes -> type the password -> Reboot"
  exit 1
fi

guidance
exit 1
