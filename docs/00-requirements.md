# 00 — What you need before you start

Read this first. Most failed recoveries are not failed *fixes* — they are missing cables, missing drivers, or a phone that cannot be reached because USB debugging was never enabled.

---

## The minimum kit

| You need | Why | Notes |
|---|---|---|
| **A Windows PC or laptop** | LMSA / Software Fix is Windows-only, and every script here is PowerShell | Windows 10 or 11, 64-bit. Linux/macOS can do the ADB parts, but **not** the Motorola firmware flash |
| **A USB *data* cable** | Charge-only cables cannot carry ADB | The single most common cause of "`adb devices` shows nothing". Try 2–3 cables before blaming the phone |
| **ADB installed** | Every diagnostic and most fixes use it | Android SDK **Platform-Tools** (includes `adb` and `fastboot`). See [install steps](#install-adb) |
| **A working USB port, directly on the PC** | Hubs and front-panel ports drop connections mid-flash | Prefer a rear USB 2.0 port for flashing. No hub, no dock, no extension cable |
| **Internet on the PC** | Downloads: Platform-Tools, gnirehtet, 2–5 GB of firmware | 10 Mbps+ recommended. The phone's own internet may be broken — that is the point |
| **30–60 GB free disk space** | Backups + firmware + LMSA cache | Photos/videos alone can be tens of GB |
| **Admin rights on the PC** | Installing USB drivers and LMSA | A locked-down work laptop may block both |
| **The phone charged above 50 %** | First boot after a reset can take 15 minutes | Keep it on the charger for the whole procedure |
| **Time: 2–4 hours** | Downloads, backup, reset, first boot, verification | Most of it is waiting |

---

## Phone prerequisites

| Requirement | How to check | If missing |
|---|---|---|
| **USB debugging enabled, "Always allow" ticked** | Settings → About phone → tap *Build number* 7× → Developer options → USB debugging. Plug in, unlock, tick **"Always allow from this computer"**, tap **Allow** | If the phone cannot stay up long enough, see [the workaround](02-diagnosis.md#if-usb-debugging-is-not-enabled). Without it, ADB, gnirehtet and evidence collection are impossible |
| **Screen lock removed (temporarily)** | Settings → Security → **Screen lock → None** | With a PIN/pattern, `/data` stays encrypted until you unlock, so ADB is unusable for the first part of every boot. That can eat the entire 1.5–3 minute window |
| **"Stay awake" enabled** | Developer options → **Stay awake** (screen on while charging) | The screen sleeps, you unlock again, and the window is gone |
| **Bootloader reachable** | Power off → hold **Power + Volume Down** | If this does not work, stop and use the service centre |
| **Recovery reachable** | Bootloader menu → *Recovery mode* | Same |
| **Google account password known** | — | Factory Reset Protection will ask for the last synced account. Removing the screen lock does **not** bypass FRP |
| **SIM available, able to receive SMS** | — | Needed to reactivate WhatsApp and to test LTE after the fix |
| **A way to read this guide while the phone is down** | Second screen, phone, or printout | You will be rebooting the only device you might be reading on |

### Why remove the screen lock? (and the catch)

The reboot interval is the scarce resource. Every second spent unlocking is a second not spent pulling files or running commands.

- With a **secure lock** (PIN/pattern/password), Android uses file-based encryption: `adbd` may come up, but `/data` is not decrypted until you unlock. `adb devices` can sit at `unauthorized` or shell commands fail. You then have to unlock *again* after every reboot.
- With **no lock**, the phone boots straight to a usable state, the ADB key is already trusted ("Always allow"), and your script can start the moment `adb devices` shows `device`.

**Steps:**

1. Settings → **Security** → **Screen lock** → enter your current PIN → choose **None**.
   (Motorola: *Settings → Security → Screen lock*. Some builds: *Security & privacy → Device unlock*.)
2. Settings → **Developer options** → enable **Stay awake**.
3. Plug in USB, unlock once if asked, tick **"Always allow from this computer"**, tap **Allow**.
4. Verify: `adb devices` shows `device`, not `unauthorized`.

**Catch 1 — physical security.** A phone with no lock is open to anyone who picks it up. Do this only while you are at the PC, keep the phone with you, and **set a lock again after the recovery**.

**Catch 2 — FRP is not bypassed.** Removing the lock does not remove Factory Reset Protection. After the reset you will still need the **Google account password** that was on the device.

**Catch 3 — the reset undoes it.** A factory reset wipes `/data/misc/adb/adb_keys` and turns USB debugging **off**. After setup you must re-enable Developer options → USB debugging and re-authorize the PC. Plan for that before you need it for verification.

**Catch 4 — some apps refuse.** Banking and work-profile apps may refuse to run without a secure lock. That is temporary; restore the lock afterwards.


> **Root is not required.** Neither is an unlocked bootloader. The documented fix works on a stock, locked device.

---

## Accounts and secrets you must have

These are the things people discover they are missing *after* the wipe:

- [ ] **Google account password** (FRP + restoring contacts/apps)
- [ ] **Screen lock PIN / pattern / password**
- [ ] **WhatsApp number** and the **same Google account** used for its Drive backup
- [ ] **WhatsApp 64-digit encryption key**, if end-to-end encrypted backup is enabled (otherwise the backup is unrecoverable)
- [ ] **2FA authenticator seeds exported** — not just installed. A wiped phone with no exported seeds can lock you out of everything
- [ ] **Password manager recovery kit** or master password
- [ ] **eSIM activation QR code / carrier app login** if you use eSIM
- [ ] **Banking app reactivation info** — some banks require a branch visit after a device change
- [ ] **Carrier account PIN** if you may need to re-provision the SIM

See [`06-backup.md`](06-backup.md) for how to export each one.

---

## Software you will install

| Software | Required? | Purpose | Size |
|---|---|---|---|
| **Android SDK Platform-Tools** | ✅ Yes | `adb`, `fastboot` | ~15 MB |
| **Motorola / Google USB driver** | ✅ Windows | Lets Windows see the phone in ADB and fastboot mode | ~10–30 MB |
| **7-Zip** | Recommended | Extracting firmware and tool zips | ~2 MB |
| **Motorola Rescue and Smart Assistant (LMSA)** | Only if Fix 1 fails | Full firmware flash with a locked bootloader | ~200 MB + 2–5 GB firmware |
| **gnirehtet** | Only if the phone has no Wi-Fi/SIM | Internet over USB while you back up | ~5 MB |
| **Canta + Shizuku** | Optional | No-root debloat UI | ~20 MB |
| **SMS Backup & Restore** (on the phone) | Recommended | SMS/call-log backup | ~10 MB |

You do **not** need: root, a custom recovery, a paid "bootloop fix" tool, or a Linux install.

---

## Install ADB

### Windows

1. Download **SDK Platform-Tools for Windows** from Google (`developer.android.com/tools/releases/platform-tools`).
2. Unzip to a simple path, e.g. `C:\platform-tools`. **Avoid** `C:\Program Files` and paths with spaces.
3. Add it to `PATH`:
   - Start → "Edit the system environment variables" → Environment Variables → *Path* → Edit → New → `C:\platform-tools` → OK.
   - Or just call it by full path: `C:\platform-tools\adb.exe`.
4. Open a **new** PowerShell window and check:

```powershell
adb version
adb devices
```

Expected: a version line, then a header. If `adb` is "not recognized", `PATH` is wrong or you did not reopen the terminal.

5. Install the **Motorola USB driver** (search "Motorola Device Manager" or use the Google USB driver). On Windows 10/11 the generic ADB driver often works without it.

### Linux / macOS

```bash
# Debian/Ubuntu
sudo apt install android-tools-adb android-tools-fastboot

# macOS
brew install android-platform-tools

adb devices
```

On Linux you may need a udev rule for Motorola's vendor ID `22b8`.

---

## Cable and driver troubleshooting

If `adb devices` is empty, work through this in order. Do not skip to "the phone is broken".

| Check | How |
|---|---|
| **Is the cable a data cable?** | Try a cable that you know transfers files. Charge-only cables are extremely common |
| **Is it a hub/dock/extension?** | Plug directly into the PC. Prefer a rear USB 2.0 port |
| **Does Windows see *anything*?** | Device Manager → look for *Android Composite ADB Interface*, *Motorola ADB Interface*, or an unknown device |
| **Is the phone set to file transfer?** | Pull down the notification shade → USB → **File transfer / MTP** |
| **Did you tap Allow?** | Unlock the phone; the "Allow USB debugging?" prompt only appears when unlocked |
| **Did the prompt never appear?** | Developer options → **Revoke USB debugging authorizations**, replug |
| **Stale ADB server?** | `adb kill-server` then `adb start-server` then `adb devices` |
| **Phone shows `unauthorized`** | Unlock and accept the prompt. If it still fails, revoke authorizations and replug |
| **Phone shows `offline`** | Replug, try another port, restart the ADB server |
| **Nothing at all** | Try another PC. If still nothing, the phone's USB port or the cable is the problem |

> **Rule of thumb:** if the phone charges but never asks "Allow USB debugging?", assume the cable or port first, the driver second, the phone last.

---

## Pre-flight checklist

Copy this into your notes and tick it before you wipe anything.

```text
[ ] Windows 10/11 PC with admin rights
[ ] USB data cable (tested with file transfer)
[ ] Direct USB port, no hub
[ ] Platform-Tools downloaded, adb version works
[ ] Motorola/Google USB driver installed
[ ] adb devices lists the phone as "device"
[ ] USB debugging enabled on the phone
[ ] "Always allow from this computer" ticked, RSA prompt accepted
[ ] Screen lock set to None (temporarily) — ADB usable immediately after boot
[ ] Developer options → "Stay awake" enabled
[ ] Bootloader (Power + Volume Down) reachable
[ ] Recovery reachable
[ ] Phone charged > 50 %, on charger
[ ] 30–60 GB free on the PC
[ ] PC internet working
[ ] Google account password known (FRP still applies)
[ ] Screen lock PIN known (to remove the lock, and to restore it later)
[ ] 2FA seeds exported and stored off the phone
[ ] WhatsApp Drive backup done (and 64-digit key saved if enabled)
[ ] Photos/videos/games copied off
[ ] SMS backup done
[ ] eSIM QR code available (if applicable)
[ ] 2–4 hours of uninterrupted time
```

If any box is unticked, fix that before starting the reset. The reset itself takes 5 minutes; the preparation is what protects you.

---

## What you do **not** need

- ❌ Root
- ❌ An unlocked bootloader
- ❌ A custom ROM or custom recovery
- ❌ A paid repair tool
- ❌ A Linux machine
- ❌ Opening the phone
- ❌ A service centre (unless the documented fixes fail)

---

## Next

- Not sure it is this bug? → [`01-symptoms.md`](01-symptoms.md)
- Ready to start? → [`05-tutorial.md`](05-tutorial.md)
- Back up first → [`06-backup.md`](06-backup.md)
