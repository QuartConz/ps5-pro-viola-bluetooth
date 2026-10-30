# Changelog

## v0.2.1 – 2026-10-30

- Documentation only, no patch changes
- `0001` v1.6 tested on hardware with Bazzite's 7.3.0 kernel (meower base); notes on applying it to Bazzite's `btusb.c` (one hunk with fuzz 2)
- new known limitation: adapter can fail right after boot with `Opcode 0x0c03 failed: -16` (v1.4 and v1.6); a btusb reload fixes it; pattern for Bazzite's `ps5-bt-revive`
- new known limitation: xHCI unbind/bind while working needs a cold boot
- test results section E (Bazzite) and observations from a second PS5 Pro (13.40, v1.4)

## v0.2.0 – 2026-10-29

- `0001` v1.6: **fix** – after power off/on (`bluetoothctl power`, `btmgmt`, address change, service restart) the adapter failed (`wmt command timed out`, `-110`) and needed a cold boot; setup and shutdown now reset the HCI routing to `wIndex 0` first. Power off no longer waits for a WMT timeout
- `0001` v1.6: inert `ps5_ep_resync` parameter and unused includes removed, `BTUSB_NO_AUTOSUSPEND` on the device entry, `btusb_is_ps5_viola()` helper
- new `patches/main/0001`: port for ps5-linux-patches `main` (Linux 7.2.3 incl. PS5 Pro GPU #58), hardware-tested; `main` also needs `0002`
- new `tools/ps5-bt-addr` + `system/ps5-bt-addr.service`: Linux-only Bluetooth address, so one DualSense keeps a PS5-system slot and a Linux slot (multi-device pairing)
- `verify.sh`: accepts the v1.6 log texts, new `wmt_errors` check
- README: two kernel bases, power-cycle fix, DualSense slot procedure; test results section D

Also in this release (previously unreleased):

- `install.sh`: `set -e`, no overwriting of existing files, automatic undo of completed steps on error, rollback restores the recorded previous state (incl. previous `bluetooth.service` enablement); btusb is identified by its `0e8d:3605` alias instead of the experimental parameter
- `verify.sh`: PASS/FAIL per check with exit status, USB power values are pass criteria, connection check bound to the paired DualSense
- `SECURITY.md`: global scope and security reasoning of `0002`
- README: detailed contribution section, limitations (global L2CAP scope, untested audio/LE/other HID)
- analysis: `0x0b` stall wording (consistent with NAK, not bus-level proof)

## v0.1.0-preview – 2026-10-26

- `0001` btusb: PS5 Pro MediaTek `0e8d:3605` on IF3 (WMT + HCI via `wIndex 3`), ACL bulk OUT `0x0d` (driver version "v1.4", as tested; contains the inert `ps5_ep_resync` parameter)
- `0002` L2CAP: defer security block while link encryption is pending
- udev rule and modprobe option to disable USB autosuspend
- `install.sh` (updates/ + depmod, checks, rollback), `verify.sh`
- Documentation of measurements and the BlueZ `svc_resolved` behaviour
