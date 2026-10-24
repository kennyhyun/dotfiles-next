<#
.SYNOPSIS
    Forward .env FORWARD_PORTS from the Windows host into the WSL distro over a
    single SSH connection (ssh -L), reaching services bound to 127.0.0.1 inside
    the distro -- which netsh portproxy to the WSL IP cannot do.

.DESCRIPTION
    netsh portproxy connects to the distro's IP, so it only reaches services
    that bind 0.0.0.0 (or the WSL IP). A service bound to 127.0.0.1 inside WSL
    (e.g. kirocrew on 15476) is invisible to that path. An SSH local forward
    (`ssh -L host:127.0.0.1:wsl`) terminates the far end INSIDE the distro and
    dials the distro's own loopback, so loopback-only services are reachable.

    This opens ONE ssh session with one -L per FORWARD_PORTS entry and holds it
    open. Close the window (or Ctrl+C) to tear every tunnel down at once -- no
    persistent OS state, unlike portproxy. Same .env format as
    register-autostart.ps1: "host:wsl" maps different ports, "port" maps same.

    SSH reaches the distro via localhost:<SshPort> (the 2222->22 portproxy that
    register-autostart.ps1 sets up). Override with -SshPort / -SshHost.

.PARAMETER DistroName
    WSL distro name. Auto-detected when exactly one is installed.

.PARAMETER SshHost
    Host:port alias to SSH into. Default: localhost.

.PARAMETER SshPort
    SSH port on the host (the portproxy listen port). Default: 2222.

.PARAMETER SshUser
    SSH user. Default: .env WSL_USERNAME, else the current Windows user name.

.PARAMETER ForwardPorts
    Override FORWARD_PORTS (comma/space list). Default: read from .env.

.PARAMETER EnvFile
    .env path. Default: ~/.linuxdev/<distro>/.env, else repo .env.

.PARAMETER BindAll
    Bind the host side to 0.0.0.0 (LAN-visible) instead of 127.0.0.1. Off by
    default -- forwards are loopback-only, like the portproxy host-only rules.

.PARAMETER DryRun
    Print the ssh command and exit without connecting.

.PARAMETER PrintArgs
    Print the resolved ssh argument list (one per line) and exit without
    connecting. Used by ssh-forward-gui.ps1 so it can launch ssh itself with
    no console window and capture its output.

.EXAMPLE
    .\ssh-forward.ps1
.EXAMPLE
    .\ssh-forward.ps1 -ForwardPorts "15476,4322:4322" -DryRun
#>
param(
    [string]$DistroName = "",
    [string]$SshHost    = "localhost",
    [int]$SshPort       = 2222,
    [string]$SshUser    = "",
    [string]$ForwardPorts = "",
    [string]$EnvFile    = "",
    [switch]$BindAll,
    [switch]$DryRun,
    [switch]$PrintArgs
)

$ErrorActionPreference = "Stop"

# --- resolve distro (reuse shared helper if present, else wsl -l) ---
$utils = Join-Path $PSScriptRoot "..\common\wsl-utils.ps1"
if (Test-Path $utils) { . $utils }

function Get-Distros {
    if (Get-Command Get-WslDistros -ErrorAction SilentlyContinue) {
        return @(Get-WslDistros)
    }
    # Fallback: wsl -l -q is UTF-16; decode and trim.
    $raw = & wsl.exe -l -q 2>$null
    return @($raw | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
}

if (-not $DistroName) {
    $all = @(Get-Distros)
    if ($all.Count -eq 1) { $DistroName = $all[0] }
    elseif ($all.Count -eq 0) { Write-Error "No WSL distro installed."; exit 1 }
    else { Write-Error "Multiple distros ($($all -join ', ')). Pass -DistroName."; exit 1 }
}

# --- locate .env (reuse shared Get-LinuxdevDir; fall back to the same rule) ---
function Get-DistroDir {
    param([string]$d)
    if (Get-Command Get-LinuxdevDir -ErrorAction SilentlyContinue) {
        return (Get-LinuxdevDir $d)
    }
    return (Join-Path $env:USERPROFILE ".linuxdev\$d")
}
if (-not $EnvFile) {
    $perDistro = Join-Path (Get-DistroDir $DistroName) ".env"
    $repoEnv   = Join-Path $PSScriptRoot "..\..\.env"
    $EnvFile = if (Test-Path $perDistro) { $perDistro } else { $repoEnv }
}

# --- read a key from .env ---
function Get-EnvValue {
    param([string]$File, [string]$Key)
    if (-not (Test-Path $File)) { return "" }
    $val = ""
    Get-Content $File | ForEach-Object {
        if ($_ -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*)$") { $val = $matches[1] }
    }
    return ($val -split '#', 2)[0].Trim()
}

# --- parse "host:wsl"/"port" list into unique {HostPort,WslPort} ---
function Get-PortList {
    param([string]$Raw)
    if (-not $Raw) { return @() }
    $Raw = ($Raw -split '#', 2)[0]
    $seen = @{}; $out = @()
    foreach ($tok in ($Raw -split '[,\s]+')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        $parts = $t -split ':', 2
        $h = $parts[0].Trim()
        $w = if ($parts.Count -eq 2 -and $parts[1].Trim()) { $parts[1].Trim() } else { $h }
        $ok = $h -match '^\d+$' -and $w -match '^\d+$' -and
              [int]$h -ge 1 -and [int]$h -le 65535 -and [int]$w -ge 1 -and [int]$w -le 65535
        if (-not $ok) { Write-Warning "Ignoring invalid FORWARD_PORTS entry '$t'"; continue }
        if ($seen.ContainsKey([int]$h)) { continue }
        $seen[[int]$h] = $true
        $out += [pscustomobject]@{ HostPort = [int]$h; WslPort = [int]$w }
    }
    return $out
}

# --- resolve ports + user ---
$rawPorts = if ($ForwardPorts) { $ForwardPorts } else { Get-EnvValue $EnvFile "FORWARD_PORTS" }
$ports = Get-PortList $rawPorts
if (-not $ports.Count) {
    Write-Error "No valid FORWARD_PORTS (checked: $EnvFile). Pass -ForwardPorts to override."
    exit 1
}
if (-not $SshUser) {
    $SshUser = Get-EnvValue $EnvFile "WSL_USERNAME"
    if (-not $SshUser) { $SshUser = $env:USERNAME }
}

# --- build ssh -L args; far end is the distro's OWN 127.0.0.1 ---
$bind = if ($BindAll) { "0.0.0.0" } else { "127.0.0.1" }
$sshArgs = @(
    "-N"                                  # no remote command, just forward
    "-p", "$SshPort"
    "-o", "StrictHostKeyChecking=accept-new"
    "-o", "ServerAliveInterval=30"
    "-o", "ServerAliveCountMax=3"
    "-o", "ExitOnForwardFailure=yes"
)
foreach ($m in $ports) {
    # host:WslPort reached via the distro's loopback -> loopback-only services work
    $sshArgs += @("-L", "${bind}:$($m.HostPort):127.0.0.1:$($m.WslPort)")
}
$sshArgs += "$SshUser@$SshHost"

$summary = ($ports | ForEach-Object { "${bind}:$($_.HostPort) -> WSL 127.0.0.1:$($_.WslPort)" }) -join ', '
if (-not $PrintArgs) {
    Write-Host "Distro:   $DistroName"
    Write-Host "SSH:      $SshUser@$SshHost`:$SshPort"
    Write-Host "Env:      $EnvFile"
    Write-Host "Forwards: $summary"
    Write-Host "Command:  ssh $($sshArgs -join ' ')"
}

if ($PrintArgs) {
    # One argument per line -- and ONLY the args -- so the caller round-trips
    # them exactly. (All human-readable output above is suppressed here because
    # Write-Host is captured together with stdout in Windows PowerShell.)
    $sshArgs | ForEach-Object { $_ }
    return
}

if ($DryRun) { Write-Host "(dry run -- not connecting)"; return }

Write-Host ""
Write-Host "Opening SSH tunnels. Keep this window open; Ctrl+C or close it to stop."
& ssh.exe @sshArgs
