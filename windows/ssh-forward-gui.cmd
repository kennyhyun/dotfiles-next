@echo off
rem Double-click launcher -> hands off to the windowless VBS so no console shows.
start "" wscript.exe "%~dp0ssh-forward-gui.vbs"
