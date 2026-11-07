#Requires -Version 5.1
<#
.SYNOPSIS
  Check whether the device is actually stable after a fix.

.DESCRIPTION
  Reports uptime, qcrilNrd crash count, SIM state, network type, default
  network and an HTTP connectivity check. Exits non-zero if any check fails.

  "Stable" requires: uptime >= MinUptime, 0 qcrilNrd crashes, a loaded SIM,
  a real network type, and a non-"none" default network.

.PARAMETER Adb
  Path to adb.exe. Defaults to "adb".

.PARAMETER MinUptime
  Minimum uptime in seconds to consider the boot stable. Default 600 (10 min).

.EXAMPLE
  .\verify-stability.ps1 -Adb "C:\platform-tools\adb.exe" -MinUptime 1200
#>
param(
    [string]$Adb = "adb",
    [int]$MinUptime = 600
)

$ErrorActionPreference = "Continue"
& $Adb wait-for-device

function Sh([string]$cmd) {
    ((& $Adb shell $cmd 2>$null) -join "`n").Trim()
}

$uptimeRaw = Sh "cat /proc/uptime"
$upSec = 0
if ($uptimeRaw -match '^(\d+)') { $upSec = [int]$matches[1] }

$crashLog = Sh "logcat -d -b crash"
$crashCount = ([regex]::Matches($crashLog, 'qcrilNrd')).Count

$sim = Sh "getprop gsm.sim.state"
$net = Sh "getprop gsm.network.type"
$bootReason = Sh "getprop ro.boot.bootreason"
$defaultNet = Sh "dumpsys connectivity | grep -m1 'Active default network'"
$http = Sh "curl -s -m 6 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204"

$checks = @(
    [pscustomobject]@{ Name = "Uptime >= ${MinUptime}s";  Value = "$upSec s";     Pass = ($upSec -ge $MinUptime) },
    [pscustomobject]@{ Name = "qcrilNrd crashes == 0";     Value = "$crashCount";  Pass = ($crashCount -eq 0) },
    [pscustomobject]@{ Name = "SIM loaded";                Value = $sim;           Pass = ($sim -match 'LOADED') },
    [pscustomobject]@{ Name = "Network type present";      Value = $net;           Pass = (-not [string]::IsNullOrWhiteSpace($net)) },
    [pscustomobject]@{ Name = "Default network != none";   Value = $defaultNet;    Pass = ($defaultNet -and $defaultNet -notmatch 'none') },
    [pscustomobject]@{ Name = "HTTP reachable (204)";      Value = $http;          Pass = ($http -eq '204') }
)

Write-Host ""
Write-Host "Moto G45 stability check" -ForegroundColor Cyan
Write-Host ("Boot reason: {0}" -f $bootReason)
Write-Host ""
$checks | Format-Table -AutoSize Name, Value, Pass

$failed = @($checks | Where-Object { -not $_.Pass })
Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "PASS - device looks stable. Reboot once and run this again." -ForegroundColor Green
    exit 0
}

Write-Host ("FAIL - {0} check(s) failed." -f $failed.Count) -ForegroundColor Red
Write-Host "If qcrilNrd is crashing, see docs/01-symptoms.md and docs/04-fixes.md" -ForegroundColor Yellow
exit 1
