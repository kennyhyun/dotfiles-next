' Windowless launcher for the SSH port-forward GUI.
' Runs powershell with window style 0 (hidden) so no console host flashes.
Dim sh, here
Set sh = CreateObject("WScript.Shell")
here = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "ssh-forward-gui.ps1""", 0, False
