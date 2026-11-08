# 04 — Fixes, ranked

> **Corrected 2026-11-08.** The confirmed fix is now **Fix 1: erase the modem NV**. A factory
> reset does **not** fix this — it held for ~3 hours on the reference device and then the loop
> returned. Full write-up: [`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md).

Ordered by **risk-adjusted success**: start at the top, stop when the phone is stable.

| # | Fix | Effort | Wipes data? | Worked on reference device |
|---|---|---|---|---|
| 0 | Stabilise the device temporarily | 5 min | No | Partial — bought time to back up |
| 1 | **Erase `modemst1` + `modemst2`** (needs unlocked bootloader) | 20–60 min incl. unlock | **Yes** (unlock wipes) | **Yes — permanent, cellular restored** |
| 2 | `fastboot flash radio radio.img` + erase `modemst1/2` | 30–60 min | Yes | Not needed (1 worked) |
| 3 | Factory reset from Recovery | 5 min | **Yes** | **No — loop returned after ~3 hours** |
| 4 | LMSA rescue **with factory reset** | 20–40 min | **Yes** | Not tried after the real cause was known |
| 5 | Full `fastboot` stock reflash (advanced) | 30–60 min | **Yes** | Not needed |
| 6 | Service centre (read `ssrdump`, board repair) | days | — | Not needed |

> **Do the backup first.** [`06-backup.md`](06-backup.md). Fixes 1–4 destroy `/data` irreversibly.
>
> **Before Fix 1, record your IMEI(s).** Dial `*#06#` and write both down. The NV rebuild
> restores them from `fsg`, and you need to be able to prove it afterwards.

---

## Fix 0 — Stabilise it long enough to back up

Not a repair. It slows the crash rate so you have time to copy files.

```bash
adb wait-for-device

# Quiet the radio: fewer oemhook indications, fewer crashes
adb shell settings put global airplane_mode_on 1
adb shell cmd connectivity airplane-mode enable
adb shell settings put global wifi_on 0
adb shell cmd wifi set-wifi-enabled disabled

# Keep the screen on and reduce load
adb shell svc power stayon usb
adb shell settings put system screen_off_timeout 1800000
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell am kill-all
```

Optionally disable the 13 oemhook-heavy packages — this took crashes from ~14 per boot to ~2:

```bash
adb shell pm disable-user --user 0 com.motorola.omadm.service
adb shell pm disable-user --user 0 com.qualcomm.qti.cne
# ... full list: scripts/adb/disable-oemhook-packages.sh
```

Or the whole set at once:

```powershell
.\scripts\adb\disable-oemhook-packages.ps1
```

**Why this is not the fix:** the modem still sends unsolicited indications on its own. You are removing *clients*, not the trigger. It also disables carrier features you may want later (OMADM provisioning, multi-SIM settings, entitlement checks).

**Remember to undo it** after the real fix:

```powershell
.\scripts\adb\reenable-oemhook-packages.ps1
```

**No internet?** The radio is off now. Use USB reverse tethering: [`07-internet-without-wifi-or-sim.md`](07-internet-without-wifi-or-sim.md).

---

## Fix 1 — Erase the modem NV (the confirmed fix)

**This is the repair.** It requires an **unlocked bootloader**, because the bootloader refuses
`erase` on `modemst1/2` while locked. Full detail and evidence:
[`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md).

### Why it works

`modemst1` / `modemst2` hold the modem's NV database (IMEI, RF references, carrier/band
config). If items there are corrupt, the modem asserts on every boot. `fsg` is a golden copy
of the defaults. Erasing the two NV stores makes the modem rebuild them from `fsg`.

### Before you start

- [ ] **IMEI(s) recorded** — dial `*#06#`, write both down
- [ ] `fastboot devices` lists the phone
- [ ] `fastboot getvar all` shows `securestate: flashing_unlocked`

If `securestate` says `flashing_locked`, unlock first — see
[unlocking](12-confirmed-fix-nv-repair.md#unlocking-the-bootloader).

### Steps

```bash
fastboot erase modemst1      # must print OKAY — stop if it fails
fastboot erase modemst2      # must print OKAY — stop if it fails
fastboot reboot
```

First boot takes several minutes while NV is rebuilt.

### Verify

```bash
adb shell getprop gsm.version.baseband                         # must not be empty
adb shell getprop gsm.sim.state                                # LOADED,...
adb shell cat /sys/bus/msm_subsys/devices/subsys2/crash_count   # must stay 0
```

Then dial `*#06#` — the IMEI must be **identical** to what you wrote down.

| Result | Meaning |
|---|---|
| Baseband present, `crash_count` stays `0` | **Repaired** |
| Baseband present, then `crash_count` climbs | Go to Fix 2 |
| Baseband never appears | Go to Fix 2, then Fix 5 |
| **IMEI blank / different** | **Stop.** `fsg` rebuild failed — service centre only |

### Watch it for 30 minutes

One clean boot is not proof. You need `crash_count` to stay at `0` with a SIM in and the
phone idle for at least 30 minutes, then a deliberate reboot with the same result.

```powershell
.\scripts\adb\verify-stability.ps1
```

---

## Fix 2 — Flash the modem firmware, then erase NV again

Only if Fix 1 did not work. Now that the bootloader is unlocked, you can rewrite the modem
image itself.

```bash
fastboot flash radio radio.img     # from an XT2363-9 / fogos package
fastboot erase modemst1
fastboot erase modemst2
fastboot reboot
```

**Only flash `radio`** (and optionally `fsg`). Do **not** flash `gpt.bin`, `bootloader.img`,
`abl`, `xbl` or `tz` from an older package — Motorola's anti-rollback will hard-brick the
device.

---

## Fix 3 — Factory reset (temporary, **not** a fix)

> **This does not fix the bug.** On the reference device the loop stopped for about three
> hours and then returned, because a reset does not touch `modemst1/2`. Keep this section for
> what it is good for: clearing user data, and buying a stable window to back up.

### Before you start

- [ ] Backups done — [`06-backup.md`](06-backup.md)
- [ ] You know your **Google account password** (FRP lock after reset)
- [ ] You know your **screen lock PIN/pattern** (some devices ask for it after reset)
- [ ] SIM cards removed (optional, avoids provisioning churn on first boot)
- [ ] Phone charged > 50 %

### Steps

1. Power off completely.
2. Hold **Power + Volume Down** until the bootloader menu appears.
3. Use Volume keys to select **Recovery mode**, press Power.
4. When the Android robot with "No command" appears, hold **Power**, tap **Volume Up** once, release both. (Motorola stock recovery.)
5. Select **Wipe data/factory reset** → confirm.
6. Select **Wipe cache partition** if present (harmless, sometimes helps).
7. Select **Reboot system now**.

First boot takes 5–15 minutes. Do not interrupt it.

### What this does and does not do

| Does | Does not |
|---|---|
| Wipes `/data`, including `/data/vendor/radio`, telephony DBs, carrier overrides | Touch `/persist`, `modemst1/2`, `fsg` |
| Re-runs first-boot provisioning for the modem stack | Reinstall or repair the vendor library |
| Removes all accounts, apps, photos, messages | Fix the `libmotext_inf.so` bug itself |

The bug is still there. The **trigger** is not. See [`12-confirmed-fix-nv-repair.md`](12-confirmed-fix-nv-repair.md).

### Immediately after boot

**A factory reset turns USB debugging off and wipes the ADB authorization.** Before you can verify anything, re-enable it: Settings → About phone → tap *Build number* 7× → Developer options → USB debugging, then re-authorize the PC.

```bash
adb wait-for-device
adb shell 'cat /proc/uptime'
adb shell 'logcat -d -b crash | grep -c qcrilNrd'   # expect 0
adb shell getprop gsm.sim.state
adb shell getprop gsm.network.type
adb shell 'dumpsys connectivity | grep -m1 "Active default network"'
```

Then leave it alone for **at least 20 minutes**. A reset buys a stable window, not a fix — on the reference device it lasted about three hours before the loop returned.

### Verify properly

```powershell
.\scripts\adb\verify-stability.ps1
```

Criteria: uptime > 600 s, `qcrilNrd` crashes = 0, SIM `LOADED`, default network not `none`. Then **reboot once** and check again — a single clean boot is not proof.

### If it starts looping again after the reset

- **Expected.** A reset cannot repair `modemst1/2`. Go to **Fix 1** — that is the real repair.
- Did you restore a full `/data` backup? Restore **only media/messages**, never `/data/vendor/radio` or `telephony.db` — that state is unrelated to this fault but can cause its own telephony trouble.
- Did the loop start immediately (< 2 min after first boot)? Go to Fix 1, then Fix 2.

---

## Fix 4 — LMSA rescue with "factory reset"

Motorola's **Rescue and Smart Assistant (LMSA)**, formerly "Software Fix", downloads the correct firmware for your exact model and flashes it over USB. It can do this with a locked bootloader.

### Critical: the option matters

LMSA offers a choice between preserving userdata and wiping it. **Choose the wipe / factory-reset option** — the "keep my data" path leaves stale user data behind. But understand that **neither option touches `modemst1/2`**, so LMSA cannot repair corrupt modem NV. It is still the right tool for a genuinely damaged system image.

This was tried on the reference device **three times** with newer and newer images:

> - 2026-11-06 18:00 — LMSA / Software Fix, **latest full firmware**, Android 15 → **bootloop persisted**
> - 2026-11-06 ~19:00 — **latest security-patch build** (`…-9-13`) → **bootloop persisted, identical signature**
> - a factory reset stopped it for about **three hours**, then the loop returned

That is the strongest evidence in this whole report: **if flashing the newest firmware does not fix it, the fault is not in an image.** For this device it was in the modem NV — see [Fix 1](#fix-1--erase-the-modem-nv-the-confirmed-fix).

### Steps

1. Download LMSA from Motorola's support site (search "Rescue and Smart Assistant").
2. Install, launch, sign in if prompted (an account is not always required).
3. Connect the phone via a **good USB data cable**, directly to the PC (no hub).
4. Put the phone in **bootloader/fastboot mode**: power off → hold **Power + Volume Down**.
5. LMSA should detect `XT2363-9` / `fogos`. If it does not, install the Motorola USB driver and retry.
6. Choose **Rescue**.
7. Select the firmware version offered (it will match your model/region).
8. **Select the option that wipes user data / performs a factory reset.** Wording varies by LMSA version — read the checkbox, do not accept the default blindly.
9. Start. It downloads 2–5 GB, then flashes. **Do not unplug** for 15–40 minutes.
10. Let it reboot and complete first-boot setup.

### Why this is still worth trying after Fix 1

It replaces the system, vendor and modem **images**, and wipes userdata. That covers a corrupted image or a damaged system partition. It still cannot repair the modem NV store — so run Fix 1 first, then this if the modem still asserts.

### Warning

- LMSA may install a **newer build** than you had. That is usually fine, but it can also trigger **anti-rollback** — you cannot go back to an older firmware afterwards.
- If LMSA cannot see the device, do not force it with random tools. Go to Fix 3 or the service centre.

---

## Fix 5 — full `fastboot` stock firmware reflash (advanced)

Only if LMSA fails or you are comfortable with fastboot. This is the manual version of Fix 4.

### You need

- The **exact** firmware package for `XT2363-9` / `fogos` / your region (`RET...`, `GPN...` etc.). Wrong-region or wrong-model firmware can hard-brick.
- `platform-tools` (`fastboot`, `adb`).
- A **bootloader that permits flashing**. Motorola bootloaders are usually **locked** and refuse `fastboot flash` unless unlocked. If `fastboot flashing unlock` is unavailable, **stop** — use LMSA (Fix 4) or the service centre.

### Outline

```bash
fastboot devices                     # must list your device
fastboot getvar all                  # record everything (serial, slot, anti-rollback)
fastboot flashing unlock             # ONLY if you accept voiding warranty + data loss
```

Then flash the images from the firmware package **in the order given by its `flashfile.xml` / `servicefile.xml`**, typically:

```bash
fastboot flash boot       boot.img
fastboot flash dtbo       dtbo.img
fastboot flash vbmeta     vbmeta.img
fastboot flash system     system.img_sparsechunk.*
fastboot flash vendor     vendor.img
fastboot flash modem      NON-HLOS.bin
fastboot flash fsg        fsg.mbn
fastboot erase  modemst1             # record IMEI first - see below
fastboot erase  modemst2             # record IMEI first - see below
fastboot erase  userdata
fastboot erase  metadata
fastboot reboot
```

### About `fastboot erase modemst1/modemst2`

> **Corrected 2026-11-08.** This section used to warn you away from these commands. That was
> wrong: they are the **actual fix** (Fix 1). The warning was based on the mistaken belief
> that `/data` was the trigger.
>
> They do carry IMEI data, so the risk is real — but it is manageable:
> **record your IMEI first**, erase, then confirm it is unchanged. The modem rebuilds NV
> from `fsg`, which contains the IMEI.
>
> Only skip them if `fsg` is also suspected damaged. If you erase and the IMEI comes back
> blank, that is a service-centre job.

### Anti-rollback

Motorola devices enforce a rollback index. Flashing an older build than the one on the device can hard-brick. `fastboot getvar` shows the current index; never downgrade.

---

## Fix 6 — Service centre

Go here if:

- Fixes 1–5 all failed and the loop persists on clean stock firmware, **or**
- The phone also loops in **recovery** / bootloader (hardware), **or**
- You erased `modemst` and lost IMEI, **or**
- It is under warranty and you would rather not void it.

Likely hardware suspects in that scenario: modem/PMIC power rail, eMMC/UFS failure, or a failed modem calibration partition. Those are board-level repairs.

---

## What NOT to do

| Bad idea | Why |
|---|---|
| **LMSA "keep my data" / "no factory delete"** | Leaves stale user data behind — and cannot repair `modemst1/2` either way. |
| **Disabling packages and calling it fixed** | Reduces crash *rate*, not the cause. Modem indications are independent of apps. |
| **`fastboot erase modemst1/modemst2` without recording your IMEI first** | It is the correct fix, but the IMEI lives there. Write it down first, confirm it after. |
| **Freezer / heat / "drain the battery" tricks** | Old wives' tales for bootloops; they sometimes work on failing solder, never on a software crash. |
| **"Bootloop fix" APKs / one-click tools from random sites** | Cannot patch a signed vendor library. At best useless, at worst malware. |
| **Flashing a random `fogos` firmware from a forum** | Wrong region/model/rollback index can hard-brick. |
| **Rooting to replace `libmotext_inf.so`** | It is a symptom, not the cause. You would get a phone that boots with no cellular. |
| **Restoring a full `/data` image after the fix** | Not the cause of this loop, but it can reintroduce unrelated telephony state. Restore media and messages only. |

---

## After the fix

1. Verify — [`scripts/adb/verify-stability.ps1`](../scripts/adb/verify-stability.ps1)
2. Restore data **selectively** — [`06-backup.md`](06-backup.md#restoring-safely)
3. Optionally harden/debloat — [`08-hardening.md`](08-hardening.md)
4. Keep an eye on it for a week:

```bash
adb shell 'echo UP=$(cut -d" " -f1 /proc/uptime) CRASH=$(logcat -d -b crash | grep -c qcrilNrd)'
```

If `CRASH` ever climbs above 0 with the same `libmotext_inf.so` backtrace, you are back at [`01-symptoms.md`](01-symptoms.md).
