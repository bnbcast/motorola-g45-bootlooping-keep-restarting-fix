> [!IMPORTANT]
> **This repository was written by AI.** The diagnosis, scripts and documentation were produced by the repository owner working with an **AI coding agent** (DeepSeek V4.1 Flash via OpenCode), then checked against the captured logs.
>
> **Want to debug your own phone with it?** Give your AI assistant **this whole repository and its full documentation** — `README.md`, `docs/00`–`docs/12`, `evidence/`, and `scripts/` — and tell it to follow the guide step by step. Then **always verify** what it says against `getprop` and `logcat` before you run anything. Treat AI output as a strong starting point, never as authority.

# Moto G45 5G bootloop full diagnosis, fix and recovery guide

**English** · [Bahasa Indonesia](README.id.md)

**Device:** Motorola Moto G45 5G · `XT2363-9` · codename **`fogos`** · Snapdragon 6s Gen 3 (`SM6375`)
**Symptom:** phone reboots every **~2 minutes**, forever, and it survived three different firmware flashes and two factory resets
**Root cause:** **corrupt modem NV in `modemst1` / `modemst2`** — the modem asserts on every boot, and the `qcrilNrd` crash is a symptom of that
**What actually fixed it:** **erasing `modemst1` + `modemst2`** after unlocking the bootloader, so the modem rebuilt NV from `fsg`
**Status:** stable, zero modem crashes, LTE data and voice working, IMEI intact — verified on the first boot after the repair, then monitored continuously

> **Correction (2026-11-08).** Earlier versions of this repo said a factory reset was the fix
> and that stale `/data` state was the trigger. That was **wrong** — the reset held for about
> three hours and then the loop returned. The real fix is
> [`docs/12-confirmed-fix-nv-repair.md`](docs/12-confirmed-fix-nv-repair.md).

This repository is the sanitised, reproducible write-up of one device's recovery: what broke, why, what we tried, what worked, what did **not**, and how to protect your data before you wipe.

> **Not affiliated with Motorola, Qualcomm or Google.** Everything here is from a single device plus general Android/Qualcomm knowledge. Read [DISCLAIMER](#disclaimer) before running anything.

---

## Before you start — what you need

This is not a phone-only fix. You need a **PC** and a **cable**, and most failures happen before the first command.

| You must have | Why |
|---|---|
| **Windows 10/11 PC or laptop** (admin rights) | Motorola's LMSA/Software Fix is Windows-only; all scripts here are PowerShell |
| **USB *data* cable** — not charge-only | Charge-only cables cannot carry ADB. This is the #1 cause of "`adb devices` shows nothing" |
| **ADB installed** (Android SDK Platform-Tools) | Every diagnostic and fix uses it |
| **USB debugging + "Always allow" + screen lock removed** | The boot window is only 1.5–3 minutes; unlocking the phone eats it. Set lock to **None** temporarily |
| **A direct USB port** (no hub/dock) | Hubs drop connections mid-flash |
| **Internet on the PC** + **30–60 GB free disk** | Platform-Tools, gnirehtet, 2–5 GB firmware, backups |
| **Phone charged > 50 %** | First boot after the NV erase can take several minutes |
| **Google account password** | Factory Reset Protection still applies even with no screen lock |
| **Screen lock PIN known** | You need it to remove the lock, and to restore it afterwards |
| **2FA seeds exported, backups done** | A wipe deletes them permanently |

**Full checklist, drivers, cable troubleshooting and the "do I have everything?" list:** [`docs/00-requirements.md`](docs/00-requirements.md)

> You do **not** need root, a custom ROM, or a paid tool. You **do** need an unlockable bootloader — `fastboot erase modemst1/modemst2` is refused while it is locked.

---

## TL;DR — if your phone is bootlooping right now

| # | Do this | Why |
|---|---|---|
| 1 | **Back up first** → [`docs/06-backup.md`](docs/06-backup.md) | Unlocking the bootloader wipes `/data`, including the WhatsApp decryption key and any 2FA authenticator seeds |
| 2 | Confirm it's *this* bug → [`docs/01-symptoms.md`](docs/01-symptoms.md) | A 2-minute reboot loop with `qcrilNrd` in the crash buffer is the fingerprint |
| 3 | Get internet without Wi-Fi/SIM → [`docs/07-internet-without-wifi-or-sim.md`](docs/07-internet-without-wifi-or-sim.md) | `gnirehtet` reverse-tethers the phone through USB — no root, no Wi-Fi, no SIM |
| 4 | **Record your IMEI** — dial `*#06#` and write both numbers down | The repair erases the NV store that holds the IMEI |
| 5 | **Unlock the bootloader** → [`docs/12`](docs/12-confirmed-fix-nv-repair.md#unlocking-the-bootloader) | `erase modemst1/2` is refused while the bootloader is locked |
| 6 | **Erase the modem NV** → `fastboot erase modemst1` then `fastboot erase modemst2` | **This is the fix.** The modem rebuilds NV from the golden `fsg` partition |
| 7 | Verify → `crash_count` stays `0`, baseband present, IMEI unchanged | A single clean boot is not proof — watch it 30 min, then reboot once |

If you have 30 seconds, read the [one-screen explanation](docs/03-root-cause.md#the-short-version).

---

## Final state (verified)

![Android 15, build V1UGS35H.75-14-9-3-1-4, security patch 1 September 2026](assets/android15-latest-build.png)

After the repair: **Android 15**, build `V1UGS35H.75-14-9-3-1-4`, security patch **1 September 2026**, baseband `M6375_HI434_03.562.01.121R`, `IN_SERVICE` on LTE, mobile data and voice working, **zero modem crashes**.

The phone went through **three separate firmware flashes** and **two factory resets** before the real fix. None of them touched `modemst1`/`modemst2`. Erasing those two partitions — which needs an unlocked bootloader — is what restored it.

---

## What is actually going on

The phone has two computers: the **AP** (Android, your apps) and the **modem/baseband** (radio, SIM, calls, data). They talk over a channel called **oemhook**, brokered by Qualcomm's RIL daemon `qcrilNrd`.

On this device, Motorola ships a vendor library, `libmotext_inf.so`, that handles oemhook traffic. It contains a bug:

```
Process:  /vendor/bin/hw/qcrilNrd  (uid 1001)
Signal:   SIGSEGV, SEGV_MAPERR, fault addr 0xffffffffffffff02
#00  libqcrilNr.so    qcril_qmi_oem_free_and_convert_ril_token_to_oem_token
#01  libqcrilNr.so    qcril_qmi_oemhook_agent_send
#02  libqcrilNr.so    mot_qcril_qmi_oemhook_agent_send
#03  libmotext_inf.so communicationThread      <-- Motorola proprietary
#04  libc.so          __pthread_start
```

A token that referred to a modem connection that no longer exists (`0xffffffffffffff02` = `-254`, an error code used as a pointer) gets dereferenced. `qcrilNrd` dies. `system_server` blocks on a Binder call that will never return. After ~60 s the **watchdog** kills the system and the phone reboots. Repeat every 2 minutes.

The crash is a **symptom**. Underneath it, the modem's own NV database (`modemst1`/`modemst2`) was corrupt, so the modem asserted on every boot and its QMI services vanished. The library then dereferenced a token for a connection that was already gone.

That is why:

- **The Android 15 OTA did not help** — it replaces images, never the modem's NV data.
- **The LMSA flash did not help** — same reason. It rewrites partitions the modem does not read its NV from.
- **Disabling 13 packages only reduced the crash rate** — apps are a *sender* of oemhook traffic, not the cause.
- **A factory reset only delayed it** — it re-provisions the modem stack, which masks corrupt NV for a few hours, but never touches `modemst1/2`.
- **Erasing `modemst1` + `modemst2` fixed it** — the modem rebuilt a clean NV database from the golden `fsg` partition.

Full analysis, including why a factory reset *appeared* to work and why it did not: **[`docs/03-root-cause.md`](docs/03-root-cause.md)**.

---

## Debug it with AI + ADB

This repository was diagnosed with an AI assistant in the loop, and we recommend the same approach — with guardrails. **The AI cannot see your phone.** It cannot run `adb`, flash firmware, or verify a package name. You supply the evidence; you verify the result.

### What to give it

Capture these while the phone is up, then attach the files:

```bash
adb devices
adb shell getprop > props.txt
adb shell 'logcat -d -b crash' > crash.txt
adb shell 'dumpsys telephony.registry' > telephony.txt
adb shell 'dumpsys connectivity' > connectivity.txt
adb shell 'ls -l /data/tombstones' > tombstones.txt
```

Or run [`scripts/adb/collect-evidence`](scripts/adb/) once and let it grab everything before the reboot.

> **Tombstones persist across reboots.** If the loop is too fast to catch `logcat` live, pull `/data/tombstones` instead. It is the single most useful trick in this guide.

### Prompt template

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

### Rules that keep it honest

1. **Read-only first.** `getprop`, `logcat`, `dumpsys` — no writes until the failure is understood.
2. **One change per test.** Change three things and you learn nothing.
3. **Demand citations.** If it cannot quote a log line, it is guessing.
4. **Ask "what would prove you wrong?"** If the answer is "nothing", discard it.
5. **Sanitise before pasting.** Serials, IMEIs, phone numbers, SSIDs, account names — see [`PRIVACY.md`](PRIVACY.md).
6. **Verify with time, not a reboot.** 10+ minutes uptime and `qcrilNrd` crashes = 0.

### What we got wrong

The full list, with the lesson for each, is in [`docs/11-ai-assisted-debugging.md`](docs/11-ai-assisted-debugging.md). The short version:

- **We picked the wrong root cause.** Stale `/data` state looked right because a factory reset appeared to work — for three hours. The reset was masking corrupt modem NV, not fixing it.
- **We told people not to erase `modemst`.** That warning was wrong. It is the actual fix, once you record the IMEI first.
- Flashing firmware cannot fix corrupt modem NV — three flashes failed.
- Disabling packages reduced the crash rate but did not remove the cause — apps are senders, not the trigger.
- Racing `logcat` in a 2-minute window loses; persistent tombstones win.
- Burning the boot window on the lock screen wastes the whole window.
- A "fix" that holds for a few hours is not a fix. Always test across a reboot and across days.

---

## Repository map

```
README.md                     you are here (English)
README.id.md                  Bahasa Indonesia
docs/
  00-requirements.md          PC, cable, ADB, drivers, accounts, pre-flight checklist
  01-symptoms.md              recognise this bootloop vs. other causes
  02-diagnosis.md             collect evidence with ADB; read tombstones
  03-root-cause.md            the crash mechanics, and the wrong theory (kept for the record)
  04-fixes.md                 ranked fixes + exact steps + what each one destroys
  05-tutorial.md              plain-language walkthrough, start to finish
  06-backup.md                what to back up, what is unrecoverable, how
  07-internet-without-wifi-or-sim.md   USB reverse tethering with gnirehtet
  08-hardening.md             OPTIONAL debloat + stability monitoring
  09-faq.md                   "can it come back?", warranty, root, LineageOS...
  10-evidence-index.md        what is in evidence/ and how it was sanitised
  11-ai-assisted-debugging.md debug with AI + ADB, prompts, and our mistakes
  12-confirmed-fix-nv-repair.md  THE FIX: unlock, erase modemst1/2, verify
scripts/
  adb/                        portable .ps1 + .sh: collect, disable, re-enable, verify
  windows/                    tether keeper + watchdog (path-parameterised)
evidence/                     sanitised crash signature, snapshot, logs
PRIVACY.md                    exactly what was removed before publishing
LICENSE                       MIT (code) / CC BY 4.0 (prose)
```

---

## The short version of the fix

```text
1. Dial *#06# and write both IMEIs down.
2. Unlock the bootloader (Motorola unlock code; wipes the phone).
3. fastboot erase modemst1
   fastboot erase modemst2
   fastboot reboot
4. Dial *#06# again — the IMEIs must match.
```

Everything else in this repo exists because that sequence is useless if you have not backed up, cannot tell whether your loop is the same bug, or the erase does not work.

---

## Disclaimer

Flashing, wiping and `pm disable-user` can brick a device or void warranty. This guide is provided **as-is, with no warranty**. You are responsible for your own device and data.

- A factory reset is **irreversible** for on-device data. Back up first.
- Disabling packages in [`scripts/adb/debloat-optional.txt`](scripts/adb/debloat-optional.txt) can break VoLTE, emergency calling or OTA. It is **optional and reversible**.
- If the phone is under warranty and the reset does not help, use the service centre — do not open the device.

---

## Contributing

Corrections, additional `fogos` builds, or reports of the same crash signature are welcome. Please open an issue with your **build fingerprint**, **baseband version** and a **`logcat -b crash` excerpt** — and scrub your serial/IMEI first. See [`PRIVACY.md`](PRIVACY.md) for the redaction checklist used here.

---

## AI co-authorship

This repository was written by the owner together with an **AI coding agent** (DeepSeek V4.1 Flash via OpenCode). The split is roughly:

- **Human:** owns the device, ran every command, made every destructive decision, verified the outcome.
- **AI:** read the logs, proposed hypotheses, wrote the scripts and the documentation, and was wrong more than once.

We are disclosing this because AI-assisted debugging is useful and should be normalised — but also because **AI output needs verification**. The evidence is published so you can check the reasoning instead of trusting it. See [`docs/11-ai-assisted-debugging.md`](docs/11-ai-assisted-debugging.md) for the workflow, the prompts, and the mistakes.

If you use AI on your own device: verify every claim against `getprop`/`logcat`, sanitise logs before sharing them, and never let it talk you into `erase`, `flash`, or `uninstall` without a stated reason.
