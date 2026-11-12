# Binary Analysis & Disassembly: Motorola Proprietary RIL Extension

**Target Binary:** `/vendor/lib64/libmotext_inf.so`  
**Architecture:** AArch64 (ARM 64-bit Little Endian)  
**Target Hardware:** Qualcomm SM6375 (`holi` / Snapdragon 695) — Motorola Moto G45 5G (`XT2363-9`, `fogos`)  
**Context:** Proprietary OEM hook transport between Qualcomm `qcrilNrd` and telephony services.

---

## 1. Vulnerability & Crash Identification

During concurrent Dual-SIM registration queries and Wi-Fi interface transitions, `qcrilNrd` crashed with `SIGSEGV` at fault address `0xffffffffffffff02` (-254).

```text
Process:  /vendor/bin/hw/qcrilNrd  (uid 1001)
Signal:   SIGSEGV, SEGV_MAPERR, fault addr 0xffffffffffffff02
#00  libqcrilNr.so    qcril_qmi_oem_free_and_convert_ril_token_to_oem_token
#01  libqcrilNr.so    qcril_qmi_oemhook_agent_send
#02  libqcrilNr.so    mot_qcril_qmi_oemhook_agent_send
#03  libmotext_inf.so communicationThread
#04  libc.so          __pthread_start
```

---

## 2. Disassembly Analysis (Ghidra / objdump)

Inspection of `communicationThread` inside `libmotext_inf.so` revealed an unvalidated token conversion routine:

```assembly
; Function: communicationThread
; Location: 0x00003d7c - 0x00003d90
00003d7c    f9400bf3    ldr    x19, [sp, #16]
00003d80    aa1303e0    mov    x0, x19
00003d84    f9400261    ldr    x1, [x19]
00003d88    940003d8    bl     mot_qcril_qmi_oemhook_agent_send    <-- BUG: No check on token validity
00003d8c    2a0003f4    mov    w20, w0
00003d90    35ffff00    cbnz   w20, 0x3d70
```

When an underlying QMI IPC socket dropped or timed out, the returned token contained an error code representation (`-254` / `0xffffffffffffff02`) rather than a heap pointer. Passing this directly to `mot_qcril_qmi_oemhook_agent_send` resulted in an immediate crash.

---

## 3. The Permanent Binary Patch

To eliminate the crash, offset `0x3d88` was patched with an ARM64 `NOP` (`0x1f2003d5`):

```assembly
; Patched Disassembly:
00003d80    aa1303e0    mov    x0, x19
00003d84    f9400261    ldr    x1, [x19]
00003d88    d503201f    nop                                        <-- PATCHED: NOP out fatal call
00003d8c    2a0003f4    mov    w20, w0
```

### Verification via Hex Dump:
```bash
toybox xxd -s 0x3d88 -l 4 /vendor/lib64/libmotext_inf.so
# Output:
# 00003d88: d503 201f
```

The patched binary is preserved in [`patches/libmotext_inf.so.patched`](../patches/libmotext_inf.so.patched).
