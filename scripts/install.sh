#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Install prebuilt bluetooth.ko (0002) and btusb.ko (0001) for the running
# kernel into /lib/modules/$(uname -r)/updates and set up USB power handling.
#
# Usage: sudo scripts/install.sh <path/to/bluetooth.ko> <path/to/btusb.ko>
#
# - Nothing is changed unless all checks pass.
# - Existing files are never overwritten; the script stops instead.
# - Every step is recorded; on any error the completed steps are undone.
# - A rollback script restoring the previous state is written to
#   /var/lib/ps5-viola-bt/rollback.sh. Changes take effect after a cold boot.
set -euo pipefail

SRC_BT=${1:-}
SRC_USB=${2:-}
KVER=$(uname -r)
UPD=/lib/modules/$KVER/updates
DST_BT=$UPD/net/bluetooth/bluetooth.ko
DST_USB=$UPD/drivers/bluetooth/btusb.ko
HERE=$(cd "$(dirname "$0")/.." && pwd)
UDEV=/etc/udev/rules.d/50-viola-bt-power.rules
MODOPT=/etc/modprobe.d/viola-btusb.conf
CMDL=${CMDLINE_TXT:-/boot/efi/cmdline.txt}
STATE=/var/lib/ps5-viola-bt
TS=$(date +%Y%m%d-%H%M%S)

stop() { echo "STOP (nothing changed): $*" >&2; exit 2; }

# ---------------------------------------------------------------- checks
echo "== Checks"
[ "$(id -u)" = 0 ] || stop "run as root"
{ [ -f "$SRC_BT" ] && [ -f "$SRC_USB" ]; } || stop "usage: $0 <bluetooth.ko> <btusb.ko>"
lsusb -d 0e8d:3605 >/dev/null 2>&1 || stop "MediaTek 0e8d:3605 not found (not a PS5 Pro?)"
for M in "$SRC_BT" "$SRC_USB"; do
    VM=$(modinfo -F vermagic "$M" | cut -d' ' -f1)
    [ "$VM" = "$KVER" ] || stop "$M built for '$VM', running '$KVER'"
done
modinfo -F alias "$SRC_USB" | grep -qi 'v0E8Dp3605' || stop "$SRC_USB has no 0e8d:3605 alias (not the patched btusb)"
for F in "$DST_BT" "$DST_USB" "$UDEV" "$MODOPT" "$STATE/rollback.sh"; do
    [ -e "$F" ] && stop "$F already exists (previous installation? use its rollback first)"
done
if grep -rnE '^\s*(blacklist|install)\s+(btusb|bluetooth)\b' /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null; then
    stop "modprobe.d blacklists btusb/bluetooth"
fi
SVC_WAS=$(systemctl is-enabled bluetooth.service 2>/dev/null || true)
echo "bluetooth.service before: ${SVC_WAS:-unknown}"
echo "checks OK"

# ---------------------------------------------------------------- undo log
DONE=()
undo() {
    local rc=$?
    trap - ERR EXIT
    [ "$rc" -eq 0 ] && return
    echo "ERROR (exit $rc) - undoing completed steps" >&2
    for ((i=${#DONE[@]}-1; i>=0; i--)); do
        case ${DONE[$i]} in
            bt)    rm -f "$DST_BT" ;;
            usb)   rm -f "$DST_USB" ;;
            depmod) ;;
            udev)  rm -f "$UDEV"; udevadm control --reload || true ;;
            modopt) rm -f "$MODOPT" ;;
            cmdl)  cp -p "$CMDL_BAK" "$CMDL" ;;
            svc)   [ "$SVC_WAS" = enabled ] || systemctl disable bluetooth.service || true ;;
        esac
    done
    depmod "$KVER" || true
    echo "undo finished - system as before" >&2
    exit "$rc"
}
trap undo ERR EXIT

# ---------------------------------------------------------------- install
echo "== Install"
mkdir -p "$STATE"
install -D -m 644 "$SRC_BT"  "$DST_BT";  DONE+=(bt)
install -D -m 644 "$SRC_USB" "$DST_USB"; DONE+=(usb)
depmod "$KVER"; DONE+=(depmod)
P_BT=$(modinfo -n bluetooth); P_USB=$(modinfo -n btusb)
echo "modprobe -> bluetooth: $P_BT"
echo "modprobe -> btusb:     $P_USB"
[ "$P_BT" = "$DST_BT" ] && [ "$P_USB" = "$DST_USB" ] || { echo "updates/ is not preferred by depmod" >&2; false; }

install -m 644 "$HERE/system/50-viola-bt-power.rules" "$UDEV"; DONE+=(udev)
udevadm control --reload
install -m 644 "$HERE/system/viola-btusb.conf" "$MODOPT"; DONE+=(modopt)

CMDL_BAK=""
if [ -f "$CMDL" ] && grep -q 'modprobe.blacklist=btusb' "$CMDL"; then
    CMDL_BAK="$CMDL.bak-$TS"
    cp -p "$CMDL" "$CMDL_BAK"
    sed -i 's/ modprobe\.blacklist=btusb//; s/modprobe\.blacklist=btusb //' "$CMDL"; DONE+=(cmdl)
    if grep -q 'modprobe.blacklist=btusb' "$CMDL"; then echo "entry still present in $CMDL" >&2; false; fi
    echo "removed modprobe.blacklist=btusb from $CMDL (backup $CMDL_BAK)"
fi

if [ "$SVC_WAS" != enabled ]; then
    systemctl enable bluetooth.service; DONE+=(svc)
fi

# ---------------------------------------------------------------- rollback
cat > "$STATE/rollback.sh" <<RB
#!/usr/bin/env bash
# Rollback for installation $TS - restores the state before installation
set -u
rm -f "$DST_BT" "$DST_USB" "$UDEV" "$MODOPT"
depmod "$KVER"
udevadm control --reload
if [ -n "$CMDL_BAK" ] && [ -f "$CMDL_BAK" ]; then cp -p "$CMDL_BAK" "$CMDL"; fi
if [ "$SVC_WAS" != "enabled" ]; then systemctl disable bluetooth.service; fi
rm -f "$STATE/rollback.sh" "$STATE/installed.sha256"
echo "Rollback done - cold boot required."
RB
chmod +x "$STATE/rollback.sh"
sha256sum "$DST_BT" "$DST_USB" > "$STATE/installed.sha256"

trap - ERR EXIT
echo "== Done"
cat "$STATE/installed.sha256"
echo "Rollback: $STATE/rollback.sh"
echo "Cold boot, then run: scripts/verify.sh"
