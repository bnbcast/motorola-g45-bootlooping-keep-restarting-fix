#Requires -Version 5.1
<#
.SYNOPSIS
  Disable the 13 oemhook-heavy packages as a TEMPORARY crash-rate reducer.

.DESCRIPTION
  This is NOT a fix. It reduced crashes from ~14 per boot to ~2 on the
  reference device. The modem still sends unsolicited oemhook indications.

  Run reenable-oemhook-packages.ps1 to undo.

.PARAMETER Adb
  Path to adb.exe. Defaults to "adb".
#>
param([string]$Adb = "adb")

$ErrorActionPreference = "Continue"

$packages = @(
    "com.motorola.omadm.service",
    "com.qualcomm.qti.cne",
    "com.motorola.hiddenmenuapp",
    "com.motorola.carriersettingsext",
    "com.motorola.msimsettings",
    "com.motorola.entitlement",
    "com.motorola.genie",
    "com.motorola.ccc.notification",
    "com.motorola.moto",
    "com.qualcomm.qti.uimGbaApp",
    "com.qualcomm.qti.remoteSimlockAuth",
    "com.motorola.help",
    "com.motorola.wifi.motowifimetrics"
)

& $Adb wait-for-device

Write-Host "Disabling $($packages.Count) oemhook packages..." -ForegroundColor Cyan
Write-Host "WARNING: temporary mitigation only. Re-enable after the real fix." -ForegroundColor Yellow
Write-Host ""

foreach ($p in $packages) {
    $out = (& $Adb shell pm disable-user --user 0 $p 2>&1) -join " "
    if ($out -match "new state: disabled") {
        Write-Host ("  OK      {0}" -f $p) -ForegroundColor Green
    } else {
        Write-Host ("  SKIP    {0}  ({1})" -f $p, $out.Trim()) -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "Now quiet the radio (optional, reduces crash rate further):" -ForegroundColor Cyan
Write-Host '  adb shell settings put global airplane_mode_on 1'
Write-Host '  adb shell cmd connectivity airplane-mode enable'
Write-Host ""
Write-Host "Check the crash rate:" -ForegroundColor Cyan
Write-Host '  adb shell "logcat -d -b crash | grep -c qcrilNrd"'
Write-Host ""
Write-Host "Undo with: .\reenable-oemhook-packages.ps1" -ForegroundColor Yellow
