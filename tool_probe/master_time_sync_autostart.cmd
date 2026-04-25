@echo off
setlocal
set SCRIPT=%~dp0master_time_sync.cmd
if not exist "%SCRIPT%" (
  echo Missing script: %SCRIPT%
  exit /b 1
)

call "%SCRIPT%" -Command watch-lock -PollMilliseconds 15000 -WatchSeconds 60 -LockSymbolMilliseconds 90 -LockRepeatCount 1
