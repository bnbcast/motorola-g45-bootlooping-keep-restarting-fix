@echo off
REM ============================================================
REM  Start the USB reverse-tether keeper (gnirehtet).
REM  Gives the phone internet through the PC over USB.
REM
REM  Edit the two paths below if yours differ.
REM ============================================================
setlocal
set PLATFORM_TOOLS=C:\platform-tools
set GNIREHTET=C:\gnirehtet
set LOGDIR=%GNIREHTET%

if not exist "%PLATFORM_TOOLS%\adb.exe" (
  echo adb.exe not found in %PLATFORM_TOOLS%
  echo Edit PLATFORM_TOOLS at the top of this file.
  pause
  exit /b 1
)

if not exist "%GNIREHTET%\gnirehtet.exe" (
  echo gnirehtet.exe not found in %GNIREHTET%
  echo Edit GNIREHTET at the top of this file.
  pause
  exit /b 1
)

"%PLATFORM_TOOLS%\adb.exe" start-server

powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tether-keep.ps1" -PlatformTools "%PLATFORM_TOOLS%" -Gnirehtet "%GNIREHTET%" -LogDir "%LOGDIR%"

echo.
echo Tunnel keeper started (hidden window).
echo   log: %LOGDIR%\tether-keep.log
echo.
echo Test from the phone:
echo   adb shell "curl -s -m 6 -o /dev/null -w '%%{http_code}' http://connectivitycheck.gstatic.com/generate_204"
echo   ^(204 = working^)
endlocal
