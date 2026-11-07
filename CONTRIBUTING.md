# Contributing

Corrections and additional data points are welcome. This repo exists because one device's evidence is not a dataset.

---

## Good contributions

- **A matching crash signature** on another `fogos` (or other Motorola Qualcomm) device, with build fingerprint and baseband.
- **A correction** to the root-cause reasoning — especially evidence for or against the `/data/vendor/radio` explanation.
- **A confirmed fix path** that differs from this one, with before/after verification.
- **Script fixes** (PowerShell 5.1 compatibility, macOS/Linux, better error handling).
- **Translation** of the tutorial into another language. (Indonesian already exists: [`README.id.md`](README.id.md) — more are welcome.)

## What to include in a bug report

```text
Model / SKU:        XT2363-9 (or yours)
Codename:           fogos
Build fingerprint:  ro.build.fingerprint
Baseband:           gsm.version.baseband
Android version:
Bootloader state:   locked/unlocked, verified boot green/orange
Crash excerpt:      logcat -d -b crash  (qcrilNrd section only)
What you tried:     factory reset / LMSA / fastboot / package disables
Result:             stable or not, with uptime
```

## What NOT to include

- Serial numbers, IMEI, MEID, ICCID, IMSI, phone number
- Wi-Fi SSIDs/BSSIDs or MAC addresses
- Email addresses, account names, `authuser=` values
- Full `getprop`, full `bugreport`, full `dumpsys telephony`
- Screenshots with notifications, avatars or browser tabs

See [`PRIVACY.md`](PRIVACY.md) for the exact checklist.

---

## Pull requests

1. Keep changes focused.
2. Scripts must not hardcode user paths — use parameters with sane defaults.
3. Test on PowerShell 5.1 (Windows) if you touch `.ps1`.
4. If you add evidence, sanitise it first and add a row to `evidence/README.md`.
5. Do not commit `.crypt*`, `*.log`, `props.txt`, `capture/` or anything in `.gitignore`.
6. If you used AI to write or debug a contribution, that is fine — but say so in the PR, and verify every technical claim against real output. Unverified AI output will be sent back.

## Style

- Docs: plain English, short paragraphs, tables where they help.
- Be explicit about what is **proven** vs **inferred**. The root-cause page separates the two on purpose.
- Do not present estimates as measurements. If you do not have a number, say so.

---

## Code of conduct

Be useful, be specific, be kind. "It didn't work" without logs is not a bug report. Nobody here is paid to debug your phone.
