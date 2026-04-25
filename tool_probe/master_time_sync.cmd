@echo off
setlocal
set SCRIPT=%~dp0master_time_sync.ps1
if not exist "%SCRIPT%" (
  echo Missing script: %SCRIPT%
  exit /b 1
)

powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT%" %*
