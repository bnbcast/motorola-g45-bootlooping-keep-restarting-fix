# 01 — Symptoms: is this your bug?

A bootloop has many causes. This document separates **this** failure (modem/oemhook) from the usual suspects, using evidence you can collect yourself.

---

## The fingerprint

| Signal | This bug | What it looks like |
|---|---|---|
| Reboot interval | **~1.5–3 minutes**, very consistent | Watch the clock: boot → usable → freeze → reboot |
| Boot reason | `watchdog`, occasionally `kernel_panic` | `adb shell getprop ro.boot.bootreason` |
| Crash process | **`/vendor/bin/hw/qcrilNrd`** (uid 1001) | `adb shell logcat -d -b crash` |
| Crash count | ~14 per boot, roughly every 8 s | `logcat -d -b crash \| grep -c qcrilNrd` |
| Fault address | `0xffffffffffffff02` | In the tombstone header |
| Wi-Fi | HAL never initialises, no `wlan0` | `WifiSelfRecovery: WifiNative Failure` |
| SIM state | `NOT_READY,NOT_READY` | `getprop gsm.sim.state` |
| Default network | `none` | `dumpsys connectivity \| grep "Active default network"` |
| Firmware flashes | **Still loops after 3 different builds** | Rules out a bad system image |
| Recovery mode | **Stable** (no Android framework running) | Confirms the kernel/hardware are fine |

The last two rows matter most. **If the phone is stable in recovery but loops in normal boot, it is a userspace/framework problem — not a dead battery, not a broken PMIC.** And if three clean firmware images all loop identically, the problem is not the image.

---

## The 60 seconds before the loop (the most useful clue)

This is the exact sequence reported by the owner, and it is worth reading carefully because it tells you **which subsystem failed first**:

```text
1. SIM signal disappears            ← modem / RIL dies first
2. Mobile data stops working        ← consequence of 1
3. Wi-Fi disappears                 ← framework starting to fail
4. Hotspot cannot be enabled        ← same
5. ~1 minute later: phone reboots   ← watchdog gives up
6. Reboot loop, every ~1.5–3 min    ← forever
```

The order matters. **The modem went first, then the network stack, then the framework, then the watchdog rebooted.** If the battery or storage had died, you would expect random reboots first and radio problems second. Here the radio was the *first* casualty, which points at `qcrilNrd`/modem state, not at hardware.

It also explains the confusing "everything is broken" feeling: SIM, data, Wi-Fi and hotspot all failed within a minute of each other, because they all depend on the same `system_server` + telephony stack that `qcrilNrd` was wedging.

## Timeline as observed on the reference device

```text
2026-11-05 14:49  Both SIMs registered (XL Axiata slot 0, AXIS slot 1), LTE, data OK
2026-11-05 ~16:43 SIM signal lost → mobile data lost → Wi-Fi lost → hotspot dead
                  ~1 min later: first reboot. Then a loop every ~1.5–3 min
                  qcrilNrd crashes ~14x per boot, bootreason watchdog
2026-11-05 20:00  13 oemhook packages disabled + airplane mode → crashes 14 → ~2 per boot
                  (still looping; no Wi-Fi, no SIM, no data)
2026-11-05 20:00  gnirehtet USB reverse tether → internet from the PC
2026-11-05 21:00  Backup scripts fight the reboot interval: DCIM, images, videos, games
                  folders copied piece by piece across reboots
2026-11-05 22:00  WhatsApp + Gmail backed up over the gnirehtet tunnel
2026-11-06 01:38  Android 15 OTA appears (1.97 GB), download stalls at 37 %
2026-11-06 18:00  Motorola/Lenovo "Software Fix" (LMSA) with latest firmware
                  → Android 15 installed, loop PERSISTS
2026-11-06 ~19:00 Latest security-patch build (…-9-13) flashed
                  → loop PERSISTS, identical signature
2026-11-06 20:00  Factory reset #1 via Recovery → stable
2026-11-06 21:00  27 min uptime, 0 crashes, native LTE, all packages re-enabled
2026-11-06 ~22:00 Factory reset #2, to confirm it was not luck → still stable
2026-11-07        Reboot test: 18+ min, 0 crashes. Closed.
```

Note the shape of it: **the loop did not start after an update.** It started while the phone was simply sitting there with two SIMs registered, and it survived **three different firmware flashes** (Android 15 OTA path, latest full firmware via Software Fix, latest security-patch build). That combination — survives flashing, dies on wipe — is the signature of **state**, not of a bad image.

---

## Collect the evidence in 60 seconds

You have a ~2-minute window per boot. Run these as soon as `adb devices` shows the phone:

```bash
adb wait-for-device

# 1. How long has this boot lasted, and why did the last one end?
adb shell 'cat /proc/uptime'
adb shell getprop ro.boot.bootreason

# 2. The money shot: the crash buffer
adb shell logcat -d -b crash > crash.txt
grep -c qcrilNrd crash.txt

# 3. Confirm the fingerprint
adb shell 'logcat -d -b crash | grep -A12 "qcrilNrd"'

# 4. Radio and network state
adb shell getprop gsm.sim.state
adb shell getprop gsm.network.type
adb shell 'dumpsys connectivity | grep -m1 "Active default network"'
```

Ready-made: [`../scripts/adb/collect-evidence.ps1`](../scripts/adb/collect-evidence.ps1) (Windows) or [`collect-evidence.sh`](../scripts/adb/collect-evidence.sh) (Linux/macOS). It saves everything to a timestamped folder.

If ADB is not enabled, see [`02-diagnosis.md`](02-diagnosis.md#if-usb-debugging-is-not-enabled).

---

## Differential diagnosis

Rule these out before you wipe anything.

### Bootloop after installing a Magisk module / custom ROM
- Symptom: loops immediately after a flash, not after hours of uptime.
- Fix: boot to recovery, remove the module, or fastboot the stock `boot.img`.
- **Not this bug** — the reference device was 100 % stock, unrooted, bootloader locked.

### Battery / charging / PMIC
- Symptom: reboots under load, dies at 20–30 %, gets hot, sometimes boots fine on charger.
- Check: `adb shell dumpsys battery`, watch voltage while booting.
- **Not this bug** — recovery would also be unstable, and reboots would be random rather than a metronome.

### Storage (eMMC/UFS) failure
- Symptom: `I/O error`, `mmc0: card stuck`, fsck failures, apps crashing at random, `system_server` watchdog *without* a `qcrilNrd` tombstone.
- Check: `adb shell dmesg | grep -i -E "mmc|ufs|I/O error"`.
- **Not this bug** — here the watchdog is a *downstream* consequence of the RIL crash, and the tombstone names the culprit.

### Bad OTA / failed update
- Symptom: loops right after an OTA, recovery says "couldn't mount /data" or slot errors.
- Check: `adb shell getprop ro.boot.slot_suffix`, recovery logs.
- **Not this bug** — this device looped on **both** Android 14 and Android 15 with an identical signature.

### Corrupt `/data` from a single bad app
- Symptom: safe mode is stable, normal boot loops.
- **Related, but different**: safe mode was *not* stable here. Still, a factory reset fixes both.

### "com.android.phone isn't responding" dialog on every boot
Seen during this incident. It is a *symptom*, not the cause: `telephony` and `qcrilNrd` are wedged, so the dialer/phone process ANRs. Do not chase the dialog — chase `qcrilNrd`.

---

## Decision tree

```text
Phone reboots every few minutes
│
├─ Stable in Recovery? ── no ──> hardware / bootloader issue → service centre
│
└─ yes
   │
   ├─ logcat -b crash shows qcrilNrd + libmotext_inf.so ?
   │     │
   │     ├─ yes ──> THIS BUG → docs/04-fixes.md
   │     │
   │     └─ no ───> different crash. Read the tombstone, search the process name.
   │
   └─ No ADB, no crash buffer?
         └─ Still do the backup (06) then try the factory reset (04). It is the
            lowest-risk fix that resolves most telephony-related loops.
```

---

## What "fixed" looks like

Do not declare victory after one clean boot. The reference device was only considered fixed after:

- **27 minutes** of uptime immediately after the reset
- a **second reboot** with **18+ minutes** uptime
- **0** `qcrilNrd` entries in `logcat -b crash`
- native LTE up (`Active default network: 102`), HTTP 204 / HTTPS 200
- **all 13 previously disabled packages re-enabled** — proving the packages were never the cause

Use [`../scripts/adb/verify-stability.ps1`](../scripts/adb/verify-stability.ps1) to check the same criteria.
