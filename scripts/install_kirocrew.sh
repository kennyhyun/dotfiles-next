#!/bin/sh
# install_kirocrew.sh — install Kiro Crew (the self-hosted agent gateway).
#
# Idempotent: if `kirocrew` is already on PATH it does NOT reinstall; it just
# reports the version and how to update. On a fresh host it runs the official
# one-line wheel installer, which provisions a pinned CPython 3.12 venv under
# ~/.kiro and a launcher in ~/.local/bin.
#
# What this does NOT do automatically (both are interactive / privileged — run
# them yourself after install):
#   - sign-in:        kiro-cli login      (Crew drives the LLM through kiro-cli)
#   - run as service: kirocrew service install   (sudo; starts on boot)
#
# Env:
#   KIROCREW_INSTALL_URL  The official one-line installer URL. REQUIRED on a
#                         fresh install — we do NOT hard-code a download URL, to
#                         avoid pinning a stale/typosquatted endpoint in the
#                         repo. Get the current URL from the "One-line wheel"
#                         tab at https://kiro.dev/docs/crew/installation/ and
#                         pass it, e.g.:
#                           KIROCREW_INSTALL_URL='https://…/install.sh' \
#                             scripts/install_kirocrew.sh
#
# Prereqs: kiro-cli must be installed (Crew's LLM backend). If it is missing we
# print how to get it and stop, rather than installing a half-working Crew.

set -eu

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---- already installed? (idempotent short-circuit) ----
if command -v kirocrew >/dev/null 2>&1; then
  ver="$(kirocrew --version 2>/dev/null || echo '?')"
  log "kirocrew already installed ($ver); skipping install."
  echo "  Update later with:  kirocrew update"
  echo "  Verify wiring with: kirocrew doctor"
  exit 0
fi

# ---- prerequisite: kiro-cli (LLM backend) ----
if ! command -v kiro-cli >/dev/null 2>&1; then
  log "kiro-cli not found — Kiro Crew needs it to drive the LLM (ACP backend)."
  echo "  Install kiro-cli first (see https://kiro.dev/docs/cli/setup/), put it"
  echo "  on PATH, then re-run this script. After install, sign in with:"
  echo "    kiro-cli login"
  exit 1
fi

# ---- fresh install via the official one-line wheel installer ----
if [ -z "${KIROCREW_INSTALL_URL:-}" ]; then
  log "KIROCREW_INSTALL_URL is not set — cannot install non-interactively."
  echo "  This script does not hard-code a download URL on purpose. Grab the"
  echo "  current one-line installer from the 'One-line wheel' tab at:"
  echo "    https://kiro.dev/docs/crew/installation/"
  echo "  then re-run, e.g.:"
  echo "    KIROCREW_INSTALL_URL='https://…/install.sh' scripts/install_kirocrew.sh"
  echo "  (Alternatively install the desktop app / wheel manually per the docs.)"
  exit 1
fi

log "Installing Kiro Crew via official installer: $KIROCREW_INSTALL_URL"
# Fetch to a temp file first so we never pipe an unverified body straight to sh
# without the user being able to see it; the installer itself is the trusted
# step the user opted into by providing the URL.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT INT TERM
if ! curl -fsSL "$KIROCREW_INSTALL_URL" -o "$tmp"; then
  echo "Failed to download the installer from $KIROCREW_INSTALL_URL" >&2
  exit 1
fi
sh "$tmp"

# ---- make sure the launcher is reachable ----
case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) echo "NOTE: ~/.local/bin is not on PATH; add it so 'kirocrew' resolves." ;;
esac

if ! command -v kirocrew >/dev/null 2>&1; then
  # It may have landed in ~/.local/bin without PATH yet; try that explicitly.
  if [ -x "$HOME/.local/bin/kirocrew" ]; then
    KC="$HOME/.local/bin/kirocrew"
  else
    echo "Install ran but 'kirocrew' is still not found. Check the installer output." >&2
    exit 1
  fi
else
  KC="kirocrew"
fi

log "Kiro Crew installed ($("$KC" --version 2>/dev/null || echo '?'))."
echo "Next steps (run these yourself):"
echo "  1. kiro-cli login            # sign in the LLM backend (if not already)"
echo "  2. $KC setup                 # interactive wizard: data dir, agent, creds"
echo "  3. $KC doctor                # verify everything is wired up"
echo "  4. $KC gateway               # start the server -> http://localhost:5476"
echo "  (Run 24/7 on boot: '$KC service install' — uses sudo on Linux.)"
