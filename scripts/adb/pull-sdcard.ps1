#Requires -Version 5.1
<#
.SYNOPSIS
  Pull /sdcard from a device that keeps rebooting. Resumable.

.DESCRIPTION
  Runs adb pull repeatedly. Each boot gives a window; the script copies what it
  can and resumes on the next connection. adb pull skips files that already
  exist with the same size, so repeated runs are incremental.

.PARAMETER Adb
  Path to adb.exe. Defaults to "adb".

.PARAMETER Dest
  Destination folder. Defaults to .\phone-backup\sdcard

.PARAMETER Attempts
  How many pull cycles to attempt. Default 30.

.PARAMETER Paths
  Remote paths to pull. Defaults to the high-value folders.

.EXAMPLE
  .\pull-sdcard.ps1 -Adb "C:\platform-tools\adb.exe" -Dest D:\phone-backup -Attempts 50
#>
param(
    [string]$Adb = "adb",
    [string]$Dest = ".\phone-backup\sdcard",
    [int]$Attempts = 30,
    [string[]]$Paths = @(
        "/sdcard/DCIM",
        "/sdcard/Pictures",
        "/sdcard/Download",
        "/sdcard/Documents",
        "/sdcard/Movies",
        "/sdcard/Music",
        "/sdcard/Android/media/com.whatsapp",
        "/sdcard/Android/data",
        "/sdcard/Android/obb"
    )
)

$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null

for ($i = 1; $i -le $Attempts; $i++) {
    Write-Host ("[{0}/{1}] waiting for device..." -f $i, $Attempts) -ForegroundColor Cyan
    & $Adb wait-for-device

    foreach ($p in $Paths) {
        $name = ($p -replace '^/sdcard/','' -replace '/','_')
        $target = Join-Path $Dest $name
        Write-Host ("    pulling {0}" -f $p)
        & $Adb pull $p $target 2>&1 | Out-Null
    }

    $size = 0
    Get-ChildItem -Path $Dest -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object { $size += $_.Length }
    Write-Host ("    total so far: {0:N1} MB" -f ($size / 1MB)) -ForegroundColor Green
    Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "Done. Verify the files open before wiping." -ForegroundColor Yellow
Write-Host "Reminder: never restore /data/vendor/radio or telephony.db from this backup."
