#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Verify the installed stack after a cold boot, then (optionally) a DualSense
# reconnect via the PS button and real input events.
#
# Usage: sudo scripts/verify.sh            # full test, press PS when asked
#        sudo scripts/verify.sh --no-pad   # stack checks only
set -uo pipefail

KVER=$(uname -r)
UPD=/lib/modules/$KVER/updates
LOG=/var/log/ps5-viola-bt-verify-$(date +%Y%m%d-%H%M%S).log
exec > >(tee "$LOG") 2>&1
declare -A R

dev=$(for d in /sys/bus/usb/devices/*; do
    [ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" = "0e8d:3605" ] && echo "$d"
done | head -1)
count() { journalctl -k -b --no-pager | grep -cE "$1"; }

echo "== Stack"
lsmod | grep -E '^(bluetooth|btusb|btmtk) '
SV_RUN=$(cat /sys/module/bluetooth/srcversion 2>/dev/null)
SV_UPD=$(modinfo -F srcversion "$UPD/net/bluetooth/bluetooth.ko" 2>/dev/null)
R[bluetooth.ko]=$([ -n "$SV_RUN" ] && [ "$SV_RUN" = "$SV_UPD" ] && echo "OK (updates/)" || echo "FAIL ($SV_RUN)")
R[btusb]=$([ "$(count 'Viola v1.4: ACL OUT 0x0d selected')" -gt 0 ] && echo "OK (ACL OUT 0x0d)" || echo FAIL)
R[if3_wmt]=$([ "$(count 'Viola IF3 WMT sent')" -gt 0 ] && echo OK || echo FAIL)
if [ -n "$dev" ]; then
    R[usb_power]="delay=$(cat "$dev/power/autosuspend_delay_ms") control=$(cat "$dev/power/control") runtime=$(cat "$dev/power/runtime_status")"
else
    R[usb_power]="FAIL (device not found)"
fi
R[xhci]=$([ "$(count 'HC died|not responding')" -eq 0 ] && echo OK || echo FAIL)
R[bluetoothd]=$(systemctl is-active bluetooth.service)
R[controller]=$(timeout 5 bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo "OK powered" || echo FAIL)
KEYS="bluetooth.ko btusb if3_wmt usb_power xhci bluetoothd controller"

if [ "${1:-}" != "--no-pad" ]; then
    echo
    echo ">>> Press ONLY the PS button on a paired DualSense (max. 60 s)."
    echo ">>> Do not use 'bluetoothctl connect' (see README)."
    C=FAIL
    for _ in $(seq 1 60); do
        timeout 3 bluetoothctl devices Connected 2>/dev/null | grep -q . && { C=OK; break; }
        sleep 1
    done
    R[connection]=$C
    sleep 4
    EV=$(awk '/^N: Name="DualSense Wireless Controller"$/{f=1} f&&/^H: Handlers=/{match($0,/event[0-9]+/); print substr($0,RSTART,RLENGTH); exit}' /proc/bus/input/devices)
    if [ -n "$EV" ] && command -v evtest >/dev/null; then
        echo ">>> 10 s: use buttons and sticks"
        N=$(timeout 10 evtest "/dev/input/$EV" 2>/dev/null | grep -c '^Event:.*EV_\(KEY\|ABS\)')
        R[input]=$([ "$N" -gt 0 ] && echo "OK ($N events)" || echo FAIL)
    else
        R[input]="FAIL (no input device or evtest missing)"
    fi
    KEYS="$KEYS connection input"
fi

echo
echo "== Result"
for K in $KEYS; do printf '%-13s %s\n' "$K" "${R[$K]}"; done
echo "Log: $LOG"
