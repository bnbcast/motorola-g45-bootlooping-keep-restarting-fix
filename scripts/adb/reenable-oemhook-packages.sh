#!/usr/bin/env bash
# Re-enable the 13 oemhook packages disabled during recovery.
# Usage: ./reenable-oemhook-packages.sh [adb-path]

set -u
ADB="${1:-adb}"

packages=(
  com.motorola.omadm.service
  com.qualcomm.qti.cne
  com.motorola.hiddenmenuapp
  com.motorola.carriersettingsext
  com.motorola.msimsettings
  com.motorola.entitlement
  com.motorola.genie
  com.motorola.ccc.notification
  com.motorola.moto
  com.qualcomm.qti.uimGbaApp
  com.qualcomm.qti.remoteSimlockAuth
  com.motorola.help
  com.motorola.wifi.motowifimetrics
)

"$ADB" wait-for-device || exit 1

echo "Re-enabling ${#packages[@]} packages..."
echo "WARNING: if the root cause is not fixed, the crash loop may return."
echo

for p in "${packages[@]}"; do
  out="$("$ADB" shell pm enable "$p" 2>&1 | tr -d '\r')"
  case "$out" in
    *"new state: enabled"*) echo "  OK      $p" ;;
    *)                      echo "  SKIP    $p  ($out)" ;;
  esac
done

echo
echo "Still-disabled packages:"
"$ADB" shell pm list packages -d

echo
echo "Verify with: ./verify-stability.sh"
