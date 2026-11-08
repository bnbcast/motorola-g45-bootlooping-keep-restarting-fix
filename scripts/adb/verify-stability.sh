#!/usr/bin/env bash
# Check whether the device is stable after a fix.
# Usage: ./verify-stability.sh [adb-path] [min-uptime-seconds]
# Exits 0 on PASS, 1 on FAIL.

set -u
ADB="${1:-adb}"
MIN_UP="${2:-600}"

sh_() { "$ADB" shell "$@" 2>/dev/null | tr -d '\r'; }

"$ADB" wait-for-device || exit 1

uptime_raw="$(sh_ cat /proc/uptime)"
up="${uptime_raw%% *}"
[ -z "$up" ] && up=0

crash_log="$(sh_ logcat -d -b crash)"
crashes="$(printf '%s' "$crash_log" | grep -c qcrilNrd)"
modem_cc="$(sh_ cat /sys/bus/msm_subsys/devices/subsys2/crash_count)"
baseband="$(sh_ getprop gsm.version.baseband)"
sim="$(sh_ getprop gsm.sim.state)"
net="$(sh_ getprop gsm.network.type)"
bootreason="$(sh_ getprop ro.boot.bootreason)"
dnet="$(sh_ "dumpsys connectivity | grep -m1 'Active default network'")"
http="$(sh_ "curl -s -m 6 -o /dev/null -w '%{http_code}' http://connectivitycheck.gstatic.com/generate_204")"

fail=0
check() {  # check <label> <value> <0|1 pass>
  local label="$1" value="$2" pass="$3"
  local mark="PASS"
  [ "$pass" -eq 1 ] || { mark="FAIL"; fail=$((fail+1)); }
  printf '  %-28s %-40s %s\n' "$label" "$value" "$mark"
}

echo
echo "Moto G45 stability check"
echo "Boot reason: $bootreason"
echo

[ "$up" -ge "$MIN_UP" ] && p=1 || p=0
check "Uptime >= ${MIN_UP}s" "${up}s" "$p"

[ "$crashes" -eq 0 ] && p=1 || p=0
check "qcrilNrd crashes == 0" "$crashes" "$p"

[ "$modem_cc" = "0" ] && p=1 || p=0
check "modem crash_count == 0" "$modem_cc" "$p"

[ -n "$baseband" ] && p=1 || p=0
check "Baseband present" "$baseband" "$p"

case "$sim" in *LOADED*) p=1;; *) p=0;; esac
check "SIM loaded" "$sim" "$p"

[ -n "$net" ] && p=1 || p=0
check "Network type present" "$net" "$p"

case "$dnet" in *none*|"") p=0;; *) p=1;; esac
check "Default network != none" "$dnet" "$p"

[ "$http" = "204" ] && p=1 || p=0
check "HTTP reachable (204)" "$http" "$p"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS - device looks stable. Reboot once and run this again."
  exit 0
fi
echo "FAIL - $fail check(s) failed."
echo "If the modem crash counter is climbing, see docs/12-confirmed-fix-nv-repair.md"
exit 1
