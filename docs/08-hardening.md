# 08 — Hardening and optional debloat

> **This is not part of the fix.** The phone was stable after the modem NV repair (`erase modemst1`/`modemst2`) **before** any debloat, with all 13 packages re-enabled. Debloating is cosmetic/performance tuning. Skipping it changes nothing about the bootloop.

Read the risks before running anything here.

---

## Why debloat at all

The reference device was a carrier model with a heavy Motorola + Qualcomm + Meta + Google preload. Disabling unused system apps:

- reduces background CPU/RAM and radio wakeups
- reduces the number of processes that can send oemhook traffic (marginally relevant to this bug)
- removes ads/telemetry/notification spam

It does **not**:

- fix the `libmotext_inf.so` bug
- guarantee better battery life
- make the phone faster in any way you can measure without a benchmark

---

## The one rule

**`pm disable-user --user 0` is reversible. `pm uninstall --user 0` is *usually* reversible but can break OTA and factory reset.**

Prefer `disable-user`. Keep the package list so you can roll back.

```bash
adb shell pm disable-user --user 0 <package>    # disable
adb shell pm enable <package>                   # re-enable
adb shell pm list packages -d                   # what is disabled
```

---

## Risk tiers

### Tier A — safe, cosmetic

| Package | What it is |
|---|---|
| `com.facebook.appmanager` | Meta app updater |
| `com.facebook.services` | Meta background services |
| `com.facebook.system` | Meta system stub |
| `com.facebook.katana` | Facebook app |
| `com.google.android.apps.youtube.music` | YouTube Music |
| `com.google.android.apps.googleassistant` | Google Assistant |
| `com.google.android.videos` | Google TV / Play Movies |
| `com.google.android.apps.nbu.files` | Files by Google |
| `com.motorola.motocare` | Moto Care support app |
| `com.motorola.help` | Moto Help |
| `com.motorola.help.extlog` | Moto Help log uploader |
| `com.motorola.demo` | Retail demo mode |
| `com.motorola.mobiledesktop` | "Ready For" desktop mode |
| `com.motorola.mobiledesktop.core` | same |
| `com.motorola.bug2go` | Bug reporting |
| `com.motorola.aiservices` | Moto AI services |
| `com.motorola.genie` | Moto assistant |
| `com.motorola.motocit` | Hardware diagnostics (CIT) |
| `com.motorola.appforecast` | App prediction |
| `com.motorola.lifetimedata` | Usage telemetry |
| `com.motorola.bach.modemstats` | Modem statistics uploader |
| `com.motorola.dciservice` | Device care service |
| `com.motorola.nfwlocationattribution` | Location attribution |
| `com.motorola.revoker.services` | Permission revoker |
| `com.motorola.appdirectedsmsproxy` | App-directed SMS proxy |
| `com.motorola.wifi.motowifimetrics` | Wi-Fi metrics uploader |
| `com.ertanto.kompas.official` | Preinstalled local news app |
| `id.mjs.etalaseapp` | Preinstalled local store app |

### Tier B — optional, may affect features you use

| Package | What it is | What you lose |
|---|---|---|
| `com.android.chrome` | Chrome | In-app browser / Custom Tabs fall back to another browser. If Chrome is your WebView provider, some apps break. Check *Developer options → WebView implementation* first. |
| `com.motorola.ccc.ota` | Motorola OTA client | **No more system updates.** Do not disable if you still want OTA. It often refuses to disable anyway. |
| `com.motorola.ccc.notification` | OTA/device-mgmt notifier | OTA notifications |
| `com.motorola.ccc.devicemanagement` | Device management | Enterprise/MDM features |
| `com.motorola.omadm.service` | Carrier provisioning (OMADM) | Carrier provisioning, some VoLTE/VoWiFi activation |
| `com.qualcomm.qti.uimGbaApp` | GBA authentication | Some carrier auth flows |
| `com.qualcomm.qti.remoteSimlockAuth` | Remote SIM lock | Carrier SIM-lock services |
| `com.motorola.entitlement` | Entitlement checks | Carrier feature entitlement (VoLTE/VoWiFi toggles) |
| `com.motorola.msimsettings` | Multi-SIM settings | Dual-SIM settings UI |
| `com.motorola.carriersettingsext` | Carrier config extensions | Carrier-specific behaviour |
| `com.motorola.paks` | Motorola account services | Moto account features |
| `com.motorola.rcsConfigService` | RCS configuration | RCS/Chat Features |
| `com.motorola.carrierconfig` | Carrier config | Carrier-specific defaults |
| `com.oem.euiccpartnerapp.overlay.retca` | eSIM partner overlay | eSIM flows |
| `com.google.android.gms.supervision` | Family Link supervision | Parental controls |
| `com.motorola.motosignature.app` / `...2.app` | Moto signature | Moto theming/signature features |

> Several Tier B entries are **already disabled by the carrier/Motorola** on many units. Re-enabling them is usually harmless, but do not assume they were active.

### Tier C — do not touch

| Package | Why |
|---|---|
| `com.qualcomm.qti.telephonyservice` | Core telephony. Disabling can break calls/SMS/data. |
| `com.qualcomm.qti.uim` | SIM/UIM stack. Can break SIM detection. |
| `com.qualcomm.qti.dynamicddsservice` | Dynamic dual-SIM. Can break DSDS. |
| `com.qualcomm.qti.uceShimService` | RCS/UCE shim. Can break messaging features. |
| `com.android.cellbroadcastservice.overlay`, `com.android.cellbroadcast.overlay` | **Emergency alerts** (earthquake/tsunami in Indonesia). Do not disable. |
| `com.motorola.att.phone.extensions` | Carrier telephony extension — device-specific, risky. |
| `com.android.providers.telephony`, `com.android.phone`, `com.android.server.telecom` | Core. Never. |
| `com.google.android.gms`, `com.google.android.gsf` | Play services. Never. |

The original field notes listed several Tier C packages as "disabled successfully". That is **not recommended** — those were probably not actually disabled, or the device lost features silently.

---

## How to apply

### Option A — Canta (no root, needs Shizuku)

1. Install **Shizuku** (Play Store) and start it via **Wireless debugging** or ADB.
2. Install **Canta** (GitHub: `samolego/Canta`).
3. Canta lists apps with a risk label (RECOMMENDED / ADVANCED / EXPERT / SYSTEM). Only disable RECOMMENDED unless you understand the entry.
4. Search each package, toggle it off.

Canta was used on the reference device for the initial pass. It is the safest UI because it warns per-package.

### Option B — ADB script

```powershell
.\scripts\adb\debloat-optional.ps1 -DryRun    # print the list, change nothing
.\scripts\adb\debloat-optional.ps1 -TierA     # only Tier A
.\scripts\adb\debloat-optional.ps1            # Tier A + B (prompts)
```

The script is **idempotent** and writes a log of what it changed so rollback is exact.

### Option C — manual

```bash
for p in com.facebook.katana com.facebook.appmanager com.facebook.services \
         com.facebook.system com.motorola.demo com.motorola.help; do
  adb shell pm disable-user --user 0 "$p"
done
```

---

## Rollback

```powershell
.\scripts\adb\debloat-optional.ps1 -Rollback
```

or manually:

```bash
adb shell pm enable com.facebook.katana
# ... one line per package
```

If a package was disabled by the carrier and you re-enable it, you may get features back that the carrier did not want you to have (e.g. RCS). That is usually fine, but it is a change from stock.

**Nuclear option** — factory reset restores every preinstalled package.

---

## Verify you did not break telephony

After any debloat, test:

```bash
# SIM still detected
adb shell getprop gsm.sim.state          # expect LOADED (or ABSENT,LOADED with one SIM)

# Can it register?
adb shell getprop gsm.network.type       # LTE / NR / UMTS

# Data still works
adb shell "curl -s -m 6 -o /dev/null -w '%{http_code}' https://www.google.com"   # 200

# VoLTE flag (carrier-dependent)
adb shell dumpsys telephony.registry | grep -i -E "volte|vonr|ims"
```

Then, with your own eyes:

- [ ] Place a call
- [ ] Receive a call
- [ ] Send and receive an SMS
- [ ] Send and receive an MMS
- [ ] Toggle mobile data off/on
- [ ] Toggle airplane mode off/on
- [ ] Make an emergency test? **Do not actually call emergency services.** Just confirm the dialer opens and shows the SIM as available.

If any of these fail, roll back the last batch.

---

## Stability monitoring (worth doing for a week)

A simple daily check:

```bash
adb shell 'echo UP=$(cut -d" " -f1 /proc/uptime) CRASH=$(logcat -d -b crash | grep -c qcrilNrd)'
```

Or on the phone, with Termux + `adb` over wireless debugging (advanced), or just by noticing: **if the phone has been up for days, you are fine.**

Watch for:

- unexplained reboots (check `ro.boot.bootreason`)
- `qcrilNrd` reappearing in `logcat -b crash`
- SIM dropping to `NOT_READY` and staying there
- Wi-Fi refusing to enable

If the same crash signature returns, go back to [`01-symptoms.md`](01-symptoms.md) — do not start disabling packages again.

---

## OTA policy after the fix

- **Do not disable `com.motorola.ccc.ota`** if you want security patches.
- Before accepting a major OTA, back up (again). An interrupted OTA is one plausible way the modem NV got corrupted in the first place.
- After an OTA, verify stability with the same commands — and check `subsys2/crash_count`.
- An OTA will not repair `modemst1/2`. If the loop ever returns, re-run the NV erase.

---

## Summary

| Action | Recommended? |
|---|---|
| Modem NV erase (`erase modemst1`/`modemst2`) — **the fix** | ✅ Yes |
| Tier A debloat | ✅ Optional, safe |
| Tier B debloat | ⚠️ Only if you understand the loss |
| Tier C debloat | ❌ No |
| Disabling OTA | ❌ Only if you accept no security updates |
| Rooting / custom ROM | ❌ Not for this bug |
