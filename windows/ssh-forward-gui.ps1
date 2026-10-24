<#
.SYNOPSIS
    GUI for ssh-forward.ps1 -- edit .env FORWARD_PORTS, start/stop the SSH
    tunnels (no console window), see live ssh output, and register/unregister
    logon autostart.

.DESCRIPTION
    A WPF front-end that sits next to ssh-forward.ps1 and its .env. It:
      * Shows/edits the FORWARD_PORTS entries and saves them back to .env
        (preserving every other key and comment).
      * Starts the tunnels by asking ssh-forward.ps1 for the resolved ssh
        argument list (-PrintArgs), then launches ssh.exe ITSELF with no window
        (CreateNoWindow) and captures stdout+stderr live into a log pane and a
        log file. Stop kills ssh, tearing every -L down at once.
      * Monitors the ssh process: if it dies unexpectedly (auth failure, host
        refused, forward bind failure, dropped link) the UI updates and shows
        the last log lines instead of silently pretending it is still up.
      * Registers logon autostart via a Scheduled Task that runs the tunnels
        silently (-Tunnel), or unregisters it.

.PARAMETER Tunnel
    Internal: run the tunnels headless (used by the autostart task). Launches
    ssh the same windowless way and logs to the same file, then blocks until
    ssh exits. Not for interactive use.
#>
param(
    [switch]$Tunnel
)

$ErrorActionPreference = "Stop"
$ScriptDir   = $PSScriptRoot
$ForwardPs1  = Join-Path $ScriptDir "ssh-forward.ps1"
$EnvFile     = Join-Path $ScriptDir ".env"
$LogFile     = Join-Path $ScriptDir "ssh-forward.log"
$TaskName    = "LinuxdevSshForward"

if (-not (Test-Path $ForwardPs1)) {
    throw "ssh-forward.ps1 not found next to this GUI ($ForwardPs1)."
}

# =============================================================================
#  ssh launch -- windowless, output captured. Shared by GUI and -Tunnel mode.
# =============================================================================

# Ask ssh-forward.ps1 for the exact ssh argument list (one per line on stdout).
function Resolve-SshArgs {
    $psExe = (Get-Command powershell.exe).Source
    $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $ForwardPs1 -PrintArgs 2>$null
    $lines = @($out | ForEach-Object { "$_".TrimEnd("`r") } | Where-Object { $_ -ne "" })
    return ,$lines
}

# Start ssh.exe with NO console window and stream stdout+stderr into $LogFile.
# Uses Register-ObjectEvent (the reliable way to catch async process output in
# Windows PowerShell -- plain add_OutputDataReceived handlers do not fire in a
# script host). Returns a hashtable: @{ Proc = <Process>; Events = <names> }.
function Start-SshProcess {
    param([string[]]$SshArgs)

    $sshExe = (Get-Command ssh.exe -ErrorAction SilentlyContinue)
    if (-not $sshExe) { throw "ssh.exe not found on PATH." }

    # Windows PowerShell 5.1's ProcessStartInfo has no ArgumentList; build a
    # single Arguments string, quoting any token that contains whitespace.
    $quoted = $SshArgs | ForEach-Object {
        if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }
    $argString = ($quoted -join ' ')

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $sshExe.Source
    $psi.Arguments              = $argString
    $psi.UseShellExecute        = $false   # required to redirect + no shell window
    $psi.CreateNoWindow         = $true    # the key: no console window at all
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    # Event action appends each line (timestamped) to the log file. The GUI
    # timer tails that file into the on-screen pane, so we never touch WPF from
    # a background thread. $Event.MessageData carries the log path.
    $action = {
        if ($EventArgs.Data) {
            $stamp = (Get-Date -Format "HH:mm:ss")
            Add-Content -Path $Event.MessageData -Value ("[$stamp] " + $EventArgs.Data) -Encoding UTF8
        }
    }
    $so = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $action -MessageData $LogFile
    $se = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived  -Action $action -MessageData $LogFile

    [void]$proc.Start()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    return @{ Proc = $proc; Events = @($so.Name, $se.Name) }
}

# Tear down the event subscriptions created by Start-SshProcess.
function Stop-SshEvents {
    param([string[]]$Names)
    foreach ($n in $Names) { Unregister-Event -SourceIdentifier $n -ErrorAction SilentlyContinue }
}

# --- headless tunnel mode (autostart Scheduled Task) ---------------------------
if ($Tunnel) {
    "`n===== $(Get-Date -Format s) tunnel start (autostart) =====" | Add-Content $LogFile -Encoding UTF8
    # Reconnect loop: if ssh drops (sleep/resume, distro restart) wait and retry.
    while ($true) {
        try {
            $sshArgs = Resolve-SshArgs
            if (-not $sshArgs.Count) {
                "No ssh args resolved; check .env FORWARD_PORTS. Retrying in 30s." | Add-Content $LogFile -Encoding UTF8
                Start-Sleep -Seconds 30; continue
            }
            $h = Start-SshProcess -SshArgs $sshArgs
            $h.Proc.WaitForExit()
            Stop-SshEvents -Names $h.Events
            "ssh exited (code $($h.Proc.ExitCode)). Reconnecting in 10s." | Add-Content $LogFile -Encoding UTF8
        } catch {
            "tunnel error: $($_.Exception.Message). Retrying in 30s." | Add-Content $LogFile -Encoding UTF8
            Start-Sleep -Seconds 30; continue
        }
        Start-Sleep -Seconds 10
    }
    return
}

# =============================================================================
#  .env helpers -- read/write ONLY the FORWARD_PORTS key, preserve everything.
# =============================================================================
function Get-ForwardPortsRaw {
    if (-not (Test-Path $EnvFile)) { return "" }
    $val = ""
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*FORWARD_PORTS\s*=\s*(.*)$') { $val = $matches[1] }
    }
    return ($val -split '#', 2)[0].Trim()
}

function Set-ForwardPortsRaw {
    param([string]$Value)
    Set-EnvKey -Key "FORWARD_PORTS" -Value $Value
}

# Generic: read a single .env key (value with any trailing #comment stripped).
function Get-EnvKey {
    param([string]$Key, [string]$Default = "")
    if (-not (Test-Path $EnvFile)) { return $Default }
    $val = $null
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=\s*(.*)$") { $val = $matches[1] }
    }
    if ($null -eq $val) { return $Default }
    return ($val -split '#', 2)[0].Trim()
}

# Generic: upsert a single .env key, preserving every other line and comment.
function Set-EnvKey {
    param([string]$Key, [string]$Value)
    $lines = if (Test-Path $EnvFile) { @(Get-Content $EnvFile) } else { @() }
    $out = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($line in $lines) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*=") {
            $out.Add("$Key=$Value")
            $found = $true
        } else {
            $out.Add($line)
        }
    }
    if (-not $found) { $out.Add("$Key=$Value") }
    Set-Content -Path $EnvFile -Value $out -Encoding ASCII
}

function Parse-Ports {
    param([string]$Raw)
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $Raw) { return $list }
    $Raw = ($Raw -split '#', 2)[0]
    foreach ($tok in ($Raw -split '[,\s]+')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        $parts = $t -split ':', 2
        $h = $parts[0].Trim()
        $w = if ($parts.Count -eq 2 -and $parts[1].Trim()) { $parts[1].Trim() } else { $h }
        $list.Add([pscustomobject]@{ HostPort = $h; WslPort = $w })
    }
    return $list
}

function Format-Ports {
    param($Rows)
    $toks = @()
    foreach ($r in $Rows) {
        $h = "$($r.HostPort)".Trim()
        $w = "$($r.WslPort)".Trim()
        if (-not $h) { continue }
        if (-not $w) { $w = $h }
        if ($h -eq $w) { $toks += $h } else { $toks += "${h}:${w}" }
    }
    return ($toks -join ',')
}

function Test-ValidPort { param([string]$p) return ($p -match '^\d+$' -and [int]$p -ge 1 -and [int]$p -le 65535) }

# =============================================================================
#  Autostart (Scheduled Task at logon).
# =============================================================================
function Test-AutostartRegistered {
    return [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)
}

function Register-Autostart {
    $psExe  = (Get-Command powershell.exe).Source
    $selfPs = Join-Path $ScriptDir "ssh-forward-gui.ps1"
    $arg    = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$selfPs`" -Tunnel"
    $action   = New-ScheduledTaskAction -Execute $psExe -Argument $arg
    $trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Settings $settings -Description "Linuxdev SSH port-forward tunnels (logon)" `
        -Force | Out-Null
}

function Unregister-Autostart {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# =============================================================================
#  WPF window
# =============================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Linuxdev SSH Port Forward" Height="680" Width="580"
        WindowStartupLocation="CenterScreen" ResizeMode="CanResize">
    <Grid Margin="12">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="2*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="3*"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,8">
            <TextBlock Text="Forward Ports (.env FORWARD_PORTS)" FontWeight="Bold" FontSize="14"/>
            <TextBlock Text="Host Port = the port on Windows; WSL Port = the port inside the distro (127.0.0.1)."
                       Foreground="Gray" TextWrapping="Wrap" Margin="0,2,0,0"/>
            <Border Background="#F0F0F0" CornerRadius="3" Padding="6,3" Margin="0,6,0,0">
                <TextBlock x:Name="OverallStatus" Text="Tunnels: stopped" FontWeight="Bold"/>
            </Border>
        </StackPanel>

        <DataGrid x:Name="Grid" Grid.Row="1" AutoGenerateColumns="False"
                  CanUserAddRows="True" HeadersVisibility="Column" GridLinesVisibility="Horizontal">
            <DataGrid.Columns>
                <DataGridTextColumn Header="Host Port" Binding="{Binding HostPort}" Width="*"/>
                <DataGridTextColumn Header="WSL Port"  Binding="{Binding WslPort}"  Width="*"/>
                <DataGridTextColumn Header="Status"    Binding="{Binding Status}"   Width="1.4*" IsReadOnly="True"/>
            </DataGrid.Columns>
        </DataGrid>

        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,8,0,0">
            <Button x:Name="BtnAdd"    Content="Add Row"    Width="90" Height="28" Margin="0,0,6,0"/>
            <Button x:Name="BtnRemove" Content="Remove Row" Width="90" Height="28" Margin="0,0,6,0"/>
            <Button x:Name="BtnSave"   Content="Save .env"  Width="90" Height="28" Margin="0,0,6,0"/>
            <Button x:Name="BtnReload" Content="Reload"     Width="90" Height="28"/>
        </StackPanel>

        <Separator Grid.Row="3" Margin="0,10,0,10"/>

        <StackPanel Grid.Row="4">
            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <Button x:Name="BtnStart" Content="Start Tunnels" Width="120" Height="32" Margin="0,0,6,0"/>
                <Button x:Name="BtnStop"  Content="Stop Tunnels"  Width="120" Height="32" Margin="0,0,6,0"/>
                <CheckBox x:Name="ChkAutostart" Content="Start at logon (silent)" VerticalAlignment="Center" Margin="10,0,0,0"/>
            </StackPanel>
            <CheckBox x:Name="ChkAutoStartOnLaunch" Content="Start tunnels automatically when this app opens"
                      Margin="0,0,0,8"/>
            <TextBlock x:Name="Status" Text="Idle." Foreground="#333" TextWrapping="Wrap"/>
        </StackPanel>

        <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,10,0,4">
            <TextBlock Text="SSH output" FontWeight="Bold" VerticalAlignment="Center"/>
            <Button x:Name="BtnClearLog" Content="Clear"     Width="70" Height="24" Margin="12,0,6,0"/>
            <Button x:Name="BtnOpenLog"  Content="Open log file" Width="110" Height="24"/>
        </StackPanel>

        <TextBox x:Name="LogBox" Grid.Row="6" IsReadOnly="True" TextWrapping="NoWrap"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
                 FontFamily="Consolas" FontSize="12" Background="#111" Foreground="#DDD"/>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [Windows.Markup.XamlReader]::Load($reader)

$grid         = $win.FindName("Grid")
$btnAdd       = $win.FindName("BtnAdd")
$btnRemove    = $win.FindName("BtnRemove")
$btnSave      = $win.FindName("BtnSave")
$btnReload    = $win.FindName("BtnReload")
$btnStart     = $win.FindName("BtnStart")
$btnStop      = $win.FindName("BtnStop")
$chkAutostart = $win.FindName("ChkAutostart")
$chkAutoLaunch = $win.FindName("ChkAutoStartOnLaunch")
$status       = $win.FindName("Status")
$overallStatus = $win.FindName("OverallStatus")
$logBox       = $win.FindName("LogBox")
$btnClearLog  = $win.FindName("BtnClearLog")
$btnOpenLog   = $win.FindName("BtnOpenLog")

$script:Handle   = $null   # @{ Proc = <Process>; Events = <names> } while running
$script:Rows     = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$script:LogOffset = 0       # bytes of $LogFile already shown in the pane
$script:StatusTick = 0      # throttles the port-status probe in the UI timer
$script:LastStatusRunning = $false

function Set-Status { param([string]$msg, [string]$color = "#333")
    $status.Text = $msg
    $status.Foreground = $color
}

function Append-Log { param([string]$line)
    $logBox.AppendText($line + "`r`n")
    $logBox.ScrollToEnd()
}

function Load-Grid {
    $script:Rows.Clear()
    foreach ($p in (Parse-Ports (Get-ForwardPortsRaw))) {
        $script:Rows.Add([pscustomobject]@{ HostPort = $p.HostPort; WslPort = $p.WslPort; Status = "-" })
    }
    $grid.ItemsSource = $script:Rows
}

function Test-TunnelRunning {
    return ($script:Handle -and $script:Handle.Proc -and -not $script:Handle.Proc.HasExited)
}

# Is something accepting TCP connections on 127.0.0.1:<port>? Quick, bounded.
function Test-PortListening {
    param([int]$Port)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(250)   # 250ms budget per port
        if ($ok -and $client.Connected) { $client.EndConnect($iar); return $true }
        return $false
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

# Refresh the per-row Status column and the overall summary line.
function Update-PortStatus {
    $running = Test-TunnelRunning
    if (-not $running) {
        foreach ($r in $script:Rows) { $r.Status = "-" }
        $overallStatus.Text = "Tunnels: stopped"
        $overallStatus.Foreground = [System.Windows.Media.Brushes]::DimGray
        $grid.Items.Refresh()
        return
    }
    $up = 0; $total = 0
    foreach ($r in $script:Rows) {
        $h = "$($r.HostPort)".Trim()
        if (-not ($h -match '^\d+$')) { $r.Status = "-"; continue }
        $total++
        if (Test-PortListening ([int]$h)) { $r.Status = "UP (listening)"; $up++ }
        else { $r.Status = "DOWN" }
    }
    $overallStatus.Text = "Tunnels: RUNNING (PID $($script:Handle.Proc.Id)) -- $up/$total ports up"
    if ($up -eq $total -and $total -gt 0) {
        $overallStatus.Foreground = [System.Windows.Media.Brushes]::Green
    } elseif ($up -gt 0) {
        $overallStatus.Foreground = [System.Windows.Media.Brushes]::DarkOrange
    } else {
        $overallStatus.Foreground = [System.Windows.Media.Brushes]::Red
    }
    $grid.Items.Refresh()
}

function Refresh-TunnelButtons {
    $running = Test-TunnelRunning
    $btnStart.IsEnabled = -not $running
    $btnStop.IsEnabled  = $running
}

# --- grid editing ---
$btnAdd.Add_Click({ $script:Rows.Add([pscustomobject]@{ HostPort = ""; WslPort = "" }) })
$btnRemove.Add_Click({
    $sel = @($grid.SelectedItems)
    foreach ($item in $sel) { [void]$script:Rows.Remove($item) }
})
$btnReload.Add_Click({ Load-Grid; Set-Status "Reloaded from .env." })
$btnSave.Add_Click({
    $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Row, $true) | Out-Null
    $bad = @()
    foreach ($r in $script:Rows) {
        $h = "$($r.HostPort)".Trim()
        if (-not $h) { continue }
        $w = "$($r.WslPort)".Trim(); if (-not $w) { $w = $h }
        if (-not (Test-ValidPort $h) -or -not (Test-ValidPort $w)) { $bad += "${h}:${w}" }
    }
    if ($bad.Count) {
        Set-Status "Invalid port(s): $($bad -join ', '). Ports must be 1-65535." "#B00"
        return
    }
    $value = Format-Ports $script:Rows
    Set-ForwardPortsRaw $value
    Set-Status "Saved FORWARD_PORTS=$value" "#070"
})

# --- log pane buttons ---
$btnClearLog.Add_Click({
    $logBox.Clear()
    # Skip past everything already in the file so cleared lines don't reappear.
    try { if (Test-Path $LogFile) { $script:LogOffset = (Get-Item $LogFile).Length } } catch {}
})
$btnOpenLog.Add_Click({
    if (Test-Path $LogFile) { Start-Process notepad.exe $LogFile }
    else { Set-Status "No log file yet ($LogFile)." }
})

# --- tunnel start/stop ---
# Shared start routine so both the button and launch-autostart use one path.
function Start-Tunnels {
    if (Test-TunnelRunning) {
        Set-Status "Tunnels already running (PID $($script:Handle.Proc.Id))."
        return
    }
    try {
        $sshArgs = Resolve-SshArgs
        if (-not $sshArgs.Count) {
            Set-Status "No ssh args (check FORWARD_PORTS in .env)." "#B00"; return
        }
        "----- $(Get-Date -Format s) start: ssh $($sshArgs -join ' ')" | Add-Content $LogFile -Encoding UTF8
        $script:Handle = Start-SshProcess -SshArgs $sshArgs
        Set-Status "Tunnels started (PID $($script:Handle.Proc.Id)). Watching ssh output below." "#070"
    } catch {
        Set-Status "Failed to start: $($_.Exception.Message)" "#B00"
        "ERROR: $($_.Exception.Message)" | Add-Content $LogFile -Encoding UTF8
    }
    Refresh-TunnelButtons
}

$btnStart.Add_Click({ Start-Tunnels })
$btnStop.Add_Click({
    if (Test-TunnelRunning) {
        try {
            Stop-Process -Id $script:Handle.Proc.Id -Force -ErrorAction Stop
            Set-Status "Tunnels stopped." "#070"
            "----- $(Get-Date -Format s) stopped by user" | Add-Content $LogFile -Encoding UTF8
        } catch {
            Set-Status "Failed to stop: $($_.Exception.Message)" "#B00"
        }
    } else {
        Set-Status "No running tunnel process."
    }
    if ($script:Handle) { Stop-SshEvents -Names $script:Handle.Events }
    $script:Handle = $null
    Refresh-TunnelButtons
})

# --- autostart toggle ---
$chkAutostart.Add_Click({
    try {
        if ($chkAutostart.IsChecked) {
            Register-Autostart
            Set-Status "Autostart registered (Scheduled Task '$TaskName', runs silently at logon)." "#070"
        } else {
            Unregister-Autostart
            Set-Status "Autostart removed." "#070"
        }
    } catch {
        Set-Status "Autostart change failed (admin rights may be needed): $($_.Exception.Message)" "#B00"
        $chkAutostart.IsChecked = (Test-AutostartRegistered)
    }
})

# "Start tunnels when this app opens" -- persisted to .env as AUTO_START_TUNNELS.
$chkAutoLaunch.Add_Click({
    $val = if ($chkAutoLaunch.IsChecked) { "true" } else { "false" }
    try {
        Set-EnvKey -Key "AUTO_START_TUNNELS" -Value $val
        if ($chkAutoLaunch.IsChecked) {
            Set-Status "Will auto-start tunnels every time this app opens." "#070"
        } else {
            Set-Status "Auto-start on app open disabled." "#070"
        }
    } catch {
        Set-Status "Could not save setting: $($_.Exception.Message)" "#B00"
    }
})

# --- UI timer: tail the log file into the pane, watch for unexpected ssh exit ---
$script:WasRunning = $false
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({
    # Tail new bytes of the log file (written by the ssh output events and by
    # the autostart tunnel if it's running) into the TextBox.
    try {
        if (Test-Path $LogFile) {
            $fs = [System.IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
            try {
                if ($fs.Length -lt $script:LogOffset) { $script:LogOffset = 0 } # file truncated
                if ($fs.Length -gt $script:LogOffset) {
                    [void]$fs.Seek($script:LogOffset, 'Begin')
                    $sr = New-Object System.IO.StreamReader($fs)
                    $new = $sr.ReadToEnd()
                    $script:LogOffset = $fs.Length
                    if ($new) { $logBox.AppendText($new); $logBox.ScrollToEnd() }
                }
            } finally { $fs.Close() }
        }
    } catch {}

    $running = Test-TunnelRunning
    if ($script:WasRunning -and -not $running) {
        $code = try { $script:Handle.Proc.ExitCode } catch { "?" }
        Set-Status "ssh exited unexpectedly (code $code). See output below / log file." "#B00"
        if ($script:Handle) { Stop-SshEvents -Names $script:Handle.Events }
        $script:Handle = $null
        Refresh-TunnelButtons
    }
    $script:WasRunning = $running

    # Port status probe, throttled to ~every 2s (5 ticks * 400ms) to avoid
    # hammering TCP connects on every tick. Also probe immediately on the
    # first tick after a state change.
    $script:StatusTick = ($script:StatusTick + 1) % 5
    if ($script:StatusTick -eq 0 -or ($running -ne $script:LastStatusRunning)) {
        Update-PortStatus
        $script:LastStatusRunning = $running
    }
})
$timer.Start()

# --- initial state ---
Load-Grid
$chkAutostart.IsChecked = (Test-AutostartRegistered)
$chkAutoLaunch.IsChecked = ((Get-EnvKey -Key "AUTO_START_TUNNELS" -Default "false").ToLower() -eq "true")
Refresh-TunnelButtons
Set-Status "Loaded .env from $EnvFile"
# Start the log pane at the current end of file so we only show NEW output.
try { if (Test-Path $LogFile) { $script:LogOffset = (Get-Item $LogFile).Length } } catch {}
$logBox.AppendText("Ready. Log file: $LogFile`r`n")

# =============================================================================
#  System tray (NotifyIcon). Closing the window hides to tray; tunnels keep
#  running. Exit from the tray menu is the only thing that really quits.
# =============================================================================
$script:ReallyExit = $false

# Pick an icon: the distro shortcut icon if present, else the system app icon.
$iconPath = Join-Path $ScriptDir "distro\shortcut.ico"
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
try {
    if (Test-Path $iconPath) { $trayIcon.Icon = New-Object System.Drawing.Icon $iconPath }
    else { $trayIcon.Icon = [System.Drawing.SystemIcons]::Application }
} catch { $trayIcon.Icon = [System.Drawing.SystemIcons]::Application }
$trayIcon.Text    = "Linuxdev SSH Port Forward"
$trayIcon.Visible = $true

# Restore the window from the tray.
function Show-Window {
    $win.Show()
    $win.WindowState = [System.Windows.WindowState]::Normal
    $win.Activate()
    [void]$win.Topmost; $win.Topmost = $true; $win.Topmost = $false
}

# Context menu: Show / Start / Stop / Exit.
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$miShow  = $menu.Items.Add("Show")
$miStart = $menu.Items.Add("Start Tunnels")
$miStop  = $menu.Items.Add("Stop Tunnels")
[void]$menu.Items.Add("-")                # separator
$miExit  = $menu.Items.Add("Exit")
$trayIcon.ContextMenuStrip = $menu

$miShow.add_Click({ Show-Window })
$miStart.add_Click({ $btnStart.RaiseEvent((New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent))) })
$miStop.add_Click({  $btnStop.RaiseEvent( (New-Object System.Windows.RoutedEventArgs ([System.Windows.Controls.Button]::ClickEvent))) })
$miExit.add_Click({
    $script:ReallyExit = $true
    $win.Close()
    try { $script:app.Shutdown() } catch {}
})

# Double-click the tray icon to show the window.
$trayIcon.add_MouseDoubleClick({ Show-Window })

# Reflect tunnel state in the tray tooltip when the menu opens.
$menu.add_Opening({
    $running = Test-TunnelRunning
    $miStart.Enabled = -not $running
    $miStop.Enabled  = $running
    $trayIcon.Text = if ($running) { "Linuxdev SSH: tunnels UP" } else { "Linuxdev SSH: idle" }
})

# Closing the window hides to tray UNLESS Exit was chosen.
$script:BalloonShown = $false
$win.add_Closing({
    param($s, $e)
    if (-not $script:ReallyExit) {
        $e.Cancel = $true
        $win.Hide()
        # Show the "still running in tray" hint only the first time, so it
        # never spams the notification area on repeated closes.
        if (-not $script:BalloonShown) {
            $script:BalloonShown = $true
            $trayIcon.ShowBalloonTip(2000, "Linuxdev SSH Port Forward",
                "Still running in the tray. Right-click the icon to Stop or Exit.",
                [System.Windows.Forms.ToolTipIcon]::Info)
        }
    }
})

# Real teardown happens only on actual exit.
$win.add_Closed({
    $timer.Stop()
    if (Test-TunnelRunning) {
        try { Stop-Process -Id $script:Handle.Proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
    if ($script:Handle) { Stop-SshEvents -Names $script:Handle.Events }
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
})

# Run a WPF application loop (Show, not ShowDialog) so the tray stays alive
# while the window is hidden.
$script:app = New-Object System.Windows.Application
$script:app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown

# If "start on launch" is enabled, kick the tunnels off once the window has
# rendered (so status/log updates are visible). Fires a single time.
if ($chkAutoLaunch.IsChecked) {
    $win.Add_ContentRendered({
        if (-not $script:AutoLaunchDone) {
            $script:AutoLaunchDone = $true
            Set-Status "Auto-starting tunnels on app open..." "#070"
            Start-Tunnels
        }
    })
}

$win.Show()
$script:app.Run()
try { $script:app.Shutdown() } catch {}
