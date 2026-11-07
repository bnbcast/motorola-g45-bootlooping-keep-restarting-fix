# 07 — Internet without Wi-Fi and without a SIM

During the incident the phone had **no Wi-Fi** (HAL never initialised) and **no mobile data** (modem never registered). It still needed internet: to trigger a Google Drive backup, download an app, verify an account, or finish setup.

The solution was **gnirehtet** — reverse tethering over the USB cable. No root, no Wi-Fi, no SIM, no carrier.

---

## How it works

```text
┌────────── PC ──────────┐            ┌──────── phone ────────┐
│                        │            │                       │
│  gnirehtet relay       │◄── TCP ────┤  gnirehtet app        │
│  (listens :31416)      │            │  (VPNService)         │
│         ▲              │            │        ▲              │
│         │              │            │        │ tun0           │
│   your PC's internet   │            │   apps' traffic        │
│                        │            │                       │
└────────┬───────────────┘            └───────────────────────┘
         │
    adb reverse tcp:31416 tcp:31416
    (phone's localhost:31416 → PC's localhost:31416)
```

1. The **relay** runs on your PC and speaks to the real internet.
2. `adb reverse` makes the phone's `127.0.0.1:31416` reach the PC's relay over USB.
3. The **app** on the phone creates a `VPNService` interface (`tun0`, `10.0.0.2`) and routes traffic into the tunnel.
4. Android sees a VPN network — and therefore a **default network** — even though Wi-Fi and mobile data are down.

This is why it works when everything else fails: it does not touch the broken telephony or Wi-Fi stack at all.

---

## Install

### 1. Download

Get **gnirehtet** (Rust build, `gnirehtet-rust-win64.zip`) from the official releases:
`https://github.com/Genymobile/gnirehtet/releases`

Unzip to `C:\gnirehtet`. You should have `gnirehtet.exe` and `gnirehtet.apk`.

### 2. Install the APK on the phone

```powershell
adb install C:\gnirehtet\gnirehtet.apk
```

If it says `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, uninstall the old one first:
`adb uninstall com.genymobile.gnirehtet`

### 3. Start the relay (PC)

```powershell
cd C:\gnirehtet
.\gnirehtet.exe relay
```

Leave this window open. It prints connection logs.

### 4. Start the client (PC, second window)

```powershell
cd C:\gnirehtet
.\gnirehtet.exe start
```

This runs `adb reverse tcp:31416 tcp:31416` and launches the app's VPN service.

### 5. Verify

```powershell
adb shell "curl -s -m 6 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204"
```

- `204` → working.
- `000` or empty → see troubleshooting.

Also check the phone has a default network now:

```powershell
adb shell "dumpsys connectivity | grep -m1 'Active default network'"
```

It should show a VPN network instead of `none`.

---

## The catch: TCP, not everything

gnirehtet is a **TCP relay**. This matters:

| Works | Often does not |
|---|---|
| HTTP / HTTPS (browsers, curl, app APIs) | ICMP (`ping`) |
| Play Store downloads (mostly) | UDP/QUIC (some Google traffic) |
| WhatsApp messaging | Some VoIP/video calls |
| `curl`, `wget` | mDNS, LAN discovery |
| Gmail **web** | Play Services "network validation" (may say "no internet" while HTTP works) |

That last row is the annoying one: **Play Services can report "Can't connect to the Internet" even though the tunnel is fine**, because it validates using UDP/QUIC. Apps that rely on Play Services' validation may refuse to start.

Workarounds used in this incident:

- Use the **browser** or **web versions** for Google services.
- Trigger backups from inside the app, not from Play Services.
- Accept that some apps will insist they are offline. The tunnel still moves data.

---

## Automating it: the keeper and the watchdog

A reboot kills the tunnel. Two scripts are included:

### `scripts/windows/tether-keep.ps1` — minimal, non-destructive

- Restarts the **relay** if it dies.
- Rebuilds the **client** if connectivity fails twice in a row.
- **Never changes phone settings, never force-stops apps.**
- Logs to `tether-keep.log`.

Use this when you are backing up and do not want the phone's state touched.

```powershell
.\scripts\windows\tether-keep.ps1 -PlatformTools "C:\platform-tools" -Gnirehtet "C:\gnirehtet"
```

### `scripts/windows/tether-watchdog.ps1` — aggressive, for the crash loop

- Waits for the device after every reboot.
- Quiets the radio (airplane mode) and trims background apps.
- Rebuilds the tunnel, validates it, and retries.
- Resets the ADB server if the device disappears for 30 s.
- Logs to `tether.log`.

Use this when the phone reboots every 2 minutes and you need it to come back automatically.

```powershell
.\scripts\windows\tether-watchdog.ps1 -PlatformTools "C:\platform-tools" -Gnirehtet "C:\gnirehtet"
```

> Both scripts are path-parameterised. The originals hardcoded `D:\platform-tools`; that has been removed. See `PRIVACY.md`.

### `scripts/windows/START-TETHER.cmd`

Double-click wrapper that starts the keeper in a hidden window.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `adb devices` empty | charge-only cable, driver, or ADB not authorised | another cable/port; unlock phone and allow debugging |
| `gnirehtet start` says `error: no devices/emulators found` | ADB lost the device | `adb kill-server; adb start-server; adb devices` |
| Tunnel up, but no internet | relay not running, or PC has no internet | check the relay window; test on the PC |
| `curl` returns `000` | DNS or TCP blocked | try `curl http://1.1.1.1` to separate DNS from routing |
| Works for a minute, then dies | phone rebooted | use the watchdog |
| Play Store says "no connection" | Play Services validation over UDP | ignore, or use web/APK sideload |
| VPN icon but apps still offline | app has no default network / split tunnelling | `adb shell cmd connectivity reevaluate` |
| `INSTALL_FAILED_*` | old version installed | `adb uninstall com.genymobile.gnirehtet` |

### Reset everything

```powershell
adb kill-server
adb start-server
adb devices
adb reverse --remove-all
adb reverse tcp:31416 tcp:31416
.\gnirehtet.exe start
```

---

## Alternatives, and why they were not used

| Option | Requires | Verdict |
|---|---|---|
| **USB-C Ethernet adapter** | OTG support, driver | Works on many phones and is faster/cleaner than gnirehtet. Worth trying if you have an adapter. Not available here. |
| **Bluetooth PAN** | A paired PC/phone sharing internet | Slow, flaky, and pairing needs a working UI. |
| **Wi-Fi hotspot from another phone** | Working Wi-Fi on the broken phone | The Wi-Fi HAL was dead — impossible in this incident. |
| **USB tethering from the broken phone to a PC** | Working modem | Opposite direction; not applicable. |
| **`adb reverse` + a local proxy** | Manual proxy config per app | Works for specific apps, not system-wide. gnirehtet is the generalisation. |
| **Ethernet over USB via `usb0` + NAT** | Root, `ip` rules | No root available. |
| **Mobile data** | Working modem | The modem was the thing that was broken. |

**Key limitation to plan for:** gnirehtet needs **USB debugging already enabled**. If it was never enabled and the phone cannot boot long enough to enable it, you cannot use this method. In that case, the phone's own Google Photos/Drive sync (if already configured) is your only cloud path.

---

## Why this matters beyond this bug

Reverse tethering is the general answer to "my phone has no network but I need it online":

- broken Wi-Fi chip, broken modem, no SIM
- travelling with no local SIM
- a phone stuck on a captive-portal loop
- backing up a phone whose radios are deliberately disabled

It is also the reason this incident was recoverable at all: with no Wi-Fi, no SIM, and a 2-minute uptime window, the Drive backup and the diagnostic evidence both went out over USB.
