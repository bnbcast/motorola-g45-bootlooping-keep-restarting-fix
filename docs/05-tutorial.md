# 05 — Tutorial: the whole recovery, start to finish

A plain-language walkthrough. No prior Android experience assumed. Total time: **2–4 hours**, most of it waiting for downloads and first boot.

If you only want the short version, [README](../README.md#tldr--if-your-phone-is-bootlooping-right-now) has it.

---

## What you will need

The full checklist is in [`00-requirements.md`](00-requirements.md). The short version:

| Item | Notes |
|---|---|
| **Windows 10/11 PC or laptop** | Required for LMSA/Software Fix. Admin rights needed to install drivers |
| **A *data* USB cable** | Many cables are charge-only. If `adb devices` shows nothing, try another cable **first** |
| **ADB installed** (Platform-Tools) | `adb version` must work in PowerShell. Install guide: [`00-requirements.md#install-adb`](00-requirements.md#install-adb) |
| **USB debugging enabled + "Always allow"** | Tick **"Always allow from this computer"** in the RSA prompt. Without it you re-authorize after every reboot |
| **Screen lock set to None (temporarily)** | With a PIN/pattern, `/data` stays encrypted until you unlock, so ADB is unusable for part of every boot — and the window is only 1.5–3 min |
| **Developer options → Stay awake** | Keeps the screen on while charging so it does not re-lock |
| **A direct USB port** | No hub, no dock, no extension cable |
| **Internet on the PC** | For Platform-Tools, gnirehtet and 2–5 GB of firmware |
| **30–60 GB free on the PC** | Backups + firmware |
| **Phone charged > 50 %** | Keep it on the charger during the whole process |
| **Google account password** | Required after a factory reset (FRP) |
| **Screen lock PIN/pattern** | Some builds ask for it after a reset |
| **SIM that can receive SMS** | Needed to reactivate WhatsApp and test LTE |
| **2FA seeds exported** | Otherwise a wipe can lock you out of your accounts |
| **~2–4 hours** | Mostly waiting for downloads and first boot |

Optional but recommended: **a second screen or phone** — you will be reading this guide while the phone is down.

> You do **not** need root, an unlocked bootloader, a custom ROM, or a paid tool.

---

## Phase 0 — Do not skip this: back up

**A factory reset deletes everything in `/data`: photos in internal storage, WhatsApp chats, SMS, call logs, app logins, 2FA authenticator seeds, downloaded files.**

If the phone boots for at least 30 seconds at a time, you can copy files. If it does not, read [`06-backup.md`](06-backup.md#when-the-phone-barely-boots) for the MTP/recovery tricks.

Minimum viable backup:

1. **Photos/videos** — plug into the PC, allow **File transfer / MTP**, copy `DCIM`, `Pictures`, `Download`, `Movies`, `Music`, `Documents`.
2. **WhatsApp** — in the app: *Settings → Chats → Chat backup → Back up to Google Drive* (include videos if you have space). Also copy `/sdcard/Android/media/com.whatsapp/WhatsApp/Databases/` to the PC.
3. **Authenticator apps** — export/migrate the seeds **now**. A wiped phone with no exported 2FA seeds can lock you out of every account. This is the single most common disaster after a factory reset.
4. **SMS/call log** — install *SMS Backup & Restore*, back up to a file, copy the file to the PC.
5. **Contacts** — *Settings → Google → Backup*, or export a `.vcf`.

Full checklist and commands: [`06-backup.md`](06-backup.md).

> **Checkpoint:** you have a folder on your PC containing your photos, a WhatsApp backup, exported 2FA seeds, and an SMS backup. Do not continue until this is true.

---

## Phase 1 — Confirm what you are dealing with (10 min)

You need ADB for this. If USB debugging is off, skip to Phase 2 — the fix does not require it.

**Before anything:** remove the screen lock temporarily (Settings → Security → Screen lock → **None**) and enable **Developer options → Stay awake**. The phone only stays up 1.5–3 minutes; unlocking it on every boot wastes the whole window. See [`00-requirements.md`](00-requirements.md#why-remove-the-screen-lock-and-the-catch).

1. Download **Platform-Tools** from Google and unzip to `C:\platform-tools`.
2. Open PowerShell:

```powershell
cd C:\platform-tools
.\adb.exe devices
```

3. Unlock the phone (if it still asks), tick **"Always allow from this computer"**, tap **Allow**.
4. As soon as the phone is up, run:

```powershell
.\adb.exe shell "cat /proc/uptime"
.\adb.exe shell "logcat -d -b crash" | Select-String "qcrilNrd"
```

**What you want to see:** uptime in the low hundreds of seconds, and `qcrilNrd` in the crash log.

- **Yes** → this guide applies.
- **No, different process** → read [`01-symptoms.md`](01-symptoms.md#differential-diagnosis); your fix may differ.

5. Save the evidence before you wipe:

```powershell
.\adb.exe shell logcat -d -b crash > crash-before-fix.txt
.\adb.exe pull /data/tombstones .\tombstones
.\adb.exe shell getprop > props-before-fix.txt
```

> **Checkpoint:** you have `crash-before-fix.txt` containing `libmotext_inf.so`.

---

## Phase 2 — Get internet on the phone without Wi-Fi or SIM (15 min, optional)

You may need the phone online to trigger a Google backup, download an app, or finish account verification. With the radio off and Wi-Fi dead, the normal path is blocked.

Use **gnirehtet**: it relays the phone's traffic through your PC over USB. No root.

1. Download gnirehtet (Rust build) from its GitHub releases, unzip to `C:\gnirehtet`.
2. Install the gnirehtet APK on the phone: `adb install gnirehtet.apk`
3. Start the relay on the PC, then the client:

```powershell
cd C:\gnirehtet
.\gnirehtet.exe relay          # leave this window open
# in a second window:
.\gnirehtet.exe start
```

4. Test from the phone:

```powershell
adb shell "curl -s -m 6 -o NUL -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204"
```

`204` means it works.

Caveats and the automated keeper script: [`07-internet-without-wifi-or-sim.md`](07-internet-without-wifi-or-sim.md).

> **Checkpoint:** the phone reports HTTP 204 over the USB tunnel.

---

## Phase 3 — Factory reset (10 min + first boot)

1. Unplug USB. Power the phone **off**.
2. Hold **Power + Volume Down** until the bootloader screen appears.
3. Volume Down → **Recovery mode** → Power.
4. At the "No command" robot: hold **Power**, press **Volume Up** once, release both.
5. **Wipe data/factory reset** → confirm. (Volume keys move, Power selects.)
6. **Reboot system now.**
7. **Wait.** First boot can take 15 minutes. It may show the Motorola logo for a long time, then the setup wizard. Do not power-cycle it.

> **Checkpoint:** you reach the "Welcome / Let's go" setup screen.

---

## Phase 4 — First boot: keep it clean (20 min)

1. Complete setup. Connect to Wi-Fi **or** skip it if you must.
2. **Do not restore a full device backup yet.** Especially not an "old phone clone" that restores system settings.
3. Sign in to Google. Let it restore **contacts and apps** only if you trust the source.
4. Leave the phone on the charger, screen on, for **20–30 minutes**.

Then verify:

```powershell
adb shell "cat /proc/uptime"
adb shell "logcat -d -b crash | grep -c qcrilNrd"
adb shell getprop gsm.sim.state
adb shell getprop gsm.network.type
```

Expected: uptime climbing past 1200 s, crash count **0**, SIM `LOADED`, network `LTE`/`NR`.

Or run the script:

```powershell
.\scripts\adb\verify-stability.ps1
```

> **Checkpoint:** 20+ minutes uptime, 0 crashes.

---

## Phase 5 — Reboot test (10 min)

One clean boot proves little. Reboot deliberately:

```powershell
adb reboot
```

Wait for it to come back, then leave it for **15+ minutes** and verify again.

> **Checkpoint:** two consecutive boots, 0 crashes each.

---

## Phase 6 — Restore your data, selectively

| Restore | Safe? | How |
|---|---|---|
| Photos, videos, documents | ✅ | Copy folders back over MTP |
| WhatsApp messages | ✅ | Install WhatsApp → verify number → copy `msgstore*.crypt14` into `Android/media/com.whatsapp/WhatsApp/Databases/` → restore |
| Contacts | ✅ | Google sync / `.vcf` |
| SMS, call log | ✅ | SMS Backup & Restore |
| App logins | ✅ | Reinstall from Play Store, sign in |
| **System settings / full `/data` clone** | ❌ | Can reintroduce the stale telephony state |
| **`/data/vendor/radio`, `telephony.db`** | ❌ | Directly reintroduces the trigger |
| 2FA seeds | ✅ | Import into the authenticator app |

Details: [`06-backup.md`](06-backup.md#restoring-safely).

---

## Phase 7 — Optional hardening (30 min)

Only after the phone has been stable for a day. The debloat list is **optional** and can break VoLTE/emergency calling.

```powershell
.\scripts\adb\debloat-optional.ps1 -DryRun     # see what would be disabled
.\scripts\adb\debloat-optional.ps1             # actually disable
```

Rollback:

```powershell
.\scripts\adb\debloat-optional.ps1 -Rollback
```

Read [`08-hardening.md`](08-hardening.md) before doing this.

---

## If it did not work

| Situation | Next step |
|---|---|
| Still loops after reset | [Fix 2 — LMSA with factory reset](04-fixes.md#fix-2--lmsa-rescue-with-factory-reset) |
| Loops in recovery too | Hardware → [service centre](04-fixes.md#fix-4--service-centre) |
| Stable but no mobile data | Check APN, reseat SIM, `settings get global mobile_data`; see [FAQ](09-faq.md) |
| Stable but no Wi-Fi | `adb shell cmd wifi set-wifi-enabled enabled`, reboot; if `wlan0` is missing, LMSA |
| Phone asks for the old PIN after reset | Normal on some builds; use your Google account / last PIN |
| Stuck at setup wizard "checking for updates" | Skip Wi-Fi, finish offline, connect later |
| `adb devices` shows `unauthorized` | Unlock the phone and tap Allow; if no prompt, revoke USB debugging authorizations from Developer options |

---

## Timeline of the reference recovery (for comparison)

```text
Day 1  14:49  phone healthy, 2 SIMs, LTE
       ~16:43 SIM signal lost → data lost → Wi-Fi lost → hotspot dead
                  ~1 min later: first reboot; then a loop every 1.5–3 min
       20:00  13 packages disabled + airplane mode → crashes 14 → ~2 per boot
       20:00  gnirehtet USB tether → internet from the PC
       21:00  backup loop copies DCIM / images / videos / games across reboots
       22:00  WhatsApp + Gmail backed up over the tunnel
Day 2  01:38  Android 15 OTA appears, stalls
       18:00  Software Fix / LMSA, latest full firmware → loop persists
      ~19:00  latest security-patch build (…-9-13) → loop persists
       20:00  factory reset #1 → stable
       21:00  27 min uptime, 0 crashes, LTE, all packages re-enabled
      ~22:00  factory reset #2 to confirm → still stable
Day 3         reboot test, 18+ min, 0 crashes → closed
```

The shape is the lesson: **three images failed, one wipe worked.**
