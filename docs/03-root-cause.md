# 03 — Root cause: what actually broke

This is the technical core of the report. It explains the crash, the trigger, why every "obvious" fix failed, and why a factory reset worked. It also corrects one claim from the original field notes.

---

## The short version

1. Motorola's `libmotext_inf.so` has a **use-after-free** in its oemhook send path.
2. The bug is harmless while the telephony stack is in a consistent state.
3. On this device, **stale telephony/modem state in `/data`** put the stack in an inconsistent state, so the modem's routine unsolicited messages began hitting the freed pointer.
4. Each hit kills `qcrilNrd`. The framework blocks on it. The **watchdog** reboots the phone after ~60 s.
5. Flashing new Android images did not clear the stale state, because **userdata was preserved**.
6. A **factory reset** cleared it. The bug is still in the binary; it is simply not triggered any more.

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

## The trigger: stale state, not a bad binary

This is the part the original field notes simplified. The report said:

> *"Factory reset cleared corrupt modem NVRAM."*

That is **directionally right but technically imprecise**, and the imprecision matters if you are deciding what to do next.

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

So a plain recovery reset does **not** touch the modem's own NVRAM partitions. What it *does* wipe is the **AP-side telephony state that drives the oemhook conversation**.

### The most likely mechanism, ranked

1. **`/data/vendor/radio` + telephony databases were inconsistent.** A stale subscription/APN/carrier-config entry made the framework and modem disagree about the current operator/RAT/data state. Every `UpdateOperator` / `RegRAT` indication then carried a token the agent had already retired. Wiping the state restarts the conversation from a clean, self-consistent baseline. **This is the best-supported explanation** — it also explains why preserving `/data` (the "no factory delete" flash) kept the loop.
2. **A half-finished OTA left the modem/framework state machine out of sync.** The 1.97 GB Android 15 download stalled at 37 % before the LMSA flash. An interrupted OTA can leave `carrierconfig`/`radio` state inconsistent even when the final images are correct.
3. **Modem NVRAM *was* affected** (the original hypothesis). Possible if the reset triggered a modem re-provisioning on first boot, but there is no direct evidence: no `modemst` dump was taken before and after. Treat this as unproven.

> **Why this correction matters:** if you believe only modem NVRAM matters, you might try a modem-only erase (`fastboot erase modemst1/modemst2`) and skip the userdata wipe. That is riskier (it can destroy IMEI provisioning) and, based on the evidence, unnecessary. **Wipe userdata first.**

### Why the crash started when it did

The first symptom was **loss of SIM signal**, then mobile data, then Wi-Fi, then the reboot loop — all inside about a minute:

```text
SIM signal lost → data lost → Wi-Fi lost → hotspot dead → reboot → loop
```

That ordering is the strongest clue available. The modem/RIL layer failed **first**; Wi-Fi and the rest fell over afterwards because they share the same wedged `system_server`/telephony stack. It was not a random hardware reboot, and it was not caused by an app install or an update.

The most plausible sequence is:

1. Something pushed the modem/telephony state into an inconsistent configuration (a modem assertion, a carrier-config push, a SIM re-registration race, or an OTA staging operation). The device had a pending OTA and two SIMs in DSDS — both increase oemhook traffic.
2. `qcrilNrd` hit the token bug and died. SIM registration dropped.
3. The framework kept retrying; each retry hit the bug again. Wi-Fi init never completed.
4. The watchdog rebooted. The stale state persisted across reboots, so the loop repeated.

We cannot prove which event poisoned the state. We *can* prove that clearing the state stopped the crashes — and that flashing new images three times did not.

---

## Why each attempted fix behaved the way it did

| Attempt | Result | Explanation |
|---|---|---|
| **Android 15 OTA** | Loop persisted | Updated system/vendor images, **preserved userdata**. Same bug, same trigger. |
| **LMSA / "Software Fix", latest full firmware** | Loop persisted | Full firmware download and flash. Preserved userdata by default → preserved `/data/vendor/radio` and telephony DBs. |
| **Latest security-patch build (`…-9-13`)** | Loop persisted, identical signature | Newer build, same vendor library, same stale state. |
| **LMSA rescue, "no factory delete"** | Loop persisted | By design preserves userdata. The report's claim that it "skips modem firmware" is **not established**; what it definitely skips is the wipe. |
| **Disable 13 oemhook packages** | Crashes 14 → ~2 per boot | Apps are *clients* that send oemhook traffic. Removing clients reduces traffic, but the **modem itself** still sends unsolicited indications. Not a fix. |
| **Airplane mode ON** | Crashes near zero | No radio → no `RegRAT`/`UpdateOperator`/`DataState` events → the hot path is never entered. This is a **workaround**, not a repair. |
| **Wi-Fi off, animations off, stay-awake** | Marginal | Reduces load and the chance of hitting the watchdog window. Cosmetic. |
| **ADB reverse tether (gnirehtet)** | Internet restored | Bypasses the broken telephony/Wi-Fi stack entirely. Does not touch the bug. See [`07`](07-internet-without-wifi-or-sim.md). |
| **Factory reset #1** | **Loop stopped permanently** | Clears the inconsistent AP-side state; first boot re-provisions the modem stack from scratch. |
| **Factory reset #2** | Still stable | Confirms the first reset was not luck. |
| **Re-enable all 13 packages after reset** | Still stable | Proves the packages were never the cause. |

> **The pattern is the point:** three different firmware images failed, and one wipe succeeded. If flashing does not fix it, stop flashing and wipe.

---

## Why the bug can come back

The binary is unchanged. `libmotext_inf.so` still has the use-after-free. What changed is the *state*.

Recurrence requires the same precondition: the telephony state must become inconsistent again while the modem emits unsolicited indications. Realistic triggers:

- **Restoring old telephony data.** If you restore a full `/data` image (TWRP, `adb` root backup, some "phone clone" tools) you can reintroduce the exact stale state. **Do not restore `/data/vendor/radio` or `telephony.db` from a backup taken during the incident.**
- **SIM swap / dual-SIM reconfiguration** while the phone is on a flaky network.
- **Another interrupted OTA**, or a carrier-config push.
- **A modem firmware crash** that leaves the AP-side state stale.
- **An OTA that changes the vendor library** — could fix it, could expose a new path.

Observed recurrence risk after a clean reset: **low** (the reference device was stable across multiple reboots and days). But it is **not zero**, and it is **not "fixed" in the sense of a patched binary**.

### If it comes back

```text
1. Confirm the signature      → docs/01-symptoms.md
2. Back up                    → docs/06-backup.md
3. Factory reset              → docs/04-fixes.md  (worked once, likely works again)
4. Still looping?             → LMSA full flash WITH factory reset / fastboot stock firmware
5. Still looping?             → service centre (modem/PMIC hardware)
```

Do **not** start by disabling packages or erasing `modemst`. Those are slower, riskier, and treat symptoms.

---

## Build numbers in this report

The source notes contain two Android 15 build strings:

| Where | Build |
|---|---|
| OTA notification, early notes | `V1UG35H.75-14-4` |
| Post-LMSA, post-reset verification | `V1UGS35H.75-14-9-3-1-4` |

The second is the build that was actually running when the device was verified stable, and it matches the `ro.build.fingerprint` captured after the reset. The first is the OTA *package* version that was downloading. They are not contradictory — one is the update payload, the other is the installed build — but they are easy to confuse, so both are recorded here.

**Android 14 baseline:** `motorola/fogos_gpn/fogos:14/U1UG34.23-110-35/a1cf4-d651b9:user/release-keys`
**Baseband (unchanged across the incident):** `M6375_HI434_03.562.01.98R FOGOS_PVT_APEM2DSDS_CUST`

The crash signature was **byte-for-byte identical** on both Android versions. That is the strongest single piece of evidence that the OS version was irrelevant.

---

## Next

- What to actually do, ranked, with the cost of each: [`04-fixes.md`](04-fixes.md)
- Protect your data before wiping: [`06-backup.md`](06-backup.md)
