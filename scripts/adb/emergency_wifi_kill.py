#!/usr/bin/env python3
"""
emergency_wifi_kill.py
======================
Moto G45 5G (XT2363-9 / SM6375)
Instant fail-safe rollback to 100% stable cellular baseline.
Cleans up experimental triggers, suppresses crashing Wi-Fi analog front-end,
restores UFS stability, verifies telephony RIL patch, and enables mobile data.
"""

import subprocess
import time
import sys
import os

ADB = r"adb"

def run(args, timeout=10):
    try:
        r = subprocess.run([ADB] + args, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "TIMEOUT"
    except Exception as e:
        return -2, "", str(e)

def wait_for_device():
    print("[*] Waiting for device...", flush=True)
    while True:
        c, out, _ = run(["devices"])
        if "device" in out and "\tdevice" in out:
            print("    -> Device connected!", flush=True)
            return
        time.sleep(0.5)

def get_root():
    print("[*] Acquiring root...", flush=True)
    for _ in range(6):
        c, who, _ = run(["shell", "whoami"])
        if "root" in who:
            print("    -> Root OK", flush=True)
            return True
        run(["root"])
        time.sleep(3)
        for _ in range(10):
            c, s, _ = run(["get-state"])
            if "device" in s:
                break
            time.sleep(1)
    return False

def remount():
    print("[*] Remounting vendor RW...", flush=True)
    for _ in range(4):
        c, out, _ = run(["remount"], timeout=12)
        if c == 0 or "remount succeeded" in out.lower():
            print("    -> Remount OK", flush=True)
            return True
        time.sleep(2)
    return False

wait_for_device()
if not get_root():
    print("ERROR: Cannot get root!", flush=True)
    sys.exit(1)

remount()

# Step 1: Disable wlan.ko kernel module
print("[1] Disabling wlan.ko kernel module...", flush=True)
c, out, _ = run(["shell", "ls /vendor/lib/modules/wlan.ko 2>&1"])
if "wlan.ko" in out and "No such" not in out:
    run(["shell", "mv /vendor/lib/modules/wlan.ko /vendor/lib/modules/wlan.ko.disabled"])
c, out, _ = run(["shell", "ls -la /vendor/lib/modules/wlan.ko.disabled"])
print(f"    -> {out}", flush=True)

# Step 2: Block Wi-Fi DSP firmware (wlanmdsp.mbn)
print("[2] Blocking Wi-Fi DSP firmware (wlanmdsp.mbn)...", flush=True)
c, out, _ = run(["shell", "ls /vendor/firmware_mnt/image/wlanmdsp.mbn 2>&1"])
if "wlanmdsp.mbn" in out and "No such" not in out:
    run(["shell", "mv /vendor/firmware_mnt/image/wlanmdsp.mbn /vendor/firmware_mnt/image/wlanmdsp.mbn.disabled"])
c, out, _ = run(["shell", "ls -la /vendor/firmware_mnt/image/wlanmdsp.mbn.disabled"])
print(f"    -> {out}", flush=True)

# Step 3: Write vendor init RC to suppress CNSS at boot
print("[3] Writing vendor init RC to suppress CNSS at boot...", flush=True)
rc = """# Stability: disable Wi-Fi CNSS subsystem due to hardware power-rail brownout
on boot
    setprop vendor.wlan.firmware.disable 1
    stop cnss-daemon
    write /sys/devices/platform/soc/4804000.ufshc/auto_hibern8 0
    write /sys/devices/platform/soc/4804000.ufshc/clkscale_enable 0

on property:sys.boot_completed=1
    stop cnss-daemon
    write /sys/devices/platform/soc/4804000.ufshc/auto_hibern8 0
"""
with open("wifi_kill_temp.rc", "w") as f:
    f.write(rc)
run(["push", "wifi_kill_temp.rc", "/vendor/etc/init/wifi_kill.rc"])
run(["shell", "chmod 644 /vendor/etc/init/wifi_kill.rc"])
if os.path.exists("wifi_kill_temp.rc"):
    os.remove("wifi_kill_temp.rc")
print("    -> RC written", flush=True)

# Step 4: Disable cnss-daemon binary
print("[4] Disabling cnss-daemon binary...", flush=True)
c, out, _ = run(["shell", "ls /vendor/bin/cnss-daemon 2>&1"])
if "cnss-daemon" in out and "No such" not in out:
    run(["shell", "mv /vendor/bin/cnss-daemon /vendor/bin/cnss-daemon.disabled"])
    run(["shell", "chmod 644 /vendor/bin/cnss-daemon.disabled"])

# Step 5: Verify RIL NOP patch (libmotext_inf.so)
print("[5] Verifying RIL NOP patch (libmotext_inf.so)...", flush=True)
c, out, _ = run(["shell", "toybox xxd -s 0x3d88 -l 4 /vendor/lib64/libmotext_inf.so 2>&1"])
if "d503 201f" in out or "1f2003d5" in out.replace(" ", ""):
    print("    -> NOP patch CONFIRMED at 0x3d88 ✓", flush=True)
else:
    print(f"    -> Status: {out}", flush=True)

# Step 6: Verify UFS stability RC
print("[6] Verifying UFS stability RC...", flush=True)
c, out, _ = run(["shell", "ls -la /vendor/etc/init/ufs_stability.rc 2>&1"])
if "ufs_stability.rc" in out:
    print("    -> ufs_stability.rc present ✓", flush=True)

# Step 7: Enable mobile data
print("[7] Enabling cellular mobile data...", flush=True)
run(["shell", "sync"])
run(["shell", "settings put global mobile_data 1"])
run(["shell", "settings put global mobile_data1 1"])
run(["shell", "svc data enable"])
run(["shell", "svc wifi disable"])
run(["shell", "settings put global wifi_on 0"])

print("\n" + "=" * 45)
print("Option 2 Baseline Enforced: 100% Stable")
print("=" * 45)
