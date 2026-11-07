#!/usr/bin/env bash
# Collect diagnostic evidence from a bootlooping Android device.
# Usage: ./collect-evidence.sh [outdir] [adb-path]
# Review the output before sharing — see PRIVACY.md.

set -u
OUT="${1:-capture}"
ADB="${2:-adb}"

mkdir -p "$OUT"

echo "==> waiting for device"
"$ADB" wait-for-device || exit 1

save() {  # save <filename> <shell command...>
  local file="$1"; shift
  "$ADB" shell "$*" > "$OUT/$file" 2>/dev/null
  printf '    %-28s %s bytes\n' "$file" "$(wc -c < "$OUT/$file" | tr -d ' ')"
}

echo "==> device info"
"$ADB" devices -l > "$OUT/devices.txt"

echo "==> properties and settings"
save props.txt            getprop
save settings-global.txt  settings list global
save settings-system.txt  settings list system
save settings-secure.txt  settings list secure

echo "==> packages"
save packages-all.txt         pm list packages
save packages-disabled.txt    pm list packages -d
save packages-thirdparty.txt  pm list packages -3

echo "==> telephony / connectivity"
save connectivity.txt        dumpsys connectivity
save telephony-registry.txt  dumpsys telephony.registry
save phone.txt               dumpsys phone
save wifi.txt                dumpsys wifi
save sim-state.txt           getprop gsm.sim.state
save network-type.txt        getprop gsm.network.type

echo "==> crash evidence"
save logcat-crash.txt   logcat -d -b crash
save logcat-radio.txt   logcat -d -b radio
save logcat-system.txt  logcat -d -b system
save dmesg.txt          dmesg
save tombstones-list.txt ls -l /data/tombstones
save uptime.txt         cat /proc/uptime
save bootreason.txt     getprop ro.boot.bootreason

echo "==> tombstones (may fail without root)"
"$ADB" pull /data/tombstones "$OUT/tombstones" 2>/dev/null

echo
echo "==> summary"
if [ -f "$OUT/logcat-crash.txt" ]; then
  printf '    qcrilNrd mentions: %s\n' "$(grep -c qcrilNrd "$OUT/logcat-crash.txt")"
fi
[ -f "$OUT/uptime.txt" ] && printf '    uptime: %s\n' "$(cat "$OUT/uptime.txt")"

echo
echo "Saved to $OUT"
echo "REMINDER: sanitise before publishing. See PRIVACY.md"
