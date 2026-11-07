# 10 — Evidence index (docs view)

The raw material behind every claim in this repository, sanitised. Full descriptions are in [`../evidence/README.md`](../evidence/README.md).

| File | Answers the question |
|---|---|
| [`../assets/android15-latest-build.png`](../assets/android15-latest-build.png) | What does "fixed" look like? Android 15, build `V1UGS35H.75-14-9-3-1-4`, patch 1 Sep 2026, 5G + VoLTE |
| [`../evidence/crash-signature.txt`](../evidence/crash-signature.txt) | What exactly crashed, and why is it the vendor library's fault? |
| [`../evidence/device-snapshot-sanitized.txt`](../evidence/device-snapshot-sanitized.txt) | What was the device state before and after the fix? |
| [`../evidence/tether-log-sanitized.txt`](../evidence/tether-log-sanitized.txt) | How bad was the loop, and did USB tethering actually work? |
| [`../evidence/timeline.txt`](../evidence/timeline.txt) | What happened, in what order, with pointers to proof? |

---

## The chain of evidence

```text
tombstone
  └─ qcrilNrd SIGSEGV at 0xffffffffffffff02
       └─ libmotext_inf.so communicationThread
            └─ oemhook token use-after-free          [crash-signature.txt]

logcat -b radio
  └─ unsolicited RegRAT / UpdateOperator / DataState / APMState
       └─ fires every few seconds on a dual-SIM device
            └─ explains ~14 crashes/boot                  [crash-signature.txt]

device state
  └─ bootreason=watchdog, uptime < 200 s, SIM NOT_READY, no default net
       └─ downstream consequences, not separate faults    [device-snapshot]

interventions
  ├─ 13 packages disabled  -> crashes 14 -> ~2            [timeline]
  ├─ airplane mode         -> crashes near 0              [timeline]
  ├─ OTA / LMSA keep-data  -> loop persists               [timeline]
  └─ factory reset         -> 0 crashes, 27 min, LTE       [device-snapshot]

post-fix
  └─ all 13 packages re-enabled, still 0 crashes
       └─ packages were never the cause                   [timeline]
```

---

## What the evidence does *not* prove

Be honest about the limits:

1. **The exact poisoning event is unknown.** We know the state was inconsistent; we do not know which message or race corrupted the token table at 16:43.
2. **Modem NVRAM was not measured.** No `modemst1/modemst2` dump exists before or after. The "cleared modem NVRAM" phrasing in the original notes is a hypothesis, not a measurement.
3. **One device.** No statistical claim about how often factory reset works. The ~60 % / ~90 % figures in the original notes were estimates, not measurements, and are deliberately not repeated as facts here.
4. **No vendor source.** `libmotext_inf.so` is closed source. The use-after-free reading comes from the fault address and the call path, not from source review.
5. **The OTA version is ambiguous.** Two Android 15 strings appear in the source notes; see [`03-root-cause.md`](03-root-cause.md#build-numbers-in-this-report).

---

## Recreating this evidence

```powershell
.\scripts\adb\collect-evidence.ps1 -OutDir .\capture
```

Outputs props, settings, crash buffer, radio log, connectivity, telephony, dmesg, tombstones and a bugreport. **Sanitise before sharing** — see [`../PRIVACY.md`](../PRIVACY.md).
