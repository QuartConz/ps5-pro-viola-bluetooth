# Changelog

## Unreleased

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
