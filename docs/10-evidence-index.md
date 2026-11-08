# 10 — Evidence index (docs view)

The raw material behind every claim in this repository, sanitised. Full descriptions are in [`../evidence/README.md`](../evidence/README.md).

| File | Answers the question |
|---|---|
| [`../assets/android15-latest-build.png`](../assets/android15-latest-build.png) | What does "fixed" look like? Android 15, build `V1UGS35H.75-14-9-3-1-4`, patch 1 Sep 2026, LTE + voice working after the NV repair |
| [`../evidence/crash-signature.txt`](../evidence/crash-signature.txt) | What exactly crashed, and why is it the vendor library's fault? |
| [`../evidence/device-snapshot-sanitized.txt`](../evidence/device-snapshot-sanitized.txt) | What was the device state before and after the fix? |
| [`../evidence/tether-log-sanitized.txt`](../evidence/tether-log-sanitized.txt) | How bad was the loop, and did USB tethering actually work? |
| [`../evidence/timeline.txt`](../evidence/timeline.txt) | What happened, in what order, with pointers to proof? |

---

## The chain of evidence

```text
modem
  └─ subsys2/crash_count climbs with /data wiped and both SIMs removed
       └─ the modem asserts on its own, before Android does anything
            └─ points at the NV store in modemst1/modemst2   [device-snapshot]

tombstone
  └─ qcrilNrd SIGSEGV at 0xffffffffffffff02
       └─ libmotext_inf.so communicationThread
            └─ oemhook token dereference of a dead modem connection
                 └─ SYMPTOM, not the cause                 [crash-signature.txt]

logcat -b radio
  └─ unsolicited RegRAT / UpdateOperator / DataState / APMState
       └─ fires every few seconds on a dual-SIM device
            └─ explains ~14 crashes/boot                   [crash-signature.txt]

device state
  └─ bootreason=watchdog, uptime < 200 s, SIM NOT_READY, no default net
       └─ downstream consequences, not separate faults     [device-snapshot]

interventions
  ├─ 13 packages disabled  -> crashes 14 -> ~2             [timeline]
  ├─ airplane mode         -> crashes near 0               [timeline]
  ├─ OTA / LMSA keep-data  -> loop persists                [timeline]
  ├─ factory reset         -> stable ~3 hours, then loop   [timeline]
  └─ erase modemst1/2      -> 0 crashes, LTE + voice        [device-snapshot]

post-fix
  └─ all 13 packages re-enabled, still 0 crashes
       └─ packages were never the cause                    [timeline]
```

---

## What the evidence does *not* prove

Be honest about the limits:

1. **The exact corrupting event is unknown.** We know the modem NV was inconsistent and that erasing it fixed the device. We do not know what wrote the bad data at 16:43 — an interrupted NV write, an aborted OTA, or a failing storage block.
2. **No NV dump was taken.** There is no `modemst1/modemst2` image from before the erase, so the corruption is proven *by repair*, not by inspection. Erasing and rebuilding produced a working modem, which is strong but indirect evidence.
3. **One device.** No statistical claim about how often the NV repair works. The ~60 % / ~90 % figures in the original notes were estimates, not measurements, and are deliberately not repeated as facts here.
4. **No vendor source.** `libmotext_inf.so` is closed source. The token-dereference reading comes from the fault address and the call path, not from source review.
5. **The OTA version is ambiguous.** Two Android 15 strings appear in the source notes; see [`03-root-cause.md`](03-root-cause.md#build-numbers-in-this-report).

---

## Recreating this evidence

```powershell
.\scripts\adb\collect-evidence.ps1 -OutDir .\capture
```

Outputs props, settings, crash buffer, radio log, connectivity, telephony, dmesg, tombstones and a bugreport. **Sanitise before sharing** — see [`../PRIVACY.md`](../PRIVACY.md).
