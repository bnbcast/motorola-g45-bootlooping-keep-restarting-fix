#Requires -Version 5.1
<#
.SYNOPSIS
  Optional debloat for Moto G45 5G (fogos). NOT part of the bootloop fix.

.DESCRIPTION
  Reads debloat-optional.txt next to this script and disables packages by tier.
  Tier A only by default. Tier B requires -IncludeTierB. Tier C is never touched.

  Every action is written to a timestamped log so -Rollback is exact.

.PARAMETER Adb
  Path to adb.exe. Defaults to "adb".

.PARAMETER IncludeTierB
  Also disable Tier B packages (may remove features you use).

.PARAMETER Rollback
  Re-enable everything recorded in the most recent debloat log.

.PARAMETER DryRun
  Print what would happen. Changes nothing.

.PARAMETER Force
  Skip the confirmation prompt.

.EXAMPLE
  .\debloat-optional.ps1 -DryRun
  .\debloat-optional.ps1 -TierA
  .\debloat-optional.ps1 -IncludeTierB
  .\debloat-optional.ps1 -Rollback
#>
param(
    [string]$Adb = "adb",
    [switch]$IncludeTierB,
    [switch]$Rollback,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$listFile  = Join-Path $scriptDir "debloat-optional.txt"

if (-not (Test-Path $listFile)) { throw "Missing list: $listFile" }

# Parse "TIER | package | note"
$entries = Get-Content $listFile | ForEach-Object {
    if ($_ -match '^\s*([ABC])\s*\|\s*([\w.]+)\s*\|\s*(.*)$') {
        [pscustomobject]@{ Tier = $matches[1]; Package = $matches[2]; Note = $matches[3] }
    }
}

$logFile = Join-Path $scriptDir ("debloat-log-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

& $Adb wait-for-device

function Is-Disabled([string]$pkg) {
    $d = (& $Adb shell pm list packages -d 2>$null) -join "`n"
    return ($d -match ("package:" + [regex]::Escape($pkg) + "\b"))
}

# ---------------------------------------------------------------- rollback
if ($Rollback) {
    $logs = Get-ChildItem -Path $scriptDir -Filter "debloat-log-*.txt" | Sort-Object LastWriteTime -Descending
    if (-not $logs) { throw "No debloat log found. Nothing to roll back." }
    $latest = $logs[0]
    Write-Host "Rolling back from $($latest.Name)" -ForegroundColor Cyan

    $targets = Get-Content $latest.FullName | Where-Object { $_ -match '^disabled\s+([\w.]+)' } |
               ForEach-Object { $matches[1] }

    if (-not $targets) { Write-Host "Log has no disabled packages."; exit 0 }

    foreach ($p in $targets) {
        if ($DryRun) { Write-Host "  would enable $p"; continue }
        $out = (& $Adb shell pm enable $p 2>&1) -join " "
        if ($out -match "new state: enabled") {
            Write-Host ("  enabled  {0}" -f $p) -ForegroundColor Green
        } else {
            Write-Host ("  skipped  {0}  ({1})" -f $p, $out.Trim()) -ForegroundColor DarkYellow
        }
    }
    Write-Host ""
    Write-Host "Rollback done. Reboot and verify telephony." -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------- disable
$tiers = @("A")
if ($IncludeTierB) { $tiers += "B" }

$targets = $entries | Where-Object { $tiers -contains $_.Tier }

Write-Host ""
Write-Host "Debloat plan (tiers: $($tiers -join ', '))" -ForegroundColor Cyan
$targets | Format-Table -AutoSize Tier, Package, Note

if ($DryRun) {
    Write-Host "DRY RUN - nothing changed." -ForegroundColor Yellow
    exit 0
}

if (-not $Force) {
    $answer = Read-Host "Disable these $($targets.Count) packages? Type YES to continue"
    if ($answer -ne "YES") { Write-Host "Aborted."; exit 1 }
}

"# debloat log $(Get-Date -Format o)" | Out-File $logFile -Encoding utf8
"# rollback with: .\debloat-optional.ps1 -Rollback" | Out-File $logFile -Append -Encoding utf8

$changed = 0
foreach ($t in $targets) {
    if (Is-Disabled $t.Package) {
        Write-Host ("  already  {0}" -f $t.Package) -ForegroundColor DarkGray
        continue
    }
    $out = (& $Adb shell pm disable-user --user 0 $t.Package 2>&1) -join " "
    if ($out -match "new state: disabled") {
        Write-Host ("  disabled {0}" -f $t.Package) -ForegroundColor Green
        "disabled $($t.Package)" | Out-File $logFile -Append -Encoding utf8
        $changed++
    } else {
        Write-Host ("  skipped  {0}  ({1})" -f $t.Package, $out.Trim()) -ForegroundColor DarkYellow
        "skipped  $($t.Package)  $($out.Trim())" | Out-File $logFile -Append -Encoding utf8
    }
}

Write-Host ""
Write-Host ("Disabled {0} package(s). Log: {1}" -f $changed, (Split-Path -Leaf $logFile)) -ForegroundColor Green
Write-Host "Now verify calls, SMS, MMS and mobile data. See docs/08-hardening.md" -ForegroundColor Yellow
