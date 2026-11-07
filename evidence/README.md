# Evidence index

Sanitised captures that support the claims in `docs/`. Nothing here is required to fix a phone — it exists so the diagnosis can be checked rather than taken on faith.

| File | What it shows | Source |
|---|---|---|
| [`../assets/android15-latest-build.png`](../assets/android15-latest-build.png) | Final state: Android 15, build `V1UGS35H.75-14-9-3-1-4`, security patch 1 September 2026, 5G + VoLTE | Settings → Software update |
| [`crash-signature.txt`](crash-signature.txt) | The `qcrilNrd` tombstone: signal, fault address, full backtrace, triggering indications | `/data/tombstones`, `logcat -b crash` |
| [`device-snapshot-sanitized.txt`](device-snapshot-sanitized.txt) | Build, bootloader state, modem version, SIM/network state, the 13 disabled packages, post-reset verification | `getprop`, `settings list`, `pm list packages -d` |
| [`tether-log-sanitized.txt`](tether-log-sanitized.txt) | Watchdog log proving the reboot cadence and that USB tethering kept reconnecting | `tether-watchdog.ps1` log |
| [`timeline.txt`](timeline.txt) | Condensed chronology with evidence pointers | Compiled from the above |

## How these were produced

```bash
adb shell getprop                > props.txt
adb shell logcat -d -b crash     > crash.txt
adb pull /data/tombstones        tombstones/
adb shell dumpsys connectivity   > connectivity.txt
adb shell dumpsys telephony.registry > telephony.txt
```

Then manually sanitised per [`../PRIVACY.md`](../PRIVACY.md).

## What is missing, and why

| Missing | Reason |
|---|---|
| Full `logcat` (all buffers) | Contains account identifiers, notification text and app usage. Only the crash excerpt is published. |
| `dumpsys telephony.registry` | Contains phone number / IMSI on some builds. Summarised instead. |
| Tombstone register dump | Not retained in the field capture; the backtrace is the load-bearing part. |
| Screen recording / screenshots | Show personal accounts and notifications. |
| WhatsApp backups | Private. Excluded entirely. |
| Raw firmware files | Multi-GB, copyrighted, and region-specific. Use LMSA to obtain the correct one. |

## Reproducing the evidence on your own device

See [`../docs/02-diagnosis.md`](../docs/02-diagnosis.md) and run:

```powershell
.\scripts\adb\collect-evidence.ps1 -OutDir .\capture
```

The script writes the same set of files, unsanitised — **review before sharing**.
