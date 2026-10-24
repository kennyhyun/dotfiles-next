# Linuxdev SSH Port-Forward GUI (Windows)

A small PowerShell/WPF GUI for forwarding ports from your **Windows host** into
a **WSL distro** over a single SSH connection (`ssh -L`), with a system-tray
icon, live SSH output, per-port status, and optional auto-start.

It exists because `netsh portproxy` can only reach services that bind
`0.0.0.0`/the WSL IP inside the distro. A service bound to `127.0.0.1` inside
WSL (e.g. a dev server on loopback) is invisible to portproxy. An SSH local
forward terminates **inside** the distro and dials the distro's own loopback,
so loopback-only services become reachable from Windows.

---

## What's in this folder

| File | Purpose |
|------|---------|
| `ssh-forward.ps1` | Core script. Reads `.env` `FORWARD_PORTS` and opens one `ssh -L` session. |
| `ssh-forward-gui.ps1` | WPF GUI around the core script (edit ports, start/stop, tray, status, autostart). |
| `ssh-forward-gui.vbs` | **Windowless launcher** — double-click this to open the GUI with no console flash. |
| `ssh-forward-gui.cmd` | Alternate launcher (hands off to the `.vbs`). |
| `.env` | Configuration (ports, distro name, SSH user, auto-start flag). |

---

## Prerequisites

- **Windows 10/11** with the built-in **OpenSSH client** (`ssh.exe` on `PATH`).
  Check: `where.exe ssh`. If missing:
  `Settings → Apps → Optional Features → Add → OpenSSH Client`.
- **WSL2** with a distro installed and an **SSH server running inside it**
  (`sudo apt install openssh-server` then `sudo service ssh start`).
- A way for `ssh.exe` to reach the distro. This project expects a portproxy
  rule `localhost:2222 → <wsl-ip>:22` (set up by the companion
  `keepalive.cmd`). If your SSH entry point differs, pass `-SshPort` /
  `-SshHost` to `ssh-forward.ps1`, or edit the GUI's call.

---

## Install (on a machine where WSL is already set up)

These files live in the dotfiles repo at `~/dotfiles/windows` **inside WSL**.
To use them you copy them to a normal **Windows** folder and run them there
(GUI apps and Scheduled Tasks must run on the Windows side, not inside WSL).

### 1. Copy the scripts to Windows

From inside WSL:

```bash
# Your Windows user profile is reachable from WSL under /mnt/c/Users/<you>.
DEST="/mnt/c/Users/$USER/linuxdev-ssh-forward"   # pick any Windows folder
mkdir -p "$DEST"
cp ~/dotfiles/windows/ssh-forward*.ps1 \
   ~/dotfiles/windows/ssh-forward-gui.vbs \
   ~/dotfiles/windows/ssh-forward-gui.cmd \
   ~/dotfiles/windows/.env.example "$DEST"/
cp "$DEST/.env.example" "$DEST/.env"   # then edit .env
```

> Adjust `DEST` to taste. The three scripts, the `.vbs`/`.cmd` launchers, and a
> `.env` must all sit in the **same** folder.

### 2. Configure `.env`

Edit `.env` in that folder (see **Configuration** below). At minimum set
`FORWARD_PORTS` and, if auto-detection isn't enough, `WSL_DISTRO_NAME` /
`WSL_USERNAME`.

### 3. Run it

Double-click **`ssh-forward-gui.vbs`**. The GUI opens with no console window.

- Click **Start Tunnels**.
- Watch the **Status** column: each host port shows `UP (listening)` / `DOWN`,
  and the summary line reads e.g. `Tunnels: RUNNING (PID 1234) -- 5/7 ports up`.

---

## Using the GUI

- **Port table** — edit `FORWARD_PORTS` as rows. *Host Port* is the port on
  Windows; *WSL Port* is the port inside the distro (`127.0.0.1`). Leave WSL
  Port blank to use the same number. **Add Row / Remove Row / Save .env /
  Reload**.
- **Start / Stop Tunnels** — opens/closes the single `ssh -L` session. `ssh.exe`
  runs with **no console window**; its stdout+stderr stream into the **SSH
  output** pane and `ssh-forward.log`.
- **Status** — refreshed ~every 2 seconds while running:
  - Per-port column: `UP (listening)` (something accepts TCP on
    `127.0.0.1:<hostport>`), `DOWN` (nothing there yet), `-` (not running).
  - Overall line: `stopped`, or `RUNNING -- <up>/<total> ports up` (green when
    all up, orange when partial, red when none).
- **Start tunnels automatically when this app opens** — persisted to `.env`
  (`AUTO_START_TUNNELS=true`). The GUI starts the tunnels for you on launch.
- **Start at logon (silent)** — registers a Windows **Scheduled Task** that runs
  the tunnels headless (no window) at logon, and reconnects if the link drops.
  Unchecking removes the task. *(Registering a task may require admin rights;
  the status line will say so if it fails.)*
- **System tray** — closing the window (X) **hides to the tray**; tunnels keep
  running. Double-click the tray icon to restore. Right-click for
  **Show / Start / Stop / Exit**. Only **Exit** really quits.

---

## Configuration (`.env`)

```ini
# Comma/space separated. "host:wsl" maps different ports; a bare "port" maps the
# same number on both sides. Everything after # is a comment.
FORWARD_PORTS=15476:5476,4322,4323,4324

# Optional. Auto-detected when exactly one distro is installed.
WSL_DISTRO_NAME=linuxdev
# Optional. Defaults to the current Windows user name.
WSL_USERNAME=kenny

# Set by the GUI checkbox; start tunnels when the app opens.
AUTO_START_TUNNELS=false
```

The GUI only ever rewrites the `FORWARD_PORTS` and `AUTO_START_TUNNELS` lines;
all other keys and comments are preserved.

---

## Command line (optional)

```powershell
# Just open the tunnels in the current window (Ctrl+C to stop):
.\ssh-forward.ps1

# Preview without connecting:
.\ssh-forward.ps1 -DryRun

# Override ports / SSH endpoint:
.\ssh-forward.ps1 -ForwardPorts "15476:5476,4322" -SshPort 2222 -SshHost localhost
```

---

## Troubleshooting

- **"ssh.exe not found on PATH"** — install the OpenSSH client (see
  Prerequisites).
- **Port shows DOWN** — the tunnel is up but nothing is listening on that port
  *inside* the distro yet, or `ExitOnForwardFailure` closed the session because
  a host port was already taken. Check the SSH output pane / `ssh-forward.log`.
- **Connection refused / auth errors** — verify the distro's SSH server is
  running and that `localhost:2222` reaches it (`ssh -p 2222 <user>@localhost`).
  The companion `keepalive.cmd` sets up the `2222 → 22` portproxy.
- **No tray icon** — the GUI falls back to a generic icon if the distro icon
  isn't found; it should still appear in the notification area (check the
  overflow `^`).
- **Autostart didn't register** — run the launcher as Administrator once, or
  create the Scheduled Task manually.

---

## Notes / design

- Forwards bind to `127.0.0.1` on Windows by default (loopback-only, like the
  portproxy host-only rules). Use `ssh-forward.ps1 -BindAll` for LAN exposure.
- Closing the GUI window does **not** stop the tunnels — it hides to the tray.
  Use **Stop Tunnels** or tray **Exit** to tear them down.
- The logon Scheduled Task and the "start when app opens" checkbox are
  independent: the former runs headless at logon, the latter runs when you open
  the GUI.
