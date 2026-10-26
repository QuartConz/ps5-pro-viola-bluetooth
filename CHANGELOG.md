# Changelog

## v0.1.0-preview – 2026-10-26

- `0001` btusb: PS5 Pro MediaTek `0e8d:3605` on IF3 (WMT + HCI via `wIndex 3`), ACL bulk OUT `0x0d` (driver version "v1.4", as tested; contains the inert `ps5_ep_resync` parameter)
- `0002` L2CAP: defer security block while link encryption is pending
- udev rule and modprobe option to disable USB autosuspend
- `install.sh` (updates/ + depmod, checks, rollback), `verify.sh`
- Documentation of measurements and the BlueZ `svc_resolved` behaviour
