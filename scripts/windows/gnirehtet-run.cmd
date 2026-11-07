@echo off
REM ============================================================
REM  Keep the gnirehtet relay running (PC side).
REM  Leave this window open. The phone connects to it over USB.
REM
REM  Edit GNIREHTET if your path differs.
REM ============================================================
setlocal
set GNIREHTET=C:\gnirehtet
set LOGDIR=%GNIREHTET%

if not exist "%GNIREHTET%\gnirehtet.exe" (
  echo gnirehtet.exe not found in %GNIREHTET%
  pause
  exit /b 1
)

cd /d "%GNIREHTET%"
:loop
gnirehtet.exe relay >> "%LOGDIR%\gnirehtet-relay.log" 2>&1
echo [%date% %time%] relay exited, retrying >> "%LOGDIR%\gnirehtet-relay.log"
timeout /t 5 /nobreak >nul
goto loop
