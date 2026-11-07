#Requires -Version 5.1
<#
.SYNOPSIS
  Minimal, non-destructive ADB reverse-tether keeper (gnirehtet).

.DESCRIPTION
  Keeps internet flowing to the phone over USB while you back it up.

  Behaviour:
    - restarts the relay if it dies
    - rebuilds the client if connectivity fails twice in a row
    - restarts the relay if the tunnel stays dead for ~30 s
    - NEVER changes phone settings, NEVER force-stops apps

  Paths are parameters. Nothing is hardcoded.

.PARAMETER PlatformTools
  Folder containing adb.exe. Default: C:\platform-tools

.PARAMETER Gnirehtet
  Folder containing gnirehtet.exe. Default: C:\gnirehtet

.PARAMETER LogDir
  Where logs go. Default: the Gnirehtet folder.

.EXAMPLE
  .\tether-keep.ps1 -PlatformTools "C:\platform-tools" -Gnirehtet "C:\gnirehtet"
#>
param(
    [string]$PlatformTools = "C:\platform-tools",
    [string]$Gnirehtet    = "C:\gnirehtet",
    [string]$LogDir       = ""
)

$ErrorActionPreference = "Continue"

$adb = Join-Path $PlatformTools "adb.exe"
$gn  = Join-Path $Gnirehtet "gnirehtet.exe"
if (-not $LogDir) { $LogDir = $Gnirehtet }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$log = Join-Path $LogDir "tether-keep.log"
$relayOut = Join-Path $LogDir "relay.out.log"
$relayErr = Join-Path $LogDir "relay.err.log"

if (-not (Test-Path $adb)) { throw "adb.exe not found: $adb" }
if (-not (Test-Path $gn))  { throw "gnirehtet.exe not found: $gn" }

$env:ADB = $adb

function Log($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding utf8 $log }

function Start-Relay {
    Start-Process -FilePath $gn -ArgumentList "relay" -WindowStyle Hidden `
        -RedirectStandardOutput $relayOut -RedirectStandardError $relayErr
}

function DevOk {
    $d = (& $adb devices 2>$null) -join "`n"
    return ($d -match "\sdevice\s*$" -or $d -match "\sdevice\r?$")
}

function NetOk {
    $c = & $adb shell "curl -s -m 6 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204" 2>$null
    return ("$c" -match '204')
}

Log "keeper started (adb=$adb gn=$gn)"
Start-Relay
Log "relay started"

$fails = 0
while ($true) {
    Start-Sleep -Seconds 10
    if (-not (DevOk)) { $fails = 0; continue }
    if (NetOk) {
        if ($fails -gt 0) { Log "connectivity OK again" }
        $fails = 0
        continue
    }

    $fails++
    Log "connectivity check failed ($fails)"
    if ($fails -lt 2) { continue }

    # client-side reconnect only (does not kill the relay)
    & $adb reverse tcp:31416 tcp:31416 2>$null | Out-Null
    & $gn start 2>&1 | Out-Null
    Start-Sleep -Seconds 6
    if (NetOk) { Log "recovered by client restart"; $fails = 0; continue }

    if ($fails -ge 5) {
        Log "tunnel dead >30s -> restarting relay"
        Get-Process gnirehtet -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Relay
        Start-Sleep -Seconds 4
        & $adb reverse tcp:31416 tcp:31416 2>$null | Out-Null
        & $gn start 2>&1 | Out-Null
        $fails = 0
    }
}
