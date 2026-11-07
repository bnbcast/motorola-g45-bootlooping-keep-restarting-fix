#Requires -Version 5.1
<#
.SYNOPSIS
  Aggressive ADB reverse-tether watchdog for a device that keeps rebooting.

.DESCRIPTION
  On every (re)connect it:
    1. optionally quiets the radio (airplane mode) to reduce crash rate
    2. trims background apps to extend the uptime window
    3. rebuilds the gnirehtet ADB tunnel (internet without Wi-Fi/SIM)
    4. validates connectivity every 5 s and rebuilds the tunnel if it drops
    5. resets the adb server if the device disappears for 30 s

  Unlike the original field script, this version:
    - has NO hardcoded paths (everything is a parameter)
    - opens NO browser or account pages
    - contains no account identifiers

  Use this while backing up a bootlooping phone. It does change phone settings
  (airplane mode, animations, force-stops) — see -QuietRadio and -TrimApps.

.PARAMETER PlatformTools
  Folder containing adb.exe. Default: C:\platform-tools

.PARAMETER Gnirehtet
  Folder containing gnirehtet.exe. Default: C:\gnirehtet

.PARAMETER LogDir
  Where logs go. Default: the Gnirehtet folder.

.PARAMETER QuietRadio
  Turn airplane mode ON and Wi-Fi OFF. Reduces oemhook traffic, at the cost of
  no native network. Recommended while the loop is active.

.PARAMETER TrimApps
  Force-stop a list of heavy/background apps. Reduces CPU load.

.EXAMPLE
  .\tether-watchdog.ps1 -QuietRadio -TrimApps
#>
param(
    [string]$PlatformTools = "C:\platform-tools",
    [string]$Gnirehtet    = "C:\gnirehtet",
    [string]$LogDir       = "",
    [switch]$QuietRadio,
    [switch]$TrimApps
)

$ErrorActionPreference = "Continue"

$adb = Join-Path $PlatformTools "adb.exe"
$gn  = Join-Path $Gnirehtet "gnirehtet.exe"
if (-not $LogDir) { $LogDir = $Gnirehtet }
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$log      = Join-Path $LogDir "tether.log"
$relayOut = Join-Path $LogDir "relay.out.log"
$relayErr = Join-Path $LogDir "relay.err.log"

if (-not (Test-Path $adb)) { throw "adb.exe not found: $adb" }
if (-not (Test-Path $gn))  { throw "gnirehtet.exe not found: $gn" }

$env:ADB = $adb

# Heavy background apps that eat CPU during a short uptime window.
# Generic, not personal: edit freely.
$heavyApps = @(
    "com.instagram.android", "com.facebook.katana", "com.facebook.orca",
    "com.google.android.youtube", "com.android.vending", "com.android.chrome",
    "com.spotify.music", "com.twitter.android", "com.zhiliaoapp.musically",
    "com.motorola.ccc.ota", "com.motorola.moto", "com.motorola.bug2go",
    "com.motorola.aiservices", "com.motorola.help"
)

function Log($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding utf8 $log }
function Sh($cmd) { & $adb shell $cmd 2>$null }

function Start-Relay {
    Start-Process -FilePath $gn -ArgumentList "relay" -WindowStyle Hidden `
        -RedirectStandardOutput $relayOut -RedirectStandardError $relayErr
}

function Quiet-Radio {
    Sh "settings put global airplane_mode_on 1"
    Sh "cmd connectivity airplane-mode enable"
    Sh "settings put global wifi_on 0"
    Sh "cmd wifi set-wifi-enabled disabled"
    Sh "settings put global wifi_scan_always_enabled 0"
    Sh "settings put global ble_scan_always_enabled 0"
    Sh "settings put global network_recommendations_enabled 0"
}

function Reduce-Load {
    Sh "svc power stayon usb"
    Sh "settings put system screen_off_timeout 1800000"
    Sh "wm dismiss-keyguard"
    Sh "settings put global window_animation_scale 0"
    Sh "settings put global transition_animation_scale 0"
    Sh "settings put global animator_duration_scale 0"
    if ($TrimApps) { foreach ($p in $heavyApps) { Sh "am force-stop $p" } }
    Sh "am kill-all"
}

function Ensure-Tunnel {
    $tun = Sh "ip addr show tun0"
    if ("$tun" -match "10\.0\.0\.2") { return $true }

    Log "tunnel missing -> restarting relay/client"
    Get-Process gnirehtet -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Relay
    Start-Sleep -Seconds 3
    Sh "true" | Out-Null
    & $adb reverse tcp:31416 tcp:31416 2>$null | Out-Null
    & $gn start 2>&1 | Out-Null
    Start-Sleep -Seconds 4

    $tun2 = Sh "ip addr show tun0"
    if ("$tun2" -match "10\.0\.0\.2") { Log "VPN tunnel UP"; return $true }
    Log "VPN tunnel still down"
    return $false
}

function Wait-Internet($tries = 12) {
    for ($i = 0; $i -lt $tries; $i++) {
        $code = Sh "curl -s -m 6 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204"
        if ("$code" -match '204') { Log "internet validated (204)"; return $true }
        Ensure-Tunnel | Out-Null
        Start-Sleep -Seconds 3
    }
    Log "internet validation failed"
    return $false
}

# Apps need a DEFAULT network; the tunnel alone is not always enough.
# Restarting the VPN app makes it re-register its NetworkAgent.
function Ensure-DefaultNet {
    $dn = Sh "dumpsys connectivity 2>/dev/null | grep -m1 'Active default network'"
    if ("$dn" -notmatch 'none') { Log "default network: $(($dn -split ':')[-1].Trim())"; return $true }

    Log "default network: none -> restarting VPN app"
    Sh "am force-stop com.genymobile.gnirehtet" | Out-Null
    Start-Sleep -Seconds 2
    Sh "am start -a com.genymobile.gnirehtet.START -n com.genymobile.gnirehtet/.GnirehtetActivity" | Out-Null
    Start-Sleep -Seconds 6

    $dn2 = Sh "dumpsys connectivity 2>/dev/null | grep -m1 'Active default network'"
    if ("$dn2" -notmatch 'none') { Log "default network restored: $(($dn2 -split ':')[-1].Trim())"; return $true }
    Log "default network STILL none"
    return $false
}

Log "watchdog started (quietRadio=$QuietRadio trimApps=$TrimApps)"

while ($true) {
    # --- wait for the device to appear -------------------------------------
    $miss = 0
    while ($true) {
        $dev = (& $adb devices 2>$null) -join "`n"
        if ($dev -match "\sdevice\s*$" -or $dev -match "\sdevice\r?$") { break }
        Start-Sleep -Seconds 5
        $miss++
        if ($miss % 6 -eq 0) {
            Log "no device for $([int]($miss*5))s - resetting adb server"
            & $adb kill-server 2>$null | Out-Null
            & $adb start-server 2>$null | Out-Null
        }
    }

    Start-Sleep -Seconds 2
    Log "device online"

    Get-Process gnirehtet -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    if ($QuietRadio) { Quiet-Radio }
    Reduce-Load

    if (Wait-Internet) {
        Ensure-DefaultNet | Out-Null
    }

    # --- monitor until the device reboots or disappears --------------------
    while ($true) {
        Start-Sleep -Seconds 5
        $up = Sh "cut -d' ' -f1 /proc/uptime"
        if (-not $up) { Log "device dropped (reboot) - re-arming"; break }
        if ($up -match '^(\d+)' -and [int]$matches[1] -lt 25) {
            Log "rebooted (uptime $($matches[1])s) - re-applying"
            break
        }
        if (-not (Ensure-Tunnel)) { continue }

        $code = Sh "curl -s -m 6 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204"
        if ("$code" -notmatch '204') {
            Log "connectivity check failed ($code) -> rebuild tunnel"
            Get-Process gnirehtet -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
    }
}
