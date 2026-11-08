# 09 — FAQ

Answers to the questions that come up repeatedly. Technical detail lives in the linked docs.

---

### Can the bootloop come back?

**Depends on why the NV corrupted.** The confirmed fix rebuilds the modem's NV from `fsg`.
If the corruption was a one-off (interrupted write, power loss), it should not return. If the
storage block holding `modemst` is failing, it will — and the same two `erase` commands will
fix it again, each time. See [recurrence](12-confirmed-fix-nv-repair.md#recurrence).

### What actually fixed it?

**Erasing `modemst1` and `modemst2`** with an unlocked bootloader, so the modem rebuilt its NV
database from `fsg`. Not a factory reset — that only held for ~3 hours. See
[`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md).

### Does updating to Android 15 fix it?

**No.** The crash signature was byte-for-byte identical on Android 14 (`U1UG34.23-110-35`) and Android 15 (`V1UGS35H.75-14-9-3-1-4`). The fault is in the modem's NV data, which no update rewrites.

### Does the official OTA fix it?

**No.** An OTA replaces system and vendor images. It never writes `modemst1`/`modemst2`, so corrupt modem NV survives it. This incident included a 1.97 GB Android 15 OTA attempt that did not help.

### Why did the factory reset appear to work if it does not touch modem NVRAM?

Because it **didn't** really work — it delayed the failure. On the reference device the loop
stopped for about **three hours** and then returned. A reset re-provisions the modem stack on
first boot, which temporarily masks corrupt NV, but it never touches `modemst1/2`, so the
fault survives. The real fix is
[erasing those two partitions](12-confirmed-fix-nv-repair.md).

### I flashed the latest firmware / security patch and it still loops. Why?

Because the fault is in the modem's **NV data**, not in any image. Firmware flashes replace
`boot`, `vendor`, `super` and sometimes `radio` — none of which is `modemst1`/`modemst2`. On
the reference device three separate images were tried and all three looped with the identical
signature. The fix is [erasing the NV stores](12-confirmed-fix-nv-repair.md).

### Do I really need to remove my screen lock?

For the **recovery window**, yes — it is the difference between having 2 minutes of usable ADB and having almost none. With a PIN/pattern, `/data` stays encrypted until you unlock, so ADB is unusable for part of every boot, and you have to unlock again after each reboot. Set it to **None** while you work, then restore it afterwards. Removing the lock does **not** bypass FRP — you still need the Google account password after the reset. See [`00-requirements.md`](00-requirements.md#why-remove-the-screen-lock-and-the-catch).

### Why "Always allow from this computer"?

It stores your PC's ADB key in `/data/misc/adb/adb_keys`, so you are not asked to tap **Allow** on every reboot. With a 1.5–3 minute window, a single missed prompt can cost you an entire boot. Note that a factory reset wipes those keys and turns USB debugging off — re-enable both after setup.

### Will a factory reset fix it?

**No.** It stopped the loop for about three hours on the reference device, then the loop
returned. A reset cannot fix corrupt modem NV because it does not touch `modemst1/2`. It is
still useful for clearing your data and buying a stable window to back up. See
[`04-fixes.md`](04-fixes.md).

### Is it a hardware fault?

**Not necessarily — and on the reference device it was not.** The cause was corrupt modem
**NV data**, fixed by erasing `modemst1`/`modemst2`. The crash was a userspace `SIGSEGV`, but
it was caused by the modem asserting underneath it.

Hardware becomes the suspect only if the NV erase **and** a `radio.img` reflash both fail, or
if the modem crash counter climbs again shortly after every repair. In that case the likely
candidates are the UFS/eMMC block holding `modemst`, the modem DSP, or the PMIC rail.

### Can I fix it without unlocking the bootloader?

**No.** `fastboot erase modemst1/modemst2` is refused while the bootloader is locked. The
unlock is what makes the repair possible. Motorola only unlocks retail units — see
[unlocking](12-confirmed-fix-nv-repair.md#unlocking-the-bootloader).

### What do I lose by unlocking the bootloader?

- **All data** — the unlock wipes the device.
- **Warranty** — it is void.
- **Verified boot** — `verifiedbootstate` becomes `orange` instead of `green`.
- **Some apps** — Play Integrity / banking apps and Google Wallet may refuse to run.
- **Widevine** — may drop from L1 to L3, capping streaming at SD.

What you do **not** lose: the IMEI (the NV rebuild restores it from `fsg`), OTA updates on a stock ROM, or the ability to use the phone normally.

### Can I relock the bootloader afterwards?

**Do not**, unless you have fully restored a stock, signed boot chain. Relocking a device with a modified or non-stock boot image **hard-bricks** it. On the reference device the bootloader stayed unlocked, which is the normal state after this repair.

### Is my phone under warranty? Should I use the service centre?

If it is under warranty and you are uncomfortable wiping it, **use the service centre first** — a factory reset is free but irreversible for data, and it will not fix corrupt modem NV anyway. If the repair is not an option for you, warranty service is the right path. Opening the device yourself voids warranty.

Note that **unlocking the bootloader voids the warranty**. On the reference device the warranty had already expired, which is why unlocking was acceptable.

### Can I fix it without losing my data?

**No.** The repair is an NV erase, and the unlock that makes it possible wipes the device.
Back up first, then repair. Anyone promising a data-preserving fix for this signature is
guessing.

### Why does it reboot after exactly ~2 minutes?

`qcrilNrd` crashes roughly every 8 seconds. Each crash leaves `system_server` waiting on a Binder transaction that will never complete. Android's watchdog allows about **60 seconds** of no progress before killing the system. Crash, retry, watchdog, reboot — hence the metronome.

### Why is my SIM state `ABSENT,LOADED`?

That is a **dual-SIM** device reporting slot 0 empty and slot 1 loaded. It is normal if you have one SIM in the second slot. It is **not** an error. `NOT_READY,NOT_READY` is the broken state.

### Why does Wi-Fi say "Failed to get WLAN MAC address"?

Because the Wi-Fi HAL never finished initialising — a downstream effect of `system_server` never getting a stable boot. It is not a broken Wi-Fi chip. It came back by itself after the modem NV repair.

### Does safe mode help?

Safe mode rules out third-party apps. Here the phone **still looped in safe mode**, which is why the cause was pinned on system/vendor components rather than an installed app. If your phone is stable in safe mode, your problem is probably an app, not this bug.

### Do the 13 package disables fix it?

**No.** They reduced crashes from ~14 per boot to ~2 by removing oemhook *clients*. The modem still asserts on its own. After the NV repair, all 13 were re-enabled and the phone stayed stable — proof they were never the cause.

### Does airplane mode fix it?

It **suppresses** it: no radio, no `RegRAT`/`UpdateOperator`/`DataState` events, so the buggy path is not entered. That is a workaround for backing up, not a repair. You cannot live in airplane mode.

### Does the LMSA "no factory delete" option ever help?

It can help for other problems (corrupt system image, failed OTA) where userdata is fine. It **cannot** help here: it never writes `modemst1`/`modemst2`, so corrupt modem NV survives it. If you use LMSA, still choose the wipe option, but do not expect it to repair this fault.

### I have an eSIM. Will I lose it?

A factory reset removes eSIM profiles from the device. You will need the carrier's activation QR code or app to re-add it. Contact the carrier **before** wiping if you are not sure you have the profile.

### Can I root and patch the library?

Technically possible, practically a bad idea: the vendor partition is verified, patching breaks OTA and possibly Play Integrity — and it treats a symptom. The `qcrilNrd` crash happens because the modem is already gone; patching the library gives you a phone that boots with no cellular. See [what not to do](04-fixes.md#what-not-to-do).

### Can I install LineageOS / AxionOS / a custom ROM to fix it?

**It will not fix the modem.** A custom ROM flashes `boot`, `vendor_boot`, `dtbo` and
`super` — it cannot reach `modemst1/2`, and it reuses Motorola's vendor blobs. If the modem is
asserting, you get a phone that boots to the home screen with **"No service"** instead of a
bootloop. That is a usability fallback, not a repair — and it needs the same bootloader unlock
the real fix needs. Do the [NV repair](12-confirmed-fix-nv-repair.md) first.

### Is gnirehtet safe?

It is a well-known open-source tool from Genymobile. It creates a VPN interface on the phone and relays TCP through your PC over USB. It does not modify system partitions. Read the source if you want; it is small. See [`07`](07-internet-without-wifi-or-sim.md).

### Why "gnirehtet" and not just USB tethering?

USB tethering shares the **phone's** internet with the PC. Here the phone had no internet at all. gnirehtet does the reverse: it shares the **PC's** internet with the phone.

### My phone says "no internet" but curl works. Why?

gnirehtet relays TCP. Play Services validates connectivity using UDP/QUIC, so it may report no connection even while HTTP works. Use web versions of services, or ignore the warning. See [the catch](07-internet-without-wifi-or-sim.md#the-catch-tcp-not-everything).

### Can I enable USB debugging if the phone will not boot?

Sometimes: the loop leaves 60–90 s of usable UI per boot. Settings → About phone → tap *Build number* 7× → Developer options → USB debugging. If that is impossible, `fastboot` still works without it — and the NV repair needs only `fastboot`, not ADB. See [this section](02-diagnosis.md#if-usb-debugging-is-not-enabled).

### Does this affect other Moto G45 units?

Unknown. This is one device, one report. The bug is in a Motorola vendor library common to `fogos`, so other units *could* hit it, but the trigger (stale telephony state) may be rare. If you have the same backtrace, open an issue with your build fingerprint.

### Does it affect other Motorola/Qualcomm phones?

Possibly. `libmotext_inf.so` and the oemhook agent exist on other Motorola Qualcomm devices. The *mechanism* (oemhook token use-after-free → RIL crash → watchdog reboot) could occur elsewhere. The diagnostic method in [`02`](02-diagnosis.md) is generic.

### How do I report this to Motorola?

Use the official support channel and include: model `XT2363-9`, codename `fogos`, build fingerprint, baseband version, the `libmotext_inf.so` backtrace, the fact that `subsys2` (modem) keeps asserting, and that erasing `modemst1`/`modemst2` fixed it. Do not include your serial/IMEI publicly.

### Is my data safe in this repository?

Yes — nothing from the phone is published except sanitised logs. WhatsApp backups were excluded entirely. See [`PRIVACY.md`](../PRIVACY.md).

### Why are there two Android 15 build numbers in the docs?

One is the OTA payload version that was downloading; the other is the installed build after the LMSA flash. Explained in [`03`](03-root-cause.md#build-numbers-in-this-report).

### Something here is wrong / I have a correction

Open an issue. Include evidence. Corrections to the root-cause section are especially welcome — the exact state that poisoned the token table is inferred, not proven.
