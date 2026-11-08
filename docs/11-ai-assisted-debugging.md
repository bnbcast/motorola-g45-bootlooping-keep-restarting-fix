# 11 — Debugging this with AI + ADB

This repo was diagnosed and written with an AI coding agent in the loop. This page explains **how to use an AI assistant on your own phone**, what to feed it, what not to feed it, and the mistakes we made so you don't repeat them.

> **Using an AI right now?** Hand it **this whole repository** — `README.md`, `docs/00`–`docs/11`, `evidence/`, `scripts/` — and tell it to follow this guide step by step. Then verify every claim it makes against real output before running anything.

> **The AI cannot see your phone.** It cannot run `adb`, flash firmware, or verify that a package name exists. It is a very fast reader of logs and a very confident guesser. You are the one with the device, the cable and the responsibility.

---

## Why AI is genuinely useful here

| Task | Why AI helps |
|---|---|
| Reading a native crash buffer | It recognises `SIGSEGV`, poisoned pointers like `0xffffffffffffff02`, and can map a backtrace to a subsystem |
| Correlating symptoms | "SIM died, then data, then Wi-Fi, then reboot" → one shared dependency (`system_server` / telephony) instead of four hardware faults |
| Writing one-shot scripts | The boot window is ~2 minutes; a single script that dumps everything beats typing commands |
| Translating vendor jargon | `qcrilNrd`, `oemhook`, `RegRAT`, `APMState`, `modemst1/2` |
| Sanitising output | Spotting serials, IMEIs, emails and paths before you paste logs in public |
| Drafting the write-up | Turning a messy timeline into a reproducible guide |

## What AI is bad at here

- **It hallucinates package names and prop keys.** Always verify with `adb shell pm list packages | grep …` or `getprop`.
- **It will suggest destructive commands** (`fastboot erase`, `pm uninstall`, `rm -rf`) if you ask vaguely. Ask for **read-only** commands first.
- **It does not know your exact build.** `fogos` has multiple firmware branches; a fix for one build may not apply.
- **It cannot confirm a fix.** Only 10+ minutes of uptime with zero `qcrilNrd` crashes does that.

---

## The workflow we actually used

This is the loop behind [`evidence/timeline.txt`](../evidence/timeline.txt). Copy it.

```
1. OBSERVE     What exactly happens, in what order, how long between reboots?
2. CAPTURE     Pull the evidence while the phone is up (or from persistent storage).
3. HYPOTHESISE One sentence: "X causes Y because Z."
4. PREDICT     "If X is the cause, then doing A should change B."
5. TEST        One change at a time. Record the result.
6. CORRECT     When the prediction fails, throw the hypothesis away. Do not patch it.
```

The important part is **step 6**. Our first hypothesis (modem NVRAM) was wrong, and the fix only worked after we abandoned it — see [`03-root-cause.md`](03-root-cause.md).

---

## What to capture before you ask an AI anything

Run these while the phone is up. Save each output to a file.

```bash
adb devices
adb shell getprop > props.txt
adb shell 'cat /proc/uptime'
adb shell getprop ro.boot.bootreason
adb shell 'logcat -d -b crash' > crash.txt
adb shell 'logcat -d -b system' > system.txt
adb shell 'dumpsys telephony.registry' > telephony.txt
adb shell 'dumpsys connectivity' > connectivity.txt
adb shell 'ls -l /data/tombstones' > tombstones.txt
```

The repo ships scripts that do this in one shot:

- [`scripts/adb/collect-evidence.ps1`](../scripts/adb/collect-evidence.ps1) (Windows)
- [`scripts/adb/collect-evidence.sh`](../scripts/adb/collect-evidence.sh) (Linux/macOS)

> **Tombstones persist across reboots.** If the loop is too fast to catch `logcat` live, pull `/data/tombstones` instead — they survive until the next factory reset. This is the single most useful trick in the whole guide.

---

## Prompt template

Paste this into your AI assistant, then attach or paste the files.

```text
You are helping me debug an Android device over ADB. Do not guess.

Device: Motorola Moto G45 5G (XT2363-9, codename fogos, SM6375)
Build: <ro.build.fingerprint>
Baseband: <gsm.version.baseband>
Symptom: <one sentence, with timings>
Uptime before reboot: <seconds>

Attached:
- crash.txt   (logcat -b crash)
- props.txt   (getprop)
- telephony.txt
- connectivity.txt

Rules:
1. Start with read-only commands only. No erase, no flash, no uninstall.
2. For every claim, quote the exact line from the files that supports it.
3. If the evidence is insufficient, say what to capture next.
4. Give me one hypothesis at a time, with a prediction I can test.
5. Tell me what would prove you wrong.
```

That last rule matters. An AI that cannot be wrong is useless for debugging.

**Indonesian version** (also in [`README.id.md`](../README.id.md)):

```text
Kamu membantu saya debug HP Android lewat ADB. Jangan menebak.

Perangkat: Motorola Moto G45 5G (XT2363-9, codename fogos, SM6375)
Build: <ro.build.fingerprint>
Baseband: <gsm.version.baseband>
Gejala: <satu kalimat, sertakan waktunya>
Uptime sebelum reboot: <detik>

Lampiran:
- crash.txt   (logcat -b crash)
- props.txt   (getprop)
- telephony.txt
- connectivity.txt

Aturan:
1. Mulai dari perintah read-only. Jangan erase, flash, atau uninstall.
2. Setiap klaim harus dikutip dari baris yang mendukung di file.
3. Kalau bukti kurang, bilang apa yang harus saya ambil lagi.
4. Beri satu hipotesis per langkah, lengkap dengan prediksi yang bisa diuji.
5. Bilang apa yang akan membuktikan kamu salah.
```

---

## Sanitise before you paste

Logs are full of identifiers. **Never paste raw output into a public issue or chat.** At minimum remove:

- `ro.serialno`, `ro.boot.serialno`, `ro.vendor.boot.serialno`
- IMEI / MEID / ICCID / IMSI / phone number
- Wi-Fi SSIDs, BSSIDs, MAC addresses
- Google account names and `authuser=` values
- Bluetooth device names
- Local file paths (`C:\Users\…`)

Full checklist: [`PRIVACY.md`](../PRIVACY.md). You can also ask the AI to redact the files *before* you read them, but **check its work** — it will miss things.

---

## Mistakes we made (do not repeat these)

Every one of these cost time, and two of them could have destroyed the phone.

### 1. Concluding that the trigger was in `/data`

This was the expensive mistake. We had a real crash — `qcrilNrd` dying at `0xffffffffffffff02` — and we explained it with stale telephony state in `/data`. A factory reset then "fixed" it, which looked like confirmation.

**Why it was wrong:** the loop came back about **three hours later**. A reset does not touch `modemst1`/`modemst2`, and the modem's NV database there was corrupt. We had built a self-consistent story on top of a coincidence: the reset re-provisioned the modem stack, which *masked* the fault long enough to be mistaken for a repair.

**Lesson:** a fix that holds for hours is not a fix. Test across a reboot, and then across days. And when a "confirmed" cause leaves one anomaly unexplained, keep the old hypothesis on the table.

### 2. Using LMSA "no factory delete" to preserve the wrong state

The Motorola/Lenovo tool has an option that preserves user data. We used it because it felt safer.

**Why it was wrong:** "safer" meant "keeps whatever was in `/data`". But the fault was not in `/data` at all, so the option made no difference either way. It re-flashed everything except the partitions that mattered.

**Lesson:** a data-preserving flash is a no-op against a fault that is not in user data — and the option is not a diagnosis.

### 3. Repeating the "factory reset clears modem NVRAM" myth — then over-correcting

Forums say a factory reset clears modem NVRAM. That is **imprecise**: a recovery `Wipe data/factory reset` does **not** touch `modemst1` / `modemst2`.

We corrected the myth — and then over-corrected. We concluded the modem's NVRAM could not be involved, when in fact it was the *only* thing involved. The folklore was closer to the truth than our correction.

**Lesson:** a plausible-sounding explanation is not evidence. Check which partitions the operation actually writes — and do not let debunking one claim rule out the whole area.

### 4. Treating package disabling as the fix

We disabled 13 Motorola/Qualcomm packages. The crash rate dropped, so it looked like progress.

**Why it was wrong:** those apps *send* oemhook traffic. Fewer senders means fewer chances to hit the bug — not a fixed bug. The loop returned.

**Lesson:** reducing the frequency of a crash is not the same as removing the cause.

### 5. Racing `logcat` instead of pulling tombstones

With a 2-minute window we kept trying to catch the crash live and losing it.

**Lesson:** `/data/tombstones` persists across reboots. Pull it once, read it calmly.

### 6. Burning the boot window on the lock screen

A PIN/pattern keeps `/data` encrypted until first unlock, so ADB is unusable for part of every boot. We lost entire windows to this.

**Lesson:** set the screen lock to **None** temporarily, enable **Stay awake**, and restore the lock afterwards. See [`00-requirements.md`](00-requirements.md#why-remove-the-screen-lock-and-the-catch).

### 7. Not ticking "Always allow from this computer"

Without it, every reboot waits for a tap on the phone — which you cannot reach in time.

**Lesson:** authorise the PC once, and remember a factory reset wipes that authorisation.

### 8. Refusing to try `fastboot erase modemst1/modemst2`

This was on the table for weeks and we kept talking ourselves out of it: it can destroy IMEI provisioning, the bootloader was locked, and our theory said `/data` was the problem.

**Why it was wrong:** it was the fix. The IMEI risk is real but manageable — record the IMEI first, erase, confirm it afterwards. The modem rebuilds NV from the golden `fsg` partition, which contains the IMEI.

**Lesson:** "too risky" is not an argument when the alternative is a device that never boots. Quantify the risk, mitigate it (record the IMEI), and test. See [`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md).

### 9. Trusting anecdotal success rates

Early drafts said "~60% success" and "~90% success". Those numbers were invented from forum reading, not measured.

**Lesson:** if you did not measure it, label it as anecdotal — or delete it.

### 10. Reading simultaneous failures as hardware failure

SIM, mobile data, Wi-Fi and hotspot all died within a minute. That looks like a dead radio.

**Why it was wrong:** they all depend on `system_server` and the telephony stack. `qcrilNrd` wedging took all of them down together. One cause, many symptoms.

**Lesson:** when unrelated subsystems fail at the same instant, look for the shared dependency, not four broken parts.

### 11. Backing up too late

The WhatsApp decryption key and 2FA seeds live in `/data`. A factory reset destroys them.

**Lesson:** back up first. See [`06-backup.md`](06-backup.md).

---

## Guardrails for AI-assisted repair

1. **Read-only first.** Make the AI start with `getprop`, `logcat`, `dumpsys`. No writes until you understand the failure.
2. **One change per test.** If you change three things and it works, you learned nothing.
3. **Demand citations.** Every claim should quote a log line. If it cannot, it is guessing.
4. **Ask "what would prove you wrong?"** If the answer is "nothing", discard the hypothesis.
5. **Never paste raw logs publicly.** Sanitise first.
6. **Never let it talk you into `erase`, `flash`, or `uninstall` without a stated reason and a rollback.**
7. **Verify the fix with time, not with a reboot.** 10+ minutes uptime and `qcrilNrd` crash count = 0.
8. **Keep a log.** Write down each hypothesis and result — that is what became [`evidence/timeline.txt`](../evidence/timeline.txt).

---

## How the root cause was actually found

The AI did not "solve" it by magic, and it did not solve it on the first try. The sequence was:

1. `logcat -b crash` showed `qcrilNrd` dying with `SIGSEGV` at `0xffffffffffffff02`.
2. The backtrace ended in `libmotext_inf.so communicationThread` — a Motorola proprietary library.
3. The fault address `0xffffffffffffff02` (`-254`) is a classic poisoned pointer, so the AI proposed **use-after-free**.
4. The AI concluded the trigger was **stale telephony state in `/data`**. Prediction: wiping `/data` stops it. Two factory resets appeared to confirm it — the first held for about three hours.
5. **The loop came back.** That falsified the hypothesis, which is the step that actually mattered.
6. The anomaly was the modem crash counter: `/sys/bus/msm_subsys/devices/subsys2/crash_count` was climbing, and it climbed with `/data` wiped **and both SIMs removed**. Only `subsys2` (modem) was affected; every other subsystem stayed at `0`.
7. That pointed below the RIL: the modem was asserting on its own. `modemst1` / `modemst2` hold its NV database.
8. Erasing both partitions and letting the modem rebuild from `fsg` fixed it — baseband returned, LTE and voice worked, IMEI intact, `crash_count` stayed at `0`.

The generalisable part: **the crash was the symptom; the subsystem crash counter was the evidence.** `logcat` told us where it died, not why.

Full reasoning: [`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md). The superseded theory, kept for the record: [`03-root-cause.md`](03-root-cause.md). Raw evidence: [`10-evidence-index.md`](10-evidence-index.md).

---

## AI co-authorship

This repository's diagnosis, scripts and documentation were produced by the repository owner working with an **AI coding agent** (DeepSeek V4.1 Flash, via OpenCode). The device evidence is real; the prose, code and analysis were drafted with AI assistance and then reviewed against the captured logs.

That means:

- Treat the text as a **strong starting point, not an authority**.
- Every technical claim should be checkable against [`evidence/`](../evidence/).
- If you find an error, please open an issue — see [`CONTRIBUTING.md`](../CONTRIBUTING.md).

Using AI to debug your own device is encouraged. Using it without verifying is how phones get bricked.
