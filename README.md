> [!IMPORTANT]
> **This repository was written by AI.** The diagnosis, scripts and documentation were produced by the repository owner working with an **AI coding agent** (DeepSeek V4.1 Flash via OpenCode), then checked against the captured logs.
>
> **Want to debug your own phone with it?** Give your AI assistant **this whole repository and its full documentation** — `README.md`, `docs/00`–`docs/12`, `evidence/`, and `scripts/` — and tell it to follow the guide step by step. Then **always verify** what it says against `getprop` and `logcat` before you run anything. Treat AI output as a strong starting point, never as authority.

# Moto G45 5G Bootloop — Complete Fix & Recovery Guide

**English** · [Bahasa Indonesia](README.id.md)

| Device | Motorola Moto G45 5G · `XT2363-9` · codename **`fogos`** · Snapdragon 6s Gen 3 (`SM6375`) |
|--------|--------------------------------------------------------------------------------------------|
| Symptom | Phone reboots every **~2 minutes**, forever — survived 3 firmware flashes & 2 factory resets |
| Root cause | **Corrupt modem NV in `modemst1` / `modemst2`** — modem asserts on every boot, `qcrilNrd` crash is just a symptom |
| **The fix** | **Erase `modemst1` + `modemst2`** after unlocking bootloader → modem rebuilds clean NV from golden `fsg` partition |
| Status | ✅ Stable · Zero modem crashes · LTE data & voice working · IMEI intact · 2+ hours verified |

> **Correction (2026-11-08).** Earlier versions said a factory reset was the fix. **That was wrong** — the reset only held for ~3 hours. The real fix is in [`docs/12-confirmed-fix-nv-repair.md`](docs/12-confirmed-fix-nv-repair.md).

---

## 📋 Table of Contents

1. [Quick Start — If Your Phone Is Bootlooping Right Now](#quick-start--if-your-phone-is-bootlooping-right-now)
2. [Before You Start — What You Need](#before-you-start--what-you-need)
3. [What Actually Happened — The Story](#what-actually-happened--the-story)
4. [The Fix — Step by Step](#the-fix--step-by-step)
5. [How We Verified It](#how-we-verified-it)
6. [FAQ](#faq)
7. [Full Documentation](#full-documentation)
8. [Debugging with AI + ADB](#debugging-with-ai--adb)
9. [What We Got Wrong (So You Don't Have To)](#what-we-got-wrong-so-you-dont-have-to)
10. [Disclaimer & Legal](#disclaimer--legal)

---

## 🚨 Quick Start — If Your Phone Is Bootlooping Right Now

| Step | Action | Why |
|------|--------|-----|
| 1 | **Back up first** → [`docs/06-backup.md`](docs/06-backup.md) | Unlocking wipes `/data` — WhatsApp keys, 2FA seeds, everything |
| 2 | Confirm it's *this* bug → [`docs/01-symptoms.md`](docs/01-symptoms.md) | 2-min reboot + `qcrilNrd` in crash buffer = the fingerprint |
| 3 | Get internet without Wi-Fi/SIM → [`docs/07-internet-without-wifi-or-sim.md`](docs/07-internet-without-wifi-or-sim.md) | `gnirehtet` reverse-tethers via USB — no root, no Wi-Fi, no SIM needed |
| 4 | **Record IMEI** — dial `*#06#` and write both numbers down | The repair erases the NV store holding IMEI |
| 5 | **Unlock bootloader** → [`docs/12`](docs/12-confirmed-fix-nv-repair.md#unlocking-the-bootloader) | `fastboot erase` is refused while locked |
| 6 | **Erase modem NV** → `fastboot erase modemst1` then `fastboot erase modemst2` | **This is the fix.** Modem rebuilds NV from golden `fsg` |
| 7 | Verify → `crash_count` = 0, baseband present, IMEI unchanged | One clean boot isn't proof — watch 30 min, then reboot once |

> ⏱️ **30-second version:** [One-screen explanation](docs/03-root-cause.md#the-short-version)

---

## 🛠️ Before You Start — What You Need

This isn't a phone-only fix. You need a **PC** and a **cable**, and most failures happen *before* the first command.

| You must have | Why |
|---------------|-----|
| **Windows 10/11 PC or laptop** (admin rights) | Motorola's LMSA/Software Fix is Windows-only; all scripts here are PowerShell |
| **USB *data* cable** — not charge-only | Charge-only cables can't carry ADB. This is the #1 cause of "`adb devices` shows nothing" |
| **ADB installed** (Android SDK Platform-Tools) | Every diagnostic and fix uses it |
| **USB debugging + "Always allow" + screen lock removed** | Boot window is only 1.5–3 min; unlocking the phone eats it. Set lock to **None** temporarily |
| **A direct USB port** (no hub/dock) | Hubs drop connections mid-flash |
| **Internet on the PC** + **30–60 GB free disk** | Platform-Tools, gnirehtet, 2–5 GB firmware, backups |
| **Phone charged > 50 %** | First boot after NV erase can take several minutes |
| **Google account password** | Factory Reset Protection still applies even with no screen lock |
| **Screen lock PIN known** | You need it to remove the lock, and to restore it afterwards |
| **2FA seeds exported, backups done** | A wipe deletes them permanently |

**Full checklist, drivers, cable troubleshooting & "do I have everything?" list:** [`docs/00-requirements.md`](docs/00-requirements.md)

> You do **not** need root, a custom ROM, or a paid tool. You **do** need an unlockable bootloader — `fastboot erase modemst1/modemst2` is refused while locked.

---

## 📖 What Actually Happened — The Story

Your phone has two computers inside:
- **The AP** (Application Processor) — runs Android, your apps, the UI
- **The Modem/Baseband** — handles radio, SIM, calls, mobile data

They talk over a channel called **oemhook**, brokered by Qualcomm's RIL daemon `qcrilNrd`.

On this device, Motorola ships a vendor library, `libmotext_inf.so`, that handles oemhook traffic. It has a bug:

```
Process:  /vendor/bin/hw/qcrilNrd  (uid 1001)
Signal:   SIGSEGV, SEGV_MAPERR, fault addr 0xffffffffffffff02
#00  libqcrilNr.so    qcril_qmi_oem_free_and_convert_ril_token_to_oem_token
#01  libqcrilNr.so    qcril_qmi_oemhook_agent_send
#02  libqcrilNr.so    mot_qcril_qmi_oemhook_agent_send
#03  libmotext_inf.so communicationThread      <-- Motorola proprietary
#04  libc.so          __pthread_start
```

A token referring to a modem connection that no longer exists (`0xffffffffffffff02` = `-254`, an error code used as a pointer) gets dereferenced. `qcrilNrd` crashes. `system_server` blocks on a Binder call that never returns. After ~60 seconds the **watchdog** kills the system and the phone reboots. Every 2 minutes. Forever.

**The crash is a symptom.** Underneath, the modem's own NV database (`modemst1`/`modemst2`) was corrupt. The modem asserted on every boot, its QMI services vanished, and the library dereferenced a token for a connection that was already gone.

That's why:
- ❌ **Android 15 OTA didn't help** — replaces AP images, never touches modem NV
- ❌ **LMSA flash didn't help** — same reason, rewrites wrong partitions
- ❌ **Disabling 13 packages only reduced crash rate** — apps are *senders* of oemhook traffic, not the cause
- ❌ **Factory reset only delayed it** — re-provisions modem stack, masks corrupt NV for a few hours, never touches `modemst1/2`
- ✅ **Erasing `modemst1` + `modemst2` fixed it** — modem rebuilt clean NV from golden `fsg` partition

**Full analysis:** [`docs/03-root-cause.md`](docs/03-root-cause.md)

---

## ⚡ The Fix — Step by Step

### Prerequisites (Read These First ⚠️)
- **Unlockable bootloader** — Motorola only unlocks retail units (XT2363-9 is retail). `fastboot erase` is refused while locked.
- **Record IMEI first** — dial `*#06#` and write both numbers down. The erase wipes the NV store holding IMEI.
- **Backup before unlock** — unlocking wipes `/data` (WhatsApp keys, 2FA seeds, everything). See [`backup guide`](docs/06-backup.md).
- **Do NOT relock** — relocking a modified boot chain bricks the device.

### The Commands

```bash
# 1. Record IMEI first (dial *#06#)
fastboot erase modemst1
# OKAY [  0.139s]

fastboot erase modemst2
# OKAY [  0.005s]

fastboot reboot

# 2. Verify after boot
adb shell cat /sys/bus/msm_subsys/devices/subsys2/crash_count
# 0

adb shell getprop gsm.version.baseband
# M6375_HI434_03.562.01.121R

# 3. Confirm IMEI unchanged (*#06#)
```

### Verification Checklist
- ✅ Modem `crash_count` = 0 (all 6 subsystems)
- ✅ Baseband present (`M6375_HI434_03.562.01.121R`)
- ✅ SIM `LOADED`, LTE `IN_SERVICE`, data & voice working
- ✅ IMEI intact (both match pre-repair)
- ✅ Uptime 2+ hours, no reboots, no framework restarts
- ✅ Data restored (9.4 GB staged push, 3,452 files verified)

---

## 🔬 How We Verified It

Not just "it booted once" — continuous monitoring with automated checks:

| Method | What We Did |
|--------|-------------|
| **4-Hour Stability Watch** | Custom PowerShell monitor (`thorough-watch.ps1`) polling every 60s: modem crash counter, uptime, baseband, SIM state, `qcrilNrd` PIDs, battery, temp. Zero anomalies across 2+ hours. |
| **Staged Restore with Gates** | 9.4 GB backup pushed in 5 stages. After each: `crash_count` = 0, uptime increases, baseband persists. All 5 stages passed — 3,452 files, 100% count match. |
| **Deep Subsystem Scan** | All 6 Qualcomm subsystems checked (`subsys0` ADSP → `subsys5` Venus): all `crash_count = 0`. No `ssrdump` directory (no modem assertion dumps). One unrelated thermal HAL tombstone at boot, never recurred. |

---

## ❓ FAQ

<details>
<summary><strong>Will this fix survive OTA updates?</strong></summary>
Yes. OTAs rewrite AP partitions (`boot`, `dtbo`, `vendor_boot`, `super`), not `modemst1/2`. The rebuilt NV persists.
</details>

<details>
<summary><strong>Can I do this without unlocking the bootloader?</strong></summary>
No. `fastboot erase modemst1/modemst2` is explicitly refused while locked. Motorola's unlock is required (retail units only).
</details>

<details>
<summary><strong>Is my IMEI at risk?</strong></summary>
The erase wipes the NV store holding IMEI, but the modem rewrites it from the golden `fsg` partition on first boot. **Record it first** (`*#06#`) and verify after. Ours matched exactly.
</details>

<details>
<summary><strong>Does a custom ROM (LineageOS, Pixel Experience, etc.) fix this?</strong></summary>
No. Custom ROMs only replace AP partitions. They never touch `modemst1/2`. Modem firmware and its NV are separate.
</details>

<details>
<summary><strong>Factory reset appeared to work for 3 hours — why?</strong></summary>
Factory reset re-provisions the modem stack (rewrites `/data/vendor/radio`, clears telephony DB), temporarily masking corrupt NV. But it never touches `modemst1/2`, so the corruption persists and the loop returns.
</details>

<details>
<summary><strong>What is the `qcrilNrd` crash really?</strong></summary>
A **symptom**, not the cause. Modem's QMI services vanish due to corrupt NV. Motorola's `libmotext_inf.so` dereferences a token for a dead connection (`-254` used as pointer) → `SIGSEGV` in `qcrilNrd` → `system_server` blocks → watchdog reboot.
</details>

<details>
<summary><strong>Can I relock the bootloader after the fix?</strong></summary>
**No.** Relocking with a modified boot chain (erased `modemst1/2` = modified vendor state) will hard-brick the device. Leave it unlocked.
</details>

<details>
<summary><strong>Is this fix specific to build V1UGS35H.75-14-9-3-1-4?</strong></summary>
The root cause (corrupt `modemst1/2`) and fix (erase both) are build-agnostic for any `fogos` device. Baseband version may differ; verify `gsm.version.baseband` is present after reboot.
</details>

**More FAQ:** [`docs/09-faq.md`](docs/09-faq.md)

---

## 📚 Full Documentation

| Section | What You'll Find |
|---------|------------------|
| **Start Here** | [`Requirements & Pre-flight Checklist`](docs/00-requirements.md) — PC, cable, ADB, accounts, 2FA seeds, cable test |
| **Diagnose** | [`Symptoms`](docs/01-symptoms.md) · [`Evidence Collection`](docs/02-diagnosis.md) · [`Root Cause Analysis`](docs/03-root-cause.md) |
| **Fix & Verify** | [`Confirmed Fix: NV Repair`](docs/12-confirmed-fix-nv-repair.md) · [`Step-by-Step Tutorial`](docs/05-tutorial.md) · [`Restore Verification`](docs/13-restore-verification.md) |
| **AI-Assisted Debugging** | [`How we used AI + ADB`](docs/11-ai-assisted-debugging.md) — prompts, mistakes, verification rules. **Give your AI this whole repo to debug your phone.** |
| **Scripts & Evidence** | [`ADB Scripts`](scripts/adb/) (collect, verify, debloat) · [`Sanitised Logs`](evidence/) (crash signature, timeline, device snapshot) |
| **Safety & Legal** | [`Privacy/Redaction Checklist`](PRIVACY.md) · [`License`](LICENSE) (MIT / CC BY 4.0) · [`Disclaimer`](#disclaimer--legal) |

---

## 🤖 Debugging with AI + ADB

This repo was diagnosed with an AI assistant in the loop. We recommend the same approach — with guardrails. **The AI cannot see your phone.** It cannot run `adb`, flash firmware, or verify a package name. You supply the evidence; you verify the result.

### What to Give Your AI

Capture these while the phone is up, then attach the files:

```bash
adb devices
adb shell getprop > props.txt
adb shell 'logcat -d -b crash' > crash.txt
adb shell 'dumpsys telephony.registry' > telephony.txt
adb shell 'dumpsys connectivity' > connectivity.txt
adb shell 'ls -l /data/tombstones' > tombstones.txt
```

Or run [`scripts/adb/collect-evidence.ps1`](scripts/adb/collect-evidence.ps1) (Windows) or [`collect-evidence.sh`](scripts/adb/collect-evidence.sh) (Linux/macOS) once and let it grab everything before the reboot.

> **💡 Pro tip:** Tombstones persist across reboots. If the loop is too fast for live `logcat`, pull `/data/tombstones` instead. It's the single most useful trick in this guide.

### Prompt Template

```text
You are helping me debug an Android device over ADB. Do not guess.

Device: Motorola Moto G45 5G (XT2363-9, codename fogos, SM6375)
Build: <ro.build.fingerprint>
Baseband: <gsm.version.baseband>
Symptom: <one sentence, with timings>
Uptime before reboot: <seconds>

Attached: crash.txt, props.txt, telephony.txt, connectivity.txt

Rules:
1. Start with read-only commands only. No erase, no flash, no uninstall.
2. For every claim, quote the exact line from the files that supports it.
3. If the evidence is insufficient, say what to capture next.
4. Give me one hypothesis at a time, with a prediction I can test.
5. Tell me what would prove you wrong.
```

### Rules That Keep It Honest

1. **Read-only first.** `getprop`, `logcat`, `dumpsys` — no writes until the failure is understood.
2. **One change per test.** Change three things and you learn nothing.
3. **Demand citations.** If it can't quote a log line, it's guessing.
4. **Ask "what would prove you wrong?"** If the answer is "nothing", discard it.
5. **Sanitise before pasting.** Serials, IMEIs, phone numbers, SSIDs, account names — see [`PRIVACY.md`](PRIVACY.md).
6. **Verify with time, not a reboot.** 10+ min uptime and `qcrilNrd` crashes = 0.

---

## 🎓 What We Got Wrong (So You Don't Have To)

The full list with lessons is in [`docs/11-ai-assisted-debugging.md`](docs/11-ai-assisted-debugging.md). The short version:

| Mistake | Lesson |
|---------|--------|
| **Picked wrong root cause** — thought stale `/data` was the trigger because factory reset *appeared* to work for 3 hours | A "fix" that holds for hours isn't a fix. Always test across a reboot and across days. |
| **Told people not to erase `modemst`** — that warning was wrong; it's the actual fix (after recording IMEI) | Don't let fear of data loss stop you from the real solution — manage the risk instead. |
| **Flashed firmware 3 times** — can't fix corrupt modem NV | Flashing AP partitions never touches modem NV. Different layer entirely. |
| **Disabled packages as "fix"** — crash rate dropped but cause remained | Apps are *senders* of oemhook traffic, not the trigger. |
| **Raced `logcat` in 2-min window** — kept missing the crash | Persistent tombstones win. Pull `/data/tombstones` instead. |
| **Burned boot window on lock screen** — PIN/pattern keeps `/data` encrypted until unlock | Set lock to **None** temporarily. Enable "Always allow from this computer" for ADB. |
| **Trusted anecdotal success rates** — "~60%", "~90%" from forums | If it's not measured, call it anecdotal — or delete it. |
| **Thought SIM/data/Wi-Fi dying together = hardware failure** | All depend on `system_server` + telephony; one `qcrilNrd` crash takes everything down. |
| **Backed up too late** — WhatsApp keys & 2FA seeds lost forever | **Backup first.** [`docs/06-backup.md`](docs/06-backup.md) tells you exactly what and how. |

---

## ⚖️ Disclaimer & Legal

**Flashing, wiping, and `fastboot erase` can brick your device or void warranty. This guide is provided as-is, with no warranty. You are responsible for your own device and data. Not affiliated with Motorola, Qualcomm, or Google.**

- Factory reset and bootloader unlock are **irreversible** for on-device data. **Back up first.**
- Disabling packages in [`scripts/adb/debloat-optional.txt`](scripts/adb/debloat-optional.txt) can break VoLTE, emergency calling, or OTA. It is **optional and reversible**.
- If the phone is under warranty and this doesn't help, use the service centre — don't open the device.

**License:** Code = MIT, Prose = CC BY 4.0. See [`LICENSE`](LICENSE).

---

## 🤝 Contributing

Corrections, additional `fogos` builds, or reports of the same crash signature are welcome. Please open an issue with your **build fingerprint**, **baseband version**, and a **`logcat -b crash` excerpt** — and scrub your serial/IMEI first. See [`PRIVACY.md`](PRIVACY.md) for the redaction checklist.

---

## 🤖 AI Co-authorship

This repository was written by the owner together with an **AI coding agent** (DeepSeek V4.1 Flash via OpenCode).

- **Human:** owns the device, ran every command, made every destructive decision, verified the outcome.
- **AI:** read the logs, proposed hypotheses, wrote the scripts and documentation, and was wrong more than once.

We disclose this because AI-assisted debugging is useful and should be normalised — but also because **AI output needs verification**. The evidence is published so you can check the reasoning instead of trusting it. See [`docs/11-ai-assisted-debugging.md`](docs/11-ai-assisted-debugging.md) for the workflow, prompts, and mistakes.

> If you use AI on your own device: verify every claim against `getprop`/`logcat`, sanitise logs before sharing, and never let it talk you into `erase`, `flash`, or `uninstall` without a stated reason.

---

## 🔗 Quick Links

- **📖 Full Repository:** [github.com/bnbcast/motorola-g45-bootlooping-keep-restarting-fix](https://github.com/bnbcast/motorola-g45-bootlooping-keep-restarting-fix)
- **🌐 Live Site:** [bnbcast.github.io/motorola-g45-bootlooping-keep-restarting-fix](https://bnbcast.github.io/motorola-g45-bootlooping-keep-restarting-fix/)
- **🇮🇩 Bahasa Indonesia:** [README.id.md](README.id.md)
- **🐛 Report Issue:** [GitHub Issues](https://github.com/bnbcast/motorola-g45-bootlooping-keep-restarting-fix/issues)

---

*© 2026 bnbcast. Built with ❤️ for the `fogos` community.*