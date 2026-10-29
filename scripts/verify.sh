#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Verify the installed stack after a cold boot, then (optionally) a DualSense
# reconnect via the PS button and real input events.
#
# Usage: sudo scripts/verify.sh            # full test, press PS when asked
#        sudo scripts/verify.sh --no-pad   # stack checks only
# Exit status: 0 = all checks PASS, 1 = at least one FAIL
set -uo pipefail

KVER=$(uname -r)
UPD=/lib/modules/$KVER/updates
LOG=/var/log/ps5-viola-bt-verify-$(date +%Y%m%d-%H%M%S).log
exec > >(tee "$LOG") 2>&1
declare -A R
KEYS=()
FAILS=0
res() {  # res <key> <PASS|FAIL> <detail>
    KEYS+=("$1"); R[$1]="$2  $3"
    [ "$2" = PASS ] || FAILS=$((FAILS + 1))
}
count() { journalctl -k -b --no-pager | grep -cE "$1"; }

dev=$(for d in /sys/bus/usb/devices/*; do
    [ "$(cat "$d/idVendor" 2>/dev/null):$(cat "$d/idProduct" 2>/dev/null)" = "0e8d:3605" ] && echo "$d"
done | head -1)

echo "== Stack"
lsmod | grep -E '^(bluetooth|btusb|btmtk) '

SV_RUN=$(cat /sys/module/bluetooth/srcversion 2>/dev/null)
SV_UPD=$(modinfo -F srcversion "$UPD/net/bluetooth/bluetooth.ko" 2>/dev/null)
if [ -n "$SV_RUN" ] && [ "$SV_RUN" = "$SV_UPD" ]; then res bluetooth.ko PASS "updates/ ($SV_RUN)"
else res bluetooth.ko FAIL "loaded '$SV_RUN', updates/ '$SV_UPD'"; fi

# v1.4 and v1.6 log texts
if [ "$(count 'Viola v1.4: ACL OUT 0x0d selected|PS5 Pro: ACL bulk OUT 0x0d selected')" -gt 0 ]; then res btusb PASS "ACL OUT 0x0d"
else res btusb FAIL "no 'ACL OUT 0x0d selected' in kernel log"; fi

if [ "$(count 'Viola IF3 WMT sent|PS5 Pro: IF3 activated')" -gt 0 ]; then res if3_wmt PASS ""
else res if3_wmt FAIL "no IF3 WMT activation in kernel log"; fi

if [ "$(count 'wmt command timed out|Failed to send wmt|Failed to set up firmware')" -eq 0 ]; then res wmt_errors PASS ""
else res wmt_errors FAIL "WMT timeouts in kernel log (v1.4 after power off/on? update 0001 to v1.6)"; fi

if [ -n "$dev" ]; then
    D=$(cat "$dev/power/autosuspend_delay_ms"); C=$(cat "$dev/power/control"); S=$(cat "$dev/power/runtime_status")
    if [ "$D" = -1 ] && [ "$C" = on ] && [ "$S" = active ]; then res usb_power PASS "delay=$D control=$C runtime=$S"
    else res usb_power FAIL "delay=$D control=$C runtime=$S (want -1/on/active)"; fi
else
    res usb_power FAIL "device 0e8d:3605 not found"
fi

if [ "$(count 'HC died|not responding')" -eq 0 ]; then res xhci PASS ""
else res xhci FAIL "'HC died' or 'not responding' in kernel log"; fi

A=$(systemctl is-active bluetooth.service)
if [ "$A" = active ]; then res bluetoothd PASS ""; else res bluetoothd FAIL "$A"; fi

if timeout 5 bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then res controller PASS "powered"
else res controller FAIL "not powered or no controller"; fi

if [ "${1:-}" != "--no-pad" ]; then
    MAC=$(timeout 5 bluetoothctl devices Paired 2>/dev/null | grep -i 'DualSense\|Wireless Controller' | awk '{print $2}' | head -1)
    if [ -z "$MAC" ]; then
        res dualsense FAIL "no paired DualSense found"
    else
        echo
        echo ">>> Press ONLY the PS button on the DualSense (max. 60 s)."
        echo ">>> Do not use 'bluetoothctl connect' (see README)."
        OK=0
        for _ in $(seq 1 60); do
            timeout 3 bluetoothctl info "$MAC" 2>/dev/null | grep -q 'Connected: yes' && { OK=1; break; }
            sleep 1
        done
        if [ "$OK" = 1 ]; then res dualsense PASS "connected"; else res dualsense FAIL "not connected within 60 s"; fi
        sleep 4
        EV=$(awk '/^N: Name="DualSense Wireless Controller"$/{f=1} f&&/^H: Handlers=/{match($0,/event[0-9]+/); print substr($0,RSTART,RLENGTH); exit}' /proc/bus/input/devices)
        if [ -z "$EV" ]; then
            res input FAIL "no DualSense input device"
        elif ! command -v evtest >/dev/null; then
            res input FAIL "evtest not installed"
        else
            echo ">>> 10 s: use buttons and sticks"
            N=$(timeout 10 evtest "/dev/input/$EV" 2>/dev/null | grep -c '^Event:.*EV_\(KEY\|ABS\)')
            if [ "$N" -gt 0 ]; then res input PASS "$N events"; else res input FAIL "no events"; fi
        fi
    fi
fi

echo
echo "== Result"
for K in "${KEYS[@]}"; do printf '%-13s %s\n' "$K" "${R[$K]}"; done
echo
if [ "$FAILS" -eq 0 ]; then echo "OVERALL: PASS"; else echo "OVERALL: FAIL ($FAILS)"; fi
echo "Log: $LOG"
[ "$FAILS" -eq 0 ]
