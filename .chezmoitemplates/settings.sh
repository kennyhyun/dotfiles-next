# ---- Settings: env (DOTFILES_*) > legacy env (deprecated) > chezmoi.toml > default ----
# Shared by the run_once scripts (.chezmoitemplates/settings.sh). The chezmoi
# [data] values are rendered into this text when chezmoi runs the script.
#
# Names: DOTFILES_ROLE, DOTFILES_PRODUCTION, DOTFILES_NO_SUDO,
#        DOTFILES_WITH_MICROK8S / _KIROCREW / _ZFS / _CLAMAV / _TRIVY / _SURICATA
# The old unprefixed names (PRODUCTION, NO_SUDO, WITH_*) are still read, with a
# deprecation warning. After this block the script sees ROLE and PRODUCTION /
# NO_SUDO / WITH_* as plain variables, empty when off and "1" when on.

# _dotfiles_bool VALUE -> prints 1 unless VALUE is empty / 0 / false / no / off.
_dotfiles_bool() {
  case "$1" in
    ''|0|false|FALSE|False|no|NO|No|off|OFF|Off) ;;
    *) printf 1 ;;
  esac
}

# _dotfiles_get NAME LEGACY CONFIGVALUE -> env DOTFILES_<NAME>, else the legacy
# env name (with a warning), else the chezmoi.toml value. (eval only ever sees
# names written in this file, never user input.)
_dotfiles_get() {
  local name="DOTFILES_$1" legacy="$2" cfg="$3" v=""
  eval "v=\${$name:-}"
  if [ -z "$v" ] && [ -n "$legacy" ]; then
    eval "v=\${$legacy:-}"
    if [ -n "$v" ]; then
      printf 'WARNING: %s is deprecated; use %s (or set it in chezmoi.toml [data]).\n' \
        "$legacy" "$name" >&2
    fi
  fi
  [ -n "$v" ] || v="$cfg"
  printf '%s' "$v"
}

# role: env/config value; empty means "not set explicitly" (falls back to base).
ROLE="$(_dotfiles_get ROLE '' '{{ get . "role" }}')"
ROLE_EXPLICIT=""
[ -n "$ROLE" ] && ROLE_EXPLICIT=1
[ -n "$ROLE" ] || ROLE=base
case "$ROLE" in
  base|linuxdev|lite) ;;
  *)
    printf 'ERROR: unknown role "%s" (expected base, linuxdev or lite).\n' "$ROLE" >&2
    exit 1 ;;
esac

PRODUCTION="$(_dotfiles_bool "$(_dotfiles_get PRODUCTION PRODUCTION '{{ get . "production" }}')")"
NO_SUDO="$(_dotfiles_bool "$(_dotfiles_get NO_SUDO NO_SUDO '{{ get . "no_sudo" }}')")"
WITH_MICROK8S="$(_dotfiles_bool "$(_dotfiles_get WITH_MICROK8S WITH_MICROK8S '{{ get . "with_microk8s" }}')")"
WITH_KIROCREW="$(_dotfiles_bool "$(_dotfiles_get WITH_KIROCREW WITH_KIROCREW '{{ get . "with_kirocrew" }}')")"
WITH_ZFS="$(_dotfiles_bool "$(_dotfiles_get WITH_ZFS WITH_ZFS '{{ get . "with_zfs" }}')")"
WITH_CLAMAV="$(_dotfiles_bool "$(_dotfiles_get WITH_CLAMAV WITH_CLAMAV '{{ get . "with_clamav" }}')")"
WITH_TRIVY="$(_dotfiles_bool "$(_dotfiles_get WITH_TRIVY WITH_TRIVY '{{ get . "with_trivy" }}')")"
WITH_SURICATA="$(_dotfiles_bool "$(_dotfiles_get WITH_SURICATA WITH_SURICATA '{{ get . "with_suricata" }}')")"
ACCEPT_CHANGE="$(_dotfiles_bool "${DOTFILES_ACCEPT_CHANGE:-}")"
