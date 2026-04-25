@echo off
setlocal
set SCRIPT=%~dp0wireless_hid_cli.ps1
if not exist "%SCRIPT%" (
  echo Missing script: %SCRIPT%
  exit /b 1
)

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT%" %*
