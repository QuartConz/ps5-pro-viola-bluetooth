#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Install prebuilt bluetooth.ko (0002) and btusb.ko (0001) for the running
# kernel into /lib/modules/$(uname -r)/updates and set up USB power handling.
#
# Usage: sudo scripts/install.sh <path/to/bluetooth.ko> <path/to/btusb.ko>
#
# Nothing is changed unless all checks pass. A rollback script is written to
# /var/lib/ps5-viola-bt/rollback.sh. Changes take effect after the next boot.
set -uo pipefail

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

stop() { echo "STOP (nothing changed): $*"; exit 2; }

echo "== Checks"
[ "$(id -u)" = 0 ] || stop "run as root"
[ -f "$SRC_BT" ] && [ -f "$SRC_USB" ] || stop "usage: $0 <bluetooth.ko> <btusb.ko>"
lsusb -d 0e8d:3605 >/dev/null 2>&1 || stop "MediaTek 0e8d:3605 not found (not a PS5 Pro?)"
for M in "$SRC_BT" "$SRC_USB"; do
    VM=$(modinfo -F vermagic "$M" | cut -d' ' -f1)
    [ "$VM" = "$KVER" ] || stop "$M built for '$VM', running '$KVER'"
done
modinfo -F parm "$SRC_USB" | grep -q '^ps5_ep_resync' || stop "$SRC_USB does not look like the patched btusb"
{ [ -e "$DST_BT" ] || [ -e "$DST_USB" ]; } && stop "$UPD already contains bluetooth modules"
grep -rnE '^\s*(blacklist|install)\s+(btusb|bluetooth)\b' /etc/modprobe.d/ /usr/lib/modprobe.d/ 2>/dev/null \
    && stop "modprobe.d blacklists btusb/bluetooth"
echo "checks OK"

echo "== Install"
mkdir -p "$STATE"
install -D -m 644 "$SRC_BT"  "$DST_BT"
install -D -m 644 "$SRC_USB" "$DST_USB"
depmod "$KVER"
P_BT=$(modinfo -n bluetooth); P_USB=$(modinfo -n btusb)
echo "modprobe -> bluetooth: $P_BT"
echo "modprobe -> btusb:     $P_USB"
if [ "$P_BT" != "$DST_BT" ] || [ "$P_USB" != "$DST_USB" ]; then
    echo "ERROR: updates/ is not preferred by depmod - reverting"
    rm -f "$DST_BT" "$DST_USB"; depmod "$KVER"
    exit 1
fi

install -m 644 "$HERE/system/50-viola-bt-power.rules" "$UDEV"
install -m 644 "$HERE/system/viola-btusb.conf" "$MODOPT"
udevadm control --reload

CMDL_BAK=""
if [ -f "$CMDL" ] && grep -q 'modprobe.blacklist=btusb' "$CMDL"; then
    CMDL_BAK="$CMDL.bak-$TS"
    cp -p "$CMDL" "$CMDL_BAK"
    sed -i 's/ modprobe\.blacklist=btusb//; s/modprobe\.blacklist=btusb //' "$CMDL"
    echo "removed modprobe.blacklist=btusb from $CMDL (backup $CMDL_BAK)"
fi

systemctl enable bluetooth.service

cat > "$STATE/rollback.sh" <<RB
#!/usr/bin/env bash
# Rollback for installation $TS
rm -f "$DST_BT" "$DST_USB" "$UDEV" "$MODOPT"
depmod "$KVER"
[ -n "$CMDL_BAK" ] && cp -p "$CMDL_BAK" "$CMDL"
systemctl disable bluetooth.service
echo "Rollback done - cold boot required."
RB
chmod +x "$STATE/rollback.sh"
sha256sum "$DST_BT" "$DST_USB" > "$STATE/installed.sha256"

echo "== Done"
cat "$STATE/installed.sha256"
echo "Rollback: $STATE/rollback.sh"
echo "Cold boot, then run: scripts/verify.sh"
