# 12 — Confirmed fix: corrupt modem NV (`modemst1` / `modemst2`)

> **Status: confirmed on hardware, 2026-11-08.**
> This supersedes the "stale `/data` state" theory in [`03-root-cause.md`](03-root-cause.md).
> A factory reset did **not** fix this device — the loop returned about three hours later.
> Erasing the modem's NV partitions **did** fix it: the modem came back, registered on LTE,
> and cellular data and voice worked.

---

## TL;DR

```text
The modem's NV database was corrupt.
  → the modem asserted on every boot
  → QMI services vanished
  → qcrilNrd dereferenced a stale token (0xffffffffffffff02) and died
  → system_server blocked → watchdog rebooted the phone → loop

Fix (requires an unlocked bootloader):
  fastboot erase modemst1
  fastboot erase modemst2
  fastboot reboot

The modem rebuilds NV from the golden fsg partition. IMEI survives.
```

---

## What is actually broken

The phone has three relevant storage areas for the modem:

| Partition | Contents | Wiped by factory reset? |
|---|---|---|
| `modemst1` | **primary NV item store** — IMEI, RF references, carrier/band config, provisioning | **No** |
| `modemst2` | **backup NV item store** | **No** |
| `fsg` | golden factory copy of the NV defaults (read-only reference) | **No** |

`modemst1` / `modemst2` are the database the modem reads at boot. If items in that
database are corrupt or internally inconsistent, the modem fails its own consistency
check, asserts, and resets. That is the `subsys2` crash.

Everything else in this report is downstream of that:

```text
modem asserts (subsys2 crash_count++)
  → QMI services disappear
    → qcrilNrd's oemhook token table goes stale
      → qcril_qmi_oem_free_and_convert_ril_token_to_oem_token()
          dereferences 0xffffffffffffff02  → SIGSEGV
        → qcrilNrd dies
          → system_server blocks on a Binder call that never returns
            → watchdog reboots the phone after ~60 s
              → loop
```

So the `libmotext_inf.so` / `qcrilNrd` crash is a **symptom**, and the bootloop is a
**symptom of a symptom**. The fault is below the vendor library, in the modem's own
persistent data.

### The fault address proves it

`0xffffffffffffff02` is `-254` sign-extended from 32 bits. That is an **error code used
as a pointer** — the token conversion failed and the caller dereferenced the failure.
It fails *because the modem connection it referred to is gone*, not because the library
is randomly buggy.

---

## The fix

### Preconditions

1. **An unlocked bootloader.** `fastboot erase modemst1` is refused while locked
   (`securestate: flashing_locked`). See [unlocking](#unlocking-the-bootloader) below.
2. **Your IMEI(s) written down.** The rebuild restores them from `fsg`, but you must be
   able to prove it afterwards. Dial `*#06#` before you start.
3. **A USB data cable**, and `fastboot` that actually works
   (`fastboot devices` must list the phone).

### Steps

```bash
# 1. Put the phone in fastboot: power off, then hold Volume Down + Power
fastboot devices

# 2. Confirm you are actually unlocked
fastboot getvar all | grep securestate      # expect: flashing_unlocked

# 3. Erase both NV stores, one at a time, and check each says OKAY
fastboot erase modemst1
fastboot erase modemst2

# 4. Reboot
fastboot reboot
```

First boot after the erase takes several minutes: the modem rebuilds NV from `fsg`
before the radio comes up.

### Verify

```bash
adb shell getprop gsm.version.baseband        # must not be empty
adb shell getprop gsm.sim.state               # LOADED,...
adb shell cat /sys/bus/msm_subsys/devices/subsys2/crash_count   # must stay 0
adb shell cat /proc/uptime
```

On the phone, dial `*#06#` — the IMEI must be **the same number you wrote down**.

| Result | Meaning |
|---|---|
| Baseband present, `crash_count` stays `0` | **NV was corrupt — repaired** |
| Baseband present, then `crash_count` climbs | NV was rebuilt but the modem still dies → firmware or hardware |
| Baseband never appears | Deeper fault — see [if it does not work](#if-it-does-not-work) |
| **IMEI blank or different** | `fsg` rebuild failed — **stop, do not use the phone** |

---

## Unlocking the bootloader

Motorola will only unlock **retail** units, and only if the region/`cid` is eligible.
A `retid` (India retail) unit such as the reference device is eligible; carrier-locked
SKUs generally are not.

1. In Android: **Settings → About phone → tap Build number 7×**, then
   **Settings → System → Developer options → OEM unlocking → ON**.
   If the toggle is greyed out, the device is not eligible — stop here.
2. Reboot to fastboot (**Power off**, then **Volume Down + Power**).
3. Get the unlock data and submit it to Motorola's bootloader-unlock page:

   ```bash
   fastboot oem get_unlock_data
   ```

   Join the five `(bootloader)` lines into one continuous string (strip the prefix and
   spaces) and paste it into Motorola's "Unlock your device" support page. They email a
   20-character key.
4. Unlock:

   ```bash
   fastboot oem unlock <20-CHARACTER-KEY>
   ```

   This **wipes all data**.

> **The unlock data string contains your serial number.** Do not post it publicly.

### Consequences of unlocking

- `ro.boot.verifiedbootstate` becomes `orange` (was `green`).
- Play Integrity / Google Wallet / some banking apps may refuse to run.
- Widevine may drop L1 → L3 (streaming capped at SD).
- Warranty is void.
- **Do not relock** unless you are on a complete stock flash — relocking a modified boot
  chain bricks the device.

---

## Evidence: before and after

Reference device: `XT2363-9` / `fogos`, build `V1UGS35H.75-14-9-3-1-4`,
baseband `M6375_HI434_03.562.01.121R`.

| Measurement | Before the erase | After the erase |
|---|---|---|
| `subsys2/crash_count` | climbing `2 → 14` with SIM, `2 → 9` with **both SIMs removed** | **`0`, stable** |
| Baseband | empty while crashed | `M6375_HI434_03.562.01.121R` |
| `qcrilNrd` | SIGSEGV roughly every 7 s | alive, original PIDs, no restarts |
| Network | none | `IN_SERVICE`, LTE, data connected |
| IMEI | intact | intact (rebuilt from `fsg`) |
| Kernel uptime | reboot every 2–4 min | no reboots during continuous monitoring |

Two facts that rule out the alternatives:

- The modem crashed **with both SIMs removed and `/data` wiped** → not app-, SIM- or
  userdata-triggered.
- The crash count climbed in **`subsys2` (modem) only**; `adsp`, `cdsp`, `ipa_fws`,
  `a615_zap` and `venus` stayed at `0` → not a general SoC/storage problem.

---

## What does **not** work, and why

| Attempt | Why it fails |
|---|---|
| **Factory reset** | Does not touch `modemst1` / `modemst2`. The loop returns — on the reference device after ~3 hours. |
| **LMSA "Upgrade" / rescue without a full erase** | Rewrites images but leaves the NV stores intact. |
| **Debloating the oemhook packages** | Removes *clients*; the modem still asserts on its own. |
| **Airplane mode** | Suppresses the crash path; not a repair. |
| **Patching `libmotext_inf.so`** | Would fix the *crash handling*, not the modem. Best case: no bootloop, still no cellular. |
| **Custom ROM (LineageOS, AxionOS, …)** | A ROM flashes `boot`/`vendor_boot`/`dtbo`/`super`. It cannot reach `modemst1/2`, and it reuses Motorola's vendor blobs. The modem stays broken. |
| **Flashing a firmware package's `radio.img` alone** | Rewrites the modem *firmware*; the corrupt NV stays corrupt. Useful only if firmware is also suspect. |

> **The ROM trap.** Installing a custom ROM can make the phone *boot* by changing how a
> dead modem is handled — you get a Wi-Fi-only device with "No service". That looks like a
> fix and is not one. It also requires an unlocked bootloader, i.e. the same unlock the
> real repair needs. Do the NV repair first.

---

## If it does not work

Ranked by cost:

1. **Rewrite the modem firmware**, now that you are unlocked:

   ```bash
   fastboot flash radio radio.img      # from an XT2363-9 / fogos package
   fastboot erase modemst1
   fastboot erase modemst2
   fastboot reboot
   ```

   Use the `radio` image from a **matching or newer** package. Do not flash
   `gpt.bin`, `bootloader.img`, `abl`, `xbl` or `tz` from an older package — Motorola's
   anti-rollback will hard-brick the device.

2. **Service centre.** Ask them to read `/data/vendor/ssrdump/` — the modem's own crash
   reason. That file names the failing assertion and separates NV corruption from a
   hardware fault in one step. It is SELinux-denied to `adb shell`.

3. **Board-level repair.** If NV rebuild and a firmware reflash both fail, suspect the
   UFS/eMMC block where `modemst` lives, the modem DSP, or the PMIC rail feeding it.

---

## Recurrence

Unknown, and worth watching. NV does not corrupt itself; something wrote bad data. Two
scenarios:

| Scenario | Recurrence |
|---|---|
| A one-off interrupted NV write (power loss, aborted update) | **Unlikely.** The erase is a permanent repair. |
| A failing UFS/eMMC block or a power fault in that area | **Likely.** The same erase will fix it temporarily, each time. |

Practical rule: if `crash_count` starts climbing again, run the two erases again. If that
keeps happening, the phone has a storage or board fault, not a software problem.

---

## What this changes in the rest of the repo

- [`03-root-cause.md`](03-root-cause.md) — the "stale `/data` state" trigger was the wrong
  hypothesis. Kept for the record, with corrections.
- [`04-fixes.md`](04-fixes.md) — the ranked list now starts with the NV erase, not a
  factory reset.
- [`09-faq.md`](09-faq.md) — "can it come back", "is it hardware", "can I fix it without
  unlocking" all changed.
- [`11-ai-assisted-debugging.md`](11-ai-assisted-debugging.md) — the mistaken path is
  documented there as a case study: the reset *appeared* to work for three hours, which
  was long enough to be mistaken for a fix.
