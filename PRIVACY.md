# Privacy and redaction

This repository is published from a real device. Everything below documents exactly what was removed, what was kept, and why.

**Goal:** publish a reproducible technical report without identifying the device owner.

---

## Removed entirely (not in this repository)

| Item | Why |
|---|---|
| `03_Backups/Whatsapp/**` — 49 MB of `.crypt14` | Private chat databases, contacts, status backups, sticker packs. Encrypted, but still private. Never publish. |
| `last_shot.png` | Screenshot of the device showing a partially visible Google account URL and the user's browser session. |
| `window_dump*.xml` (6 files) | UI hierarchy dumps listing the user's installed apps, folders and launcher layout. No technical value for this report. |
| `Moto_G45_5G_Bootloop_Full_Report.txt`, `COMPLETE_REPORT.md`, `STATE.md`, `recovery-report.md` (raw) | Contained the serial number, local paths and the email address. Their content is preserved here in sanitised form. |
| `moto-g45-recovery-full-report.zip` | Bundle of the above. |
| Full `device-snapshot.txt` | 52 KB of raw props including serial, account cache keys, Bluetooth device name, saved Wi-Fi hashes. Replaced by `evidence/device-snapshot-sanitized.txt`. |
| `tether-keep.log` (raw) | Kept only as a sanitised excerpt. |

---

## Replaced or masked

| Original | Replacement | Where |
|---|---|---|
| Device serial (alphanumeric, ~11 chars) | `<SERIAL>` / omitted | All docs and evidence |
| Owner's email address | removed | `tether-watchdog.ps1`, logs |
| `D:\platform-tools\adb.exe` | `-PlatformTools` parameter | scripts |
| `D:\platform-tools\gnirehtet\...` | `-Gnirehtet` parameter | scripts |
| `D:\platform-tools\*.log` | `$LogDir` parameter | scripts |
| `C:\Users\<name>\Desktop\...` | removed / generic | docs |
| Saved Wi-Fi SSID hashes | removed | `STATE.md` source → not reproduced |
| Bluetooth device name | removed | device snapshot |
| Google account cache keys (`cache_key.system_server.accounts_data`, etc.) | removed | device snapshot |
| `https://myaccount.google.com/security?authuser=…` | `<account-security-page>` | watchdog script + log |
| Personal app list (Instagram, Spotify, local banking/news apps) | removed | UI dumps dropped |

---

## Kept on purpose

| Item | Why it is safe / why it matters |
|---|---|
| Carrier names **XL Axiata** and **AXIS** | Relevant to reproducing a dual-SIM modem bug. They are major Indonesian carriers with millions of subscribers — not identifying on their own. |
| MCC/MNC `51011`, country `id` | Technical detail for the modem/registration behaviour. |
| Build fingerprints, baseband version, `SM6375`, `fogos` | Public firmware metadata. |
| Crash backtrace, fault address, package names | The technical substance of the report. |
| Dates (2026-11-05 → 2026-11-07) | Timeline evidence. Combined with the above, not enough to identify a person. |
| Debloat package list | Generic preinstalled apps, no personal data. |

---

## What was *not* leaked

Before publishing, the tree was checked for:

```text
serial numbers        ZP… / ro.serialno / ro.boot.serialno
IMEI / MEID           \d{15}
email addresses       @gmail.com, @outlook.com, ...
phone numbers         \+62…, 08…
Wi-Fi SSIDs / BSSIDs  saved networks, MAC addresses
accounts              cache_key.*account*, authuser=
local paths           C:\Users\, D:\platform-tools
API keys / tokens     sk-, ghp_, AIza, xoxb-
```

The scripts in this repo contain **no hardcoded user paths** — every path is a parameter with a sensible default.

---

## If you contribute

Please do not paste raw device dumps. Before opening an issue or PR, remove:

1. `ro.serialno`, `ro.boot.serialno`, `ro.vendor.boot.serialno`
2. IMEI/MEID (`*#06#` output), ICCID, IMSI, phone number
3. Wi-Fi SSIDs/BSSIDs and MAC addresses
4. Email addresses and account names
5. `cache_key.*` and `authuser=` values
6. Local filesystem paths containing your username
7. Screenshots that show notifications, account avatars or browser tabs

A useful issue contains: **model**, **build fingerprint**, **baseband**, the **backtrace**, and what you already tried. Nothing else is needed.

---

## Reporting a privacy problem

If you believe something in this repository still identifies the original device owner, open an issue titled `privacy:` (without quoting the sensitive value in the title) or contact the maintainer privately. It will be removed promptly.
