#!/bin/sh
# Debian/Ubuntu (apt) package helpers.
# Sourced by run_once_before_10-install-packages.sh.tmpl; inherits all
# functions and variables defined there (log, have_sudo, rootfs_ensure_rw,
# LITE, ROLE, OS, SDIR, WITH_*).

install_system_packages() {
  [ "$OS" = "Darwin" ] && return 0
  if ! have_sudo; then
    log "No sudo (or NO_SUDO set): skipping apt packages."
    echo "  Make sure a C compiler + headers exist for treesitter, e.g.:"
    echo "    sudo apt-get install build-essential"
    return 0
  fi
  local distro perf_pkg
  distro="$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"
  if [ "$distro" = "ubuntu" ]; then perf_pkg="linux-tools-common"; else perf_pkg="linux-perf"; fi

  local want missing=""
  local pkgs="
    apt-transport-https ca-certificates
    git git-lfs
    htop
    jq curl
    net-tools psmisc whois
  "
  if [ -z "$LITE" ]; then
    pkgs="$pkgs
      build-essential
      $perf_pkg
      python3-pip python3-venv pipx
      default-jre
      xclip
      lshw
    "
  fi

  for want in $pkgs; do
    dpkg -s "$want" >/dev/null 2>&1 || missing="$missing $want"
  done

  if [ -z "$missing" ]; then
    log "All apt packages already installed; skipping (no rootfs unlock needed)."
    return 0
  fi

  log "Installing missing apt packages:$missing"
  rootfs_ensure_rw
  sudo apt-get update || true
  # shellcheck disable=SC2086
  sudo apt-get install -y $missing
}

install_lite_extras() {
  [ "$OS" != "Linux" ] && return 0
  [ -n "$LITE" ] || return 0
  if ! have_sudo; then
    log "lite role requested but no sudo: skipping podman (install it later)."
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    log "podman already installed ($(podman --version 2>/dev/null)); skipping."
    return 0
  fi
  log "lite role: installing podman"
  rootfs_ensure_rw
  sudo apt-get install -y podman \
    || echo "Could not install podman via apt (is the package available?)."
}

install_nas() {
  [ "$OS" != "Linux" ] && return 0
  local need_cockpit="" need_samba="" need_nfs=""
  [ -n "${WITH_COCKPIT:-}" ] && ! command -v cockpit-bridge >/dev/null 2>&1 && need_cockpit=1
  [ -n "${WITH_SAMBA:-}" ]   && ! command -v smbd           >/dev/null 2>&1 && need_samba=1
  [ -n "${WITH_NFS:-}" ]     && ! dpkg -s nfs-kernel-server  >/dev/null 2>&1 && need_nfs=1

  if [ -z "$need_cockpit" ] && [ -z "$need_samba" ] && [ -z "$need_nfs" ]; then
    return 0
  fi
  if ! have_sudo; then
    log "NAS stack requested but no sudo: skipping cockpit/samba/nfs."
    return 0
  fi

  log "installing NAS stack:${need_cockpit:+ cockpit}${need_samba:+ samba}${need_nfs:+ nfs}"
  rootfs_ensure_rw
  # Samba first: install_cockpit.sh adds `include = registry` to smb.conf when
  # cockpit-file-sharing lands, so smb.conf should already exist by then.
  [ -n "$need_samba" ]   && [ -x "$SDIR/install_samba.sh" ]   && "$SDIR/install_samba.sh"   || true
  [ -n "$need_cockpit" ] && [ -x "$SDIR/install_cockpit.sh" ] && "$SDIR/install_cockpit.sh" || true
  [ -n "$need_nfs" ]     && [ -x "$SDIR/install_nfs.sh" ]     && "$SDIR/install_nfs.sh"     || true
}
