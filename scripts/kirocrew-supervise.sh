#!/usr/bin/env bash
# Keeps `kirocrew gateway` running: restarts it 5s after any exit.
# Replaces the disabled user unit kirocrew.service.
set -u
export PATH="/home/kenny/.local/bin:/home/kenny/.local/share/fnm/aliases/default/bin:/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
LOG="$HOME/.local/state/kirocrew/gateway.log"
mkdir -p "$(dirname "$LOG")"

# Refuse to start a second supervisor: hold an exclusive lock for the script's lifetime.
exec 9>"$HOME/.local/state/kirocrew/supervise.lock"
if ! flock -n 9; then
  echo "$(date -Is) supervisor already running, exiting" >>"$LOG"
  exit 0
fi

while true; do
  kirocrew gateway --no-open >>"$LOG" 2>&1
  echo "$(date -Is) gateway exited with status $?, restarting in 5s" >>"$LOG"
  sleep 5
done
