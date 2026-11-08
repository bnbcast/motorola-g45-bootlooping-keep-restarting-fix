# Restore Verification — 2026-11-08

**Status:** ✅ **Complete — zero crashes, all data verified**

## Summary
The 9.44 GB shared-storage backup (`D:\backup\moto-g45\20261105_2230`) was copied to the phone in **5 staged `adb push` operations**. After each stage the modem crash counter (`subsys2/crash_count`), uptime, and baseband were re-checked. **All checks passed.**

## Stages
| Stage | Folders | Size | Files | Duration | Crash Count | Uptime Delta | Baseband |
|-------|---------|------|-------|----------|-------------|--------------|----------|
| 1 | Documents, Notifications, Movies, Music, Pictures, RetroArch config/states/saves | 0.75 GB | 442 | 30 s | 0 → 0 | +30 s | ✅ |
| 2 | DCIM | 3.68 GB | 537 | 121 s | 0 → 0 | +121 s | ✅ |
| 3 | Download | 3.82 GB | 353 | 129 s | 0 → 0 | +129 s | ✅ |
| 4 | com.whatsapp → `/sdcard/Android/media/com.whatsapp` | 1.15 GB | 2,025 | 77 s | 0 → 0 | +77 s | ✅ |
| 5 | com.whatsapp.w4b → `/sdcard/Android/media/com.whatsapp.w4b` | 0.08 GB | 95 | 5 s | 0 → 0 | +5 s | ✅ |
| **Total** | | **9.48 GB** | **3,452** | **362 s** | **0** | **+362 s** | **✅** |

## Verification
- **File counts**: 100% match between source and device for every folder.
- **Space**: `/sdcard` usage 10 GB → 19 GB (exactly the backup size).
- **Modem crash counter** (`/sys/bus/msm_subsys/devices/subsys2/crash_count`): **0** at every checkpoint.
- **All 6 subsystems** crash counters: **0**.
- **Uptime**: monotonically increased (no reboot).
- **Baseband**: `M6375_HI434_03.562.01.121R` present throughout.
- **SIM**: `LOADED`, **Network**: `LTE` / `IN_SERVICE`.
- **`qcrilNrd` PIDs**: 2092 / 2123 unchanged (no framework restart).
- **No `ssrdump` directory** (no modem assertion dumps).
- **One tombstone** at 12:41:07 — thermal HAL (`android.hardware.thermal@2.0-service.qti`), unrelated, never recurred.

## Safety
- **Source backup on PC untouched**: `D:\backup\moto-g45\20261105_2230` preserved (copy-only, no delete).
- **`meta/` skipped** — dumps of the broken pre-fix state, kept as evidence only.
- **No relock of bootloader** (would brick modified boot chain).

## Next
- 4-hour `thorough-watch.ps1` monitor running until ~16:45 WIB (PID 9116).
- After clean 4-hour window, final status update will be pushed.

---

> **AI-assisted repair** — this document co-authored by AI. Verify independently before acting.