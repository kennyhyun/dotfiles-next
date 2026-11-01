#!/bin/sh
# RHEL/Oracle Linux/CentOS (dnf/rpm) package helpers.
# Sourced by run_once_before_10-install-packages.sh.tmpl; inherits all
# functions and variables defined there (log, have_sudo, rootfs_ensure_rw,
# LITE, ROLE, OS, SDIR, WITH_*).

install_system_packages() {
  [ "$OS" = "Darwin" ] && return 0
  if ! have_sudo; then
    log "No sudo (or NO_SUDO set): skipping dnf packages."
    echo "  Make sure a C compiler + headers exist for treesitter, e.g.:"
    echo "    sudo dnf install gcc gcc-c++ make"
    return 0
  fi

  local want missing=""
  local pkgs="
    ca-certificates
    git git-lfs
    htop
    jq curl
    net-tools psmisc whois
  "
  if [ -z "$LITE" ]; then
    pkgs="$pkgs
      gcc gcc-c++ make
      perf
      python3-pip pipx
      java-17-openjdk-headless
      xclip
      lshw
    "
  fi

  for want in $pkgs; do
    rpm -q "$want" >/dev/null 2>&1 || missing="$missing $want"
  done

  if [ -z "$missing" ]; then
    log "All dnf packages already installed; skipping."
    return 0
  fi

  log "Installing missing dnf packages:$missing"
  rootfs_ensure_rw
  # shellcheck disable=SC2086
  sudo dnf install -y $missing
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
  sudo dnf install -y podman \
    || echo "Could not install podman via dnf (is the package available?)."
}

install_nas() {
  [ "$OS" != "Linux" ] && return 0
  local need_cockpit="" need_samba="" need_nfs=""
  [ -n "${WITH_COCKPIT:-}" ] && ! command -v cockpit-bridge >/dev/null 2>&1 && need_cockpit=1
  [ -n "${WITH_SAMBA:-}" ]   && ! command -v smbd           >/dev/null 2>&1 && need_samba=1
  [ -n "${WITH_NFS:-}" ]     && ! rpm -q nfs-utils           >/dev/null 2>&1 && need_nfs=1

  if [ -z "$need_cockpit" ] && [ -z "$need_samba" ] && [ -z "$need_nfs" ]; then
    return 0
  fi
  if ! have_sudo; then
    log "NAS stack requested but no sudo: skipping cockpit/samba/nfs."
    return 0
  fi

  log "installing NAS stack:${need_cockpit:+ cockpit}${need_samba:+ samba}${need_nfs:+ nfs}"
  rootfs_ensure_rw
  [ -n "$need_samba" ]   && [ -x "$SDIR/install_samba.sh" ]   && "$SDIR/install_samba.sh"   || true
  [ -n "$need_cockpit" ] && [ -x "$SDIR/install_cockpit.sh" ] && "$SDIR/install_cockpit.sh" || true
  [ -n "$need_nfs" ]     && [ -x "$SDIR/install_nfs.sh" ]     && "$SDIR/install_nfs.sh"     || true
}
