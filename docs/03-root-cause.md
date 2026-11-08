# 03 — Root cause: what actually broke

> [!IMPORTANT]
> **Corrected 2026-11-08 — the theory on this page was wrong.**
>
> This page originally argued that the trigger was **stale AP-side telephony state in
> `/data`**, permanently cleared by a factory reset. That was disproven on the same
> device:
>
> - the factory reset **did not hold** — the loop returned about **three hours later**;
> - the modem kept asserting with `/data` wiped and **both SIMs removed**;
> - `subsys2/crash_count` (modem) climbed while every other subsystem stayed at `0`.
>
> The real cause is **corrupt NV in `modemst1` / `modemst2`**, and the real fix is
> **erasing those two partitions** after unlocking the bootloader.
>
> **Read [`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md) first.** The
> text below is kept as a record of the reasoning that led there, with inline
> corrections. The crash mechanics (the token bug, the watchdog) are still accurate —
> it is the *trigger* and the *fix* that changed.

This is the technical core of the report. It explains the crash, the trigger, why every "obvious" fix failed, and why a factory reset appeared to work.

---

## The short version

1. **The modem's NV database (`modemst1` / `modemst2`) was corrupt.**
2. On every boot the modem failed its own consistency check, asserted, and reset
   (`subsys2/crash_count++`).
3. When the modem goes down, its QMI services vanish and `qcrilNrd`'s oemhook token
   table goes stale.
4. The next oemhook send dereferences the failure code `0xffffffffffffff02` (`-254`) and
   `qcrilNrd` dies with `SIGSEGV`.
5. The framework blocks on a Binder call that will never return. The **watchdog** reboots
   the phone after ~60 s. Loop.
6. Flashing Android images never helped because the fault is in the modem's **NV data**,
   which no image flash touches.
7. **Erasing `modemst1` + `modemst2`** makes the modem rebuild NV from the golden `fsg`
   partition. That fixed it. IMEI survived, LTE and voice came back.

> The `libmotext_inf.so` / `qcrilNrd` crash is a **symptom**. Patching it would stop the
> bootloop and leave you with a phone that has no cellular.

---

## Architecture: who talks to whom

```text
┌──────────────────────────── AP (Android) ────────────────────────────┐
│                                                                      │
│  apps ──► TelephonyManager / TelephonyService ──► RIL Java ──┐        │
│                                                              │        │
│  vendor apps (omadm, cne, msimsettings, moto, ...) ──────────┤        │
│                                                              ▼        │
│                                              ┌────────────────────┐   │
│                                              │  qcrilNrd          │   │
│                                              │  (Qualcomm RIL)    │   │
│                                              │                    │   │
│                                              │ libqcrilNr.so      │   │
│                                              │  ├ oemhook agent   │   │
│                                              │  └ token table     │   │
│                                              │                    │   │
│                                              │ libmotext_inf.so ◄─┼── Motorola
│                                              │  communicationThread│   │  oemhook
│                                              └─────────┬──────────┘   │  client
│                                                        │              │
└────────────────────────────────────────────────────────┼──────────────┘
                                                         │ QMI / shared memory
                                              ┌──────────▼──────────┐
                                              │  modem / baseband   │
                                              │  (separate CPU,     │
                                              │   own firmware,     │
                                              │   own NVRAM)        │
                                              └─────────────────────┘
```

Two important consequences:

- **The modem is a separate computer.** It runs its own firmware (`M6375_HI434_03.562.01.98R FOGOS_PVT_APEM2DSDS_CUST` here) and has its own persistent storage.
- **`qcrilNrd` is a single point of failure.** If it dies, every telephony call from `system_server` blocks. Android's watchdog is designed to reboot in exactly that situation.

---

## What is "oemhook"?

Qualcomm's RIL exposes a vendor-specific channel, **oemhook**, for messages the standard Android telephony API does not cover: carrier provisioning, SIM lock, modem statistics, RF calibration, operator updates.

The modem can send these **unsolicited** — the phone did not ask. On this device the recurring set was:

| Indication | Meaning |
|---|---|
| `qcrilUpdRegRAT` | Radio access technology changed (LTE ↔ 5G ↔ 3G) |
| `qcrilUpdateOperator` | Operator/PLMN info changed |
| `qcrilUpdDataState` | Data connection state changed |
| `qcrilUpdAPMState` | Airplane-mode state changed |
| `qcrilUpdVoiceCallCountAndWfcFlag` | Call count / Wi-Fi calling flag changed |

These are **normal, high-frequency events**. A phone with two SIMs, flapping between LTE/5G and re-registering, emits them constantly. That is why the crash repeated every ~8 seconds: the bug was on the *hot path*, not a rare branch.

---

## The bug: a poisoned token

```text
qcril_qmi_oemhook_agent_send()            libqcrilNr.so
  └─ qcril_qmi_oem_free_and_convert_ril_token_to_oem_token()
       └─ dereference(token)  ← token == 0xffffffffffffff02   ✗ SIGSEGV
```

The oemhook agent keeps a **token table** mapping RIL-side message tokens to OEM-side tokens. When a message is sent, the code looks up the token, converts it, and frees it. If the same token is converted **twice**, or converted after the table entry was invalidated, the lookup returns a poisoned value.

`0xffffffffffffff02` is `-254`. That is not an address; it is a sentinel written into a freed slot (a common pattern is to fill freed memory with a small negative value, or `0xFF`-fill and then add an offset). Dereferencing it gives `SEGV_MAPERR`, not `SEGV_ACCERR` — the kernel is saying "this address is not mapped", which is exactly what you expect from a garbage pointer.

**Why can't we just patch it?** `libmotext_inf.so` lives on the **vendor** partition, which is verified boot–protected. The reference device was stock, bootloader locked, no root. Patching is not a realistic consumer fix. (And even with root, a vendor blob update would be overwritten by the next OTA.)

**Why doesn't the crash just get retried forever?** It does — 14 times per boot. But each crash leaves `system_server` waiting on a Binder transaction to a dead process. The watchdog counts ~60 s of no progress and kills the system. That is the reboot.

---

## The trigger: corrupt modem NV

> **This section was rewritten on 2026-11-08.** The original text argued the trigger was
> AP-side state in `/data`. It was not. See
> [`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md).

The original field notes said *"Factory reset cleared corrupt modem NVRAM."* That turned
out to be **closer to the truth than the correction that replaced it** — but a factory
reset does not actually touch modem NVRAM, which is exactly why the reset did not last.

### What a factory reset actually wipes

| Area | Wiped by "Wipe data/factory reset"? |
|---|---|
| `/data` (apps, accounts, `/sdcard` media, most app databases) | **Yes** |
| `/data/vendor/radio/` — RIL/modem persistent state, QCRIL databases, carrier overrides | **Yes** |
| `/data/user_de/0/com.android.providers.telephony/databases/telephony.db` — APNs, subscriptions | **Yes** |
| `/data/misc/radio/` — radio config, modem logs | **Yes** |
| `/persist` — RF calibration, some sensor/modem calibration | **No** |
| `modemst1` / `modemst2` — modem NVRAM (IMEI-adjacent, provisioning) | **No** |
| `fsg` — modem filesystem backup | **No** |
| Modem firmware image (`NON-HLOS`/`modem`) | **No** |

So a plain recovery reset does **not** touch the modem's own NVRAM partitions. That is
the whole problem: the corrupt data survives the reset, so the modem asserts again on the
next boot.

### What was actually going on, ranked

1. **`modemst1` / `modemst2` held corrupt or inconsistent NV items.** The modem failed its
   boot-time consistency check and asserted. **This is the confirmed cause** — erasing both
   partitions and rebuilding from `fsg` fixed the device completely.
2. **`/data/vendor/radio` + telephony databases were inconsistent.** *Disproven as the
   cause.* `/data` was wiped twice and the modem still asserted. This state may have
   amplified the crash rate, but it was not the trigger.
3. **A half-finished OTA left state out of sync.** Possible contributor to *how* the NV
   got written badly, but not the fault itself.

> **Why this matters:** the earlier advice here — "wipe userdata first, do not touch
> `modemst`" — was **wrong for this device**. Wiping userdata did not fix it. The modem-only
> erase did.
>
> The IMEI risk is real but manageable: **record your IMEI (`*#06#`) before erasing**, then
> confirm it is unchanged afterwards. The rebuild copies it from `fsg`.

### Why the crash started when it did

The first symptom was **loss of SIM signal**, then mobile data, then Wi-Fi, then the reboot loop — all inside about a minute:

```text
SIM signal lost → data lost → Wi-Fi lost → hotspot dead → reboot → loop
```

That ordering is the strongest clue available. The modem/RIL layer failed **first**; Wi-Fi and the rest fell over afterwards because they share the same wedged `system_server`/telephony stack. It was not a random hardware reboot, and it was not caused by an app install or an update.

The most plausible sequence is:

1. Something corrupted the modem's NV database — an interrupted NV write (power loss, aborted OTA staging), or a failing storage block under `modemst`. The device had a pending OTA and two SIMs in DSDS, both of which increase NV write traffic.
2. On the next boot the modem failed its own consistency check and **asserted** (`subsys2/crash_count++`). Its QMI services disappeared.
3. `qcrilNrd` kept a token that referred to the dead connection; the next oemhook send dereferenced the failure code and it died. SIM registration dropped.
4. The framework kept retrying; each retry hit the same dead path. Wi-Fi init never completed.
5. The watchdog rebooted. The corrupt NV persisted across reboots, so the loop repeated.

We cannot prove which event wrote the bad NV. We *can* prove that rebuilding it stopped the crashes — and that flashing new images three times and resetting twice did not.

---

## Why each attempted fix behaved the way it did

| Attempt | Result | Explanation |
|---|---|---|
| **Android 15 OTA** | Loop persisted | Replaced system/vendor images. `modemst1/2` were untouched. |
| **LMSA / "Software Fix", latest full firmware** | Loop persisted | Full firmware download and flash, but **userdata and NV preserved** — and no image flash rewrites the modem NV store. |
| **Latest security-patch build (`…-9-13`)** | Loop persisted, identical signature | Newer build, same corrupt NV. |
| **LMSA rescue, "no factory delete"** | Loop persisted | By design preserves userdata. It also cannot repair `modemst1/2`. |
| **Disable 13 oemhook packages** | Crashes 14 → ~2 per boot | Apps are *clients* that send oemhook traffic. Removing clients reduces traffic, but the **modem itself** still sends unsolicited indications. Not a fix. |
| **Airplane mode ON** | Crashes near zero | No radio → no `RegRAT`/`UpdateOperator`/`DataState` events → the hot path is never entered. This is a **workaround**, not a repair. |
| **Wi-Fi off, animations off, stay-awake** | Marginal | Reduces load and the chance of hitting the watchdog window. Cosmetic. |
| **ADB reverse tether (gnirehtet)** | Internet restored | Bypasses the broken telephony/Wi-Fi stack entirely. Does not touch the bug. See [`07`](07-internet-without-wifi-or-sim.md). |
| **Factory reset #1** | Loop stopped **for ~3 hours**, then returned | The reset re-provisioned the modem stack, which temporarily masked the corrupt NV. It does not touch `modemst1/2`, so the fault survived. |
| **Factory reset #2** | Loop returned again | Confirms the reset is not a fix. |
| **Re-enable all 13 packages after reset** | No change | Proves the packages were never the cause. |
| **`fastboot erase modemst1` + `modemst2`** (bootloader unlocked) | **Loop stopped permanently; LTE + voice returned** | The modem rebuilt NV from `fsg`. **This is the fix.** |

> **The pattern is the point:** three firmware images failed, two factory resets failed, and
> the only thing that worked was erasing the modem's NV. A reset that "works" for a few hours
> is not a fix — it is a delay.

---

## Why the fault can come back

The NV store is rebuilt, not repaired in place. Whether the corruption returns depends on
*why* it was corrupt in the first place:

| Cause | Recurrence |
|---|---|
| A one-off interrupted NV write (power loss, aborted update) | **Unlikely** — the erase is a permanent repair |
| A failing UFS/eMMC block where `modemst` lives | **Likely** — the erase fixes it temporarily, each time |
| A power/thermal fault affecting the modem's write path | Possible |

Practical rule: if `subsys2/crash_count` starts climbing again, run the two erases again.
If that keeps happening, the phone has a storage or board fault, not a software problem.

Other things that can still cause trouble:

- **Another interrupted OTA**, or a carrier-config push.
- **A modem firmware crash** that leaves NV half-written.
- **Restoring an old full `/data` image** — not the cause here, but it can reintroduce
  unrelated stale state.

### If it comes back

```text
1. Confirm the signature          → docs/01-symptoms.md
2. Check the modem crash counter  → docs/02-diagnosis.md
3. Re-run the NV repair           → docs/12-confirmed-fix-nv-repair.md
4. Still looping?                 → flash radio.img, erase modemst1/2 again
5. Still looping?                 → service centre: read /data/vendor/ssrdump/
```

Do **not** start by disabling packages or reinstalling firmware. Those are slower, treat symptoms, and cannot reach the modem's NV store.

---

## Build numbers in this report

The source notes contain two Android 15 build strings:

| Where | Build |
|---|---|
| OTA notification, early notes | `V1UG35H.75-14-4` |
| Post-LMSA, post-repair verification | `V1UGS35H.75-14-9-3-1-4` |

The second is the build that was actually running when the device was verified stable, and it matches the `ro.build.fingerprint` captured after the repair. The first is the OTA *package* version that was downloading. They are not contradictory — one is the update payload, the other is the installed build — but they are easy to confuse, so both are recorded here.

**Android 14 baseline:** `motorola/fogos_gpn/fogos:14/U1UG34.23-110-35/a1cf4-d651b9:user/release-keys`
**Baseband before the loop:** `M6375_HI434_03.562.01.98R FOGOS_PVT_APEM2DSDS_CUST`
**Baseband after the NV repair:** `M6375_HI434_03.562.01.121R`

The crash signature was **byte-for-byte identical** on both Android versions. That is the strongest single piece of evidence that the OS version was irrelevant.

---

## Next

- What to actually do, ranked, with the cost of each: [`04-fixes.md`](04-fixes.md)
- Protect your data before wiping: [`06-backup.md`](06-backup.md)
