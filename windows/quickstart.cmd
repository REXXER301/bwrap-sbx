@echo off
rem Starts quickstart.ps1 without changing the system's PowerShell execution policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0quickstart.ps1" %*
pause
