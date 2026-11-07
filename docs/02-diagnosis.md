# 02 — Diagnosis: collecting proof

Goal: decide **within a few boots** whether you have the `qcrilNrd` / `libmotext_inf.so` bug, and capture enough evidence to keep after the phone is wiped.

---

## 0. Maximise the boot window (do this first)

The phone only stays up 1.5–3 minutes. Do not spend that window unlocking.

1. **Remove the screen lock temporarily:** Settings → Security → **Screen lock → None**.
   With a PIN/pattern, `/data` stays encrypted until you unlock, so ADB is unusable for part of every boot.
2. **Developer options → Stay awake** (screen stays on while charging).
3. Plug in USB, tick **"Always allow from this computer"**, tap **Allow**.
4. Verify `adb devices` says `device` (not `unauthorized`).

> **Security:** a phone with no lock is open to anyone. Do this only while you are at the PC and restore the lock after recovery.
> **FRP still applies:** you will need the Google account password after the reset regardless.
> **The reset undoes this:** a factory reset wipes the ADB key and turns USB debugging off. Re-enable both after setup.

Full rationale and caveats: [`00-requirements.md`](00-requirements.md#why-remove-the-screen-lock-and-the-catch).

---

## 1. Get ADB working

You need `adb` on a PC and **USB debugging already enabled** on the phone. If it was never enabled, see [the workaround](#if-usb-debugging-is-not-enabled) at the bottom. Full setup and driver troubleshooting: [`00-requirements.md`](00-requirements.md#install-adb).

### Windows

1. Download **Android SDK Platform-Tools** (Google) and unzip, e.g. to `C:\platform-tools`.
2. Add that folder to `PATH`, or call `adb.exe` by full path.
3. Install the Motorola/Google USB driver if the device shows as unknown. On Windows 10/11 the generic ADB driver usually works.

```powershell
$env:ADB = "C:\platform-tools\adb.exe"
& $env:ADB version
& $env:ADB devices
```

Expected:

```
List of devices attached
<DEVICE_SERIAL>   device
```

`unauthorized` → unlock the phone and tap **Allow**. `offline` → replug the cable. Nothing → try another cable/port (USB 2.0 ports are more reliable than hubs).

### Linux / macOS

```bash
# Debian/Ubuntu
sudo apt install android-tools-adb
# macOS
brew install android-platform-tools

adb devices
```

On Linux you may need a udev rule for the Motorola vendor ID (`22b8`).

### The two-minute problem

The device only stays up ~2 minutes. Practical tricks:

- **Remove the screen lock** (Settings → Security → Screen lock → **None**). With a PIN, `/data` stays encrypted until unlock, so ADB is unusable for part of every boot.
- **Tick "Always allow from this computer"** so you are not asked to authorize on every reboot.
- **Enable Developer options → Stay awake** so the screen does not sleep and re-lock.
- Start `adb wait-for-device` **before** the phone finishes booting; it attaches the instant ADB comes up.
- Keep the screen awake: `adb shell svc power stayon usb`.
- Run one script that grabs everything at once, rather than typing commands by hand.
- If the loop is faster than you can type, pull the tombstones from `/data/tombstones` instead of trying to catch `logcat` live — they persist across reboots until the wipe.

Restore the screen lock after you are done. Full rationale: [`00-requirements.md`](00-requirements.md#why-remove-the-screen-lock-and-the-catch).

---

## 2. The five commands that identify this bug

```bash
# uptime in seconds — is this boot only 40 s old?
adb shell 'cat /proc/uptime'

# why did the previous boot end?
adb shell getprop ro.boot.bootreason

# count RIL crashes in the crash ring buffer
adb shell 'logcat -d -b crash | grep -c qcrilNrd'

# full crash record
adb shell logcat -d -b crash > crash.txt

# is the radio even up?
adb shell getprop gsm.sim.state
adb shell getprop gsm.network.type
```

Interpretation:

| Output | Meaning |
|---|---|
| uptime < 200 s, repeatedly | You are in a reboot loop, not a slow boot |
| `watchdog` | `system_server` was blocked > ~60 s — consistent with a wedged RIL |
| `qcrilNrd` count > 0 | The RIL daemon is crashing |
| `NOT_READY,NOT_READY` | Modem never registered |
| `Active default network: none` | No usable network for apps |

---

## 3. Reading the tombstone

Android writes native crashes to `/data/tombstones/tombstone_NN`. They survive reboots (until a wipe), which makes them the best evidence you can keep.

```bash
adb shell ls -l /data/tombstones/
adb pull /data/tombstones/tombstone_00
```

You will see something like:

```
pid: 1234, tid: 1300, name: qcrilNrd  >>> /vendor/bin/hw/qcrilNrd <<<
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0xffffffffffffff02
Cause: null pointer dereference
    x0  0000000000000000  x1  0000000000000000  ...
backtrace:
      #00 pc 00000000000b2c40  /vendor/lib64/libqcrilNr.so (qcril_qmi_oem_free_and_convert_ril_token_to_oem_token+56)
      #01 pc 00000000000b8f10  /vendor/lib64/libqcrilNr.so (qcril_qmi_oemhook_agent_send+172)
      #02 pc 00000000000b1a2c  /vendor/lib64/libqcrilNr.so (mot_qcril_qmi_oemhook_agent_send+52)
      #03 pc 000000000004dabc  /vendor/lib64/libmotext_inf.so (communicationThread+1244)
      #04 pc 00000000000a1f30  /system/lib64/libc.so (__pthread_start+208)
      #05 pc 00000000000a02e4  /system/lib64/libc.so (__start_thread+68)
```

How to read it:

- `fault addr 0xffffffffffffff02` — `0x...FF02` is not a real address. It is the classic pattern of a **poisoned/freed pointer** (glibc/QNX-style `-254` fill) or a small negative offset added to `NULL`. The library is dereferencing something it already freed.
- `libmotext_inf.so` — Motorola's "motext" oemhook client. **Proprietary, closed source.** You cannot patch it without reverse engineering, and even then the vendor partition is signed.
- `qcril_qmi_oemhook_agent_send` — the send path. The modem (or a client app) sent an oemhook message, and the token bookkeeping for it was already stale.

The crash is in **vendor** code, but the trigger is **state**, not the code path itself. That distinction is the whole reason the fix is "wipe the state" rather than "patch the bug".

---

## 4. Capture everything before you wipe

Run the collector script (it takes ~20 s):

```powershell
.\scripts\adb\collect-evidence.ps1 -OutDir .\capture
```

or manually:

```bash
mkdir -p capture
adb shell getprop                > capture/props.txt
adb shell settings list global   > capture/settings-global.txt
adb shell settings list system   > capture/settings-system.txt
adb shell pm list packages -d    > capture/disabled-packages.txt
adb shell dumpsys connectivity   > capture/connectivity.txt
adb shell dumpsys telephony.registry > capture/telephony.txt
adb shell logcat -d -b crash     > capture/crash.txt
adb shell logcat -d -b radio     > capture/radio.txt
adb shell dmesg                  > capture/dmesg.txt
adb shell 'ls -l /data/tombstones' > capture/tombstones.txt
adb pull /data/tombstones capture/tombstones/
adb bugreport capture/bugreport.zip
```

`adb bugreport` can take a few minutes — start it immediately after boot and let it run. If the phone reboots mid-way, you still get a partial zip; retry once.

> **Before sharing any of this publicly:** `props.txt` contains `ro.serialno`, `ro.boot.serialno`, your IMEI-adjacent props, and your SIM operator names. `dumpsys telephony` can contain your phone number. See [`../PRIVACY.md`](../PRIVACY.md).

---

## 5. Watch the boot sequence live

If you want to see the failure happen rather than infer it:

```bash
adb logcat -b all -v threadtime | findstr /i "qcrilNrd watchdog system_server WifiSelfRecovery"
```

```bash
# Linux/macOS
adb logcat -b all -v threadtime | grep -Ei "qcrilNrd|watchdog|system_server|WifiSelfRecovery"
```

What you will see, in order:

1. `qcrilNrd` starts, registers with `qcril` framework.
2. Modem sends unsolicited indications → `communicationThread` processes them.
3. `F DEBUG: signal 11` / `libmotext_inf.so` in the tombstone.
4. `qcrilNrd` restarts; the framework reconnects; another crash ~8 s later.
5. After ~60 s of blocked Binder calls, `Watchdog: *** WATCHDOG KILLING SYSTEM PROCESS ***`.
6. Kernel panics or reboots; `ro.boot.bootreason=watchdog` on the next boot.

That sequence — *crash, retry, watchdog, reboot* — is the disease. Everything else (no Wi-Fi, no SIM, "no internet") is downstream.

---

## 6. Why Wi-Fi and SIM both fail

This confuses people, because it looks like two separate hardware faults. It is one:

- `system_server` never gets a stable boot, so the **Wi-Fi HAL** never completes initialisation (`WifiSelfRecovery: WifiNative Failure`, no `wlan0`, `cnss-daemon: Failed to get WLAN MAC address`).
- The **modem** never registers because `qcrilNrd` keeps dying before registration completes (`gsm.sim.state=NOT_READY`).
- With neither up, `Active default network: none`, so every app says "no internet".

Proof that the hardware is fine: earlier the same day both SIMs were registered on LTE, and the phone was stable in recovery.

---

## If USB debugging is not enabled

This is the hard case. You cannot enable it without booting Android, and you cannot boot Android reliably.

Options, best first:

1. **Boot far enough to toggle it.** Some loops give 60–90 s of usable UI. Try: boot → immediately open Settings → About phone → tap *Build number* 7× → Developer options → USB debugging. Have the cable already connected and `adb devices` running on the PC.
2. **Safe mode** (hold Volume Down during boot / long-press Power → Safe mode). If safe mode is stable, enable USB debugging there, then reboot.
3. **Recovery ADB.** Stock recovery on Motorola exposes `adb sideload` only — no shell, no logcat. Not useful for diagnosis, but useful for applying a signed OTA.
4. **`fastboot` works without USB debugging** (bootloader unlocked or not, `fastboot devices` sees the device in bootloader mode). You cannot read logs this way, but you *can* reflash stock firmware — see [`04-fixes.md`](04-fixes.md#fix-3-fastboot-stock-firmware-reflash-advanced).
5. **Factory reset from recovery anyway.** You lose the ability to capture evidence, but the fix does not require ADB. Back up what you can via MTP first ([`06-backup.md`](06-backup.md)).

---

## Next

- Root cause and the exact trigger: [`03-root-cause.md`](03-root-cause.md)
- Fixes, ranked, with what each one destroys: [`04-fixes.md`](04-fixes.md)
