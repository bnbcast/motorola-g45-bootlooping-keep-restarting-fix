# 09 — FAQ

Answers to the questions that come up repeatedly. Technical detail lives in the linked docs.

---

### Can the bootloop come back?

**Yes, in principle.** The bug is still in `libmotext_inf.so`; only the *trigger* was cleared. Observed risk after a clean reset is **low** (the reference device was stable across multiple reboots and days), but it is not zero. See [recurrence](03-root-cause.md#why-the-bug-can-come-back).

### Does updating to Android 15 fix it?

**No.** The crash signature was byte-for-byte identical on Android 14 (`U1UG34.23-110-35`) and Android 15 (`V1UGS35H.75-14-9-3-1-4`). The faulty library is in the **vendor** partition and was not changed by the update.

### Does the official OTA fix it?

**No.** It replaces system images and preserves userdata — the exact combination that keeps the trigger. This incident included a 1.97 GB Android 15 OTA attempt that did not help.

### Why did the factory reset work if it does not touch modem NVRAM?

Because the trigger was most likely **AP-side telephony state in `/data`** (`/data/vendor/radio`, `telephony.db`, carrier overrides), not the modem's own NVRAM partitions. A recovery reset wipes the former and leaves the latter. The original field notes called it "cleared modem NVRAM"; that is a useful shorthand but not literally what a factory reset does. Full explanation: [`03-root-cause.md`](03-root-cause.md#the-trigger-stale-state-not-a-bad-binary).

### I flashed the latest firmware / security patch and it still loops. Why?

Because flashing replaces **images**, and this bug lives in **state**. On the reference device three separate images were tried — the Android 15 update, the latest full firmware via Motorola/Lenovo Software Fix, and the newest security-patch build (`…-9-13`) — and all three looped with the identical signature. The vendor library is the same in all of them, and userdata (where the trigger lives) was preserved. Wipe userdata.

### Do I really need to remove my screen lock?

For the **recovery window**, yes — it is the difference between having 2 minutes of usable ADB and having almost none. With a PIN/pattern, `/data` stays encrypted until you unlock, so ADB is unusable for part of every boot, and you have to unlock again after each reboot. Set it to **None** while you work, then restore it afterwards. Removing the lock does **not** bypass FRP — you still need the Google account password after the reset. See [`00-requirements.md`](00-requirements.md#why-remove-the-screen-lock-and-the-catch).

### Why "Always allow from this computer"?

It stores your PC's ADB key in `/data/misc/adb/adb_keys`, so you are not asked to tap **Allow** on every reboot. With a 1.5–3 minute window, a single missed prompt can cost you an entire boot. Note that a factory reset wipes those keys and turns USB debugging off — re-enable both after setup.

### Will a factory reset always fix it?

**Not always.** It worked here. If it does not work, the next step is a full firmware flash with a wipe (LMSA with factory reset, or `fastboot`), then service. See [`04-fixes.md`](04-fixes.md).

### Is it a hardware fault?

**No evidence of that here.** The phone was stable in recovery, both SIMs had worked hours earlier, and the crash was a userspace `SIGSEGV` in a vendor library. Hardware becomes the suspect only if the loop persists on clean stock firmware, or if it also loops in recovery/bootloader.

### Is my phone under warranty? Should I use the service centre?

If it is under warranty and you are uncomfortable wiping it, **use the service centre first** — a reset is free but irreversible for data. If the reset does not fix it, warranty repair is the right path. Opening the device yourself voids warranty.

### Can I fix it without losing my data?

**Realistically, no.** The evidence points at userdata state. The "keep my data" flash was tried and failed. Back up, then wipe. Anyone promising a data-preserving fix for this signature is guessing.

### Why does it reboot after exactly ~2 minutes?

`qcrilNrd` crashes roughly every 8 seconds. Each crash leaves `system_server` waiting on a Binder transaction that will never complete. Android's watchdog allows about **60 seconds** of no progress before killing the system. Crash, retry, watchdog, reboot — hence the metronome.

### Why is my SIM state `ABSENT,LOADED`?

That is a **dual-SIM** device reporting slot 0 empty and slot 1 loaded. It is normal if you have one SIM in the second slot. It is **not** an error. `NOT_READY,NOT_READY` is the broken state.

### Why does Wi-Fi say "Failed to get WLAN MAC address"?

Because the Wi-Fi HAL never finished initialising — a downstream effect of `system_server` never getting a stable boot. It is not a broken Wi-Fi chip. It came back by itself after the reset.

### Does safe mode help?

Safe mode rules out third-party apps. Here the phone **still looped in safe mode**, which is why the cause was pinned on system/vendor components rather than an installed app. If your phone is stable in safe mode, your problem is probably an app, not this bug.

### Do the 13 package disables fix it?

**No.** They reduced crashes from ~14 per boot to ~2 by removing oemhook *clients*. The modem still sends unsolicited indications. After the factory reset, all 13 were re-enabled and the phone stayed stable — proof they were never the cause.

### Does airplane mode fix it?

It **suppresses** it: no radio, no `RegRAT`/`UpdateOperator`/`DataState` events, so the buggy path is not entered. That is a workaround for backing up, not a repair. You cannot live in airplane mode.

### Does the LMSA "no factory delete" option ever help?

It can help for other problems (corrupt system image, failed OTA) where userdata is fine. It **cannot** help here, because it preserves the state that triggers the crash. If you use LMSA, choose the wipe option.

### I have an eSIM. Will I lose it?

A factory reset removes eSIM profiles from the device. You will need the carrier's activation QR code or app to re-add it. Contact the carrier **before** wiping if you are not sure you have the profile.

### Can I root and patch the library?

Technically possible, practically a bad idea: the vendor partition is verified, patching breaks OTA and possibly Play Integrity, and the bug is dormant after the reset. See [what not to do](04-fixes.md#what-not-to-do).

### Can I install LineageOS / a custom ROM?

Only with an unlockable bootloader. Motorola bootloader unlocking is region- and model-dependent and voids warranty. A custom ROM would replace the vendor stack entirely — which *would* remove the bug, but also the camera processing, VoLTE on some carriers, and OTA. Not a first-line fix.

### Is gnirehtet safe?

It is a well-known open-source tool from Genymobile. It creates a VPN interface on the phone and relays TCP through your PC over USB. It does not modify system partitions. Read the source if you want; it is small. See [`07`](07-internet-without-wifi-or-sim.md).

### Why "gnirehtet" and not just USB tethering?

USB tethering shares the **phone's** internet with the PC. Here the phone had no internet at all. gnirehtet does the reverse: it shares the **PC's** internet with the phone.

### My phone says "no internet" but curl works. Why?

gnirehtet relays TCP. Play Services validates connectivity using UDP/QUIC, so it may report no connection even while HTTP works. Use web versions of services, or ignore the warning. See [the catch](07-internet-without-wifi-or-sim.md#the-catch-tcp-not-everything).

### Can I enable USB debugging if the phone will not boot?

Sometimes: the loop leaves 60–90 s of usable UI per boot. Settings → About phone → tap *Build number* 7× → Developer options → USB debugging. If that is impossible, `fastboot` still works without it, and a factory reset from recovery does not need it. See [this section](02-diagnosis.md#if-usb-debugging-is-not-enabled).

### Does this affect other Moto G45 units?

Unknown. This is one device, one report. The bug is in a Motorola vendor library common to `fogos`, so other units *could* hit it, but the trigger (stale telephony state) may be rare. If you have the same backtrace, open an issue with your build fingerprint.

### Does it affect other Motorola/Qualcomm phones?

Possibly. `libmotext_inf.so` and the oemhook agent exist on other Motorola Qualcomm devices. The *mechanism* (oemhook token use-after-free → RIL crash → watchdog reboot) could occur elsewhere. The diagnostic method in [`02`](02-diagnosis.md) is generic.

### How do I report this to Motorola?

Use the official support channel and include: model `XT2363-9`, codename `fogos`, build fingerprint, baseband version, the `libmotext_inf.so` backtrace, and the fact that a factory reset resolves it. Do not include your serial/IMEI publicly.

### Is my data safe in this repository?

Yes — nothing from the phone is published except sanitised logs. WhatsApp backups were excluded entirely. See [`PRIVACY.md`](../PRIVACY.md).

### Why are there two Android 15 build numbers in the docs?

One is the OTA payload version that was downloading; the other is the installed build after the LMSA flash. Explained in [`03`](03-root-cause.md#build-numbers-in-this-report).

### Something here is wrong / I have a correction

Open an issue. Include evidence. Corrections to the root-cause section are especially welcome — the exact state that poisoned the token table is inferred, not proven.
