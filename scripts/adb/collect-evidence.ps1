#Requires -Version 5.1
<#
.SYNOPSIS
  Collect diagnostic evidence from a bootlooping Android device.

.DESCRIPTION
  Pulls props, settings, crash/radio logs, connectivity and telephony dumps,
  tombstones and (optionally) a full bugreport into a timestamped folder.

  Review the output before sharing: it contains serial numbers and possibly
  your phone number. See PRIVACY.md.

.PARAMETER Adb
  Path to adb.exe. Defaults to "adb" (must be on PATH).

.PARAMETER OutDir
  Output folder. Defaults to .\capture

.PARAMETER Bugreport
  Also run `adb bugreport` (slow, 2-10 minutes, large file).

.EXAMPLE
  .\collect-evidence.ps1 -Adb "C:\platform-tools\adb.exe" -OutDir .\capture
#>
param(
    [string]$Adb = "adb",
    [string]$OutDir = ".\capture",
    [switch]$Bugreport
)

$ErrorActionPreference = "Continue"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Save-Sh($cmd, $file) {
    $path = Join-Path $OutDir $file
    & $Adb shell $cmd 2>$null | Out-File -FilePath $path -Encoding utf8
    Write-Host ("    {0,-28} {1}" -f $file, (Get-Item $path).Length + " bytes")
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Write-Step "Waiting for device (plug in USB, allow debugging)..."
& $Adb wait-for-device

Write-Step "Device info"
& $Adb devices -l | Out-File (Join-Path $OutDir "devices.txt") -Encoding utf8

Write-Step "Properties and settings"
Save-Sh "getprop"                 "props.txt"
Save-Sh "settings list global"    "settings-global.txt"
Save-Sh "settings list system"    "settings-system.txt"
Save-Sh "settings list secure"    "settings-secure.txt"

Write-Step "Packages"
Save-Sh "pm list packages"        "packages-all.txt"
Save-Sh "pm list packages -d"     "packages-disabled.txt"
Save-Sh "pm list packages -3"     "packages-thirdparty.txt"

Write-Step "Telephony / connectivity"
Save-Sh "dumpsys connectivity"    "connectivity.txt"
Save-Sh "dumpsys telephony.registry" "telephony-registry.txt"
Save-Sh "dumpsys phone"           "phone.txt"
Save-Sh "getprop gsm.sim.state"   "sim-state.txt"
Save-Sh "getprop gsm.network.type" "network-type.txt"
Save-Sh "dumpsys wifi"            "wifi.txt"

Write-Step "Crash evidence"
Save-Sh "logcat -d -b crash"      "logcat-crash.txt"
Save-Sh "logcat -d -b radio"      "logcat-radio.txt"
Save-Sh "logcat -d -b system"     "logcat-system.txt"
Save-Sh "dmesg"                   "dmesg.txt"
Save-Sh "ls -l /data/tombstones"  "tombstones-list.txt"
Save-Sh "cat /proc/uptime"        "uptime.txt"
Save-Sh "getprop ro.boot.bootreason" "bootreason.txt"

Write-Step "Tombstones (may fail without root)"
& $Adb pull /data/tombstones (Join-Path $OutDir "tombstones") 2>$null

if ($Bugreport) {
    Write-Step "Bugreport (this can take several minutes)"
    & $Adb bugreport (Join-Path $OutDir "bugreport.zip")
}

Write-Step "Summary"
$crashFile = Join-Path $OutDir "logcat-crash.txt"
if (Test-Path $crashFile) {
    $hits = (Select-String -Path $crashFile -Pattern "qcrilNrd" -AllMatches).Count
    Write-Host ("    qcrilNrd mentions in crash buffer: {0}" -f $hits)
}
$up = Join-Path $OutDir "uptime.txt"
if (Test-Path $up) {
    Write-Host ("    uptime: {0}" -f ((Get-Content $up -Raw).Trim()))
}
Write-Host ""
Write-Host "Saved to $OutDir" -ForegroundColor Green
Write-Host "REMINDER: sanitise before publishing. See PRIVACY.md" -ForegroundColor Yellow
