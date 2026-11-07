#Requires -Version 5.1
<#
.SYNOPSIS
  Re-enable the 13 oemhook packages disabled during recovery.

.DESCRIPTION
  This was the state after the factory reset on the reference device: all 13
  re-enabled, still zero crashes. Proves the packages were never the cause.

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

Write-Host "Re-enabling $($packages.Count) packages..." -ForegroundColor Cyan
Write-Host "WARNING: if you have not fixed the root cause, the crash loop may return." -ForegroundColor Yellow
Write-Host ""

foreach ($p in $packages) {
    $out = (& $Adb shell pm enable $p 2>&1) -join " "
    if ($out -match "new state: enabled") {
        Write-Host ("  OK      {0}" -f $p) -ForegroundColor Green
    } else {
        Write-Host ("  SKIP    {0}  ({1})" -f $p, $out.Trim()) -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "Still-disabled packages:" -ForegroundColor Cyan
& $Adb shell pm list packages -d

Write-Host ""
Write-Host "Verify stability: .\verify-stability.ps1" -ForegroundColor Yellow
