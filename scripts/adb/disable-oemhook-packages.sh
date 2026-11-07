#!/usr/bin/env bash
# Disable the 13 oemhook-heavy packages as a TEMPORARY crash-rate reducer.
# NOT a fix. Undo with reenable-oemhook-packages.sh
# Usage: ./disable-oemhook-packages.sh [adb-path]

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

echo "Disabling ${#packages[@]} oemhook packages..."
echo "WARNING: temporary mitigation only. Re-enable after the real fix."
echo

for p in "${packages[@]}"; do
  out="$("$ADB" shell pm disable-user --user 0 "$p" 2>&1 | tr -d '\r')"
  case "$out" in
    *"new state: disabled"*) echo "  OK      $p" ;;
    *)                       echo "  SKIP    $p  ($out)" ;;
  esac
done

echo
echo "Optional: quiet the radio to reduce crash rate further"
echo '  adb shell settings put global airplane_mode_on 1'
echo '  adb shell cmd connectivity airplane-mode enable'
echo
echo "Undo with: ./reenable-oemhook-packages.sh"
