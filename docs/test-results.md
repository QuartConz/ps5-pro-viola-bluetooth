# Test results

Hardware: PS5 Pro (Viola), firmware 13.60, MediaTek `0e8d:3605`, Sony DualSense `054c:0ce6`
Software: kernel `7.3.0-PinkSoup` (Linux 7.3 + ps5-linux-patches `linux.patch`), BlueZ 5.87
Date: 2026-10-26

## A. Without patch 0002 (unmodified `bluetooth.ko`, srcversion verified)

| Check | Result |
|---|---|
| HCI controller up | OK |
| DualSense via PS button (2 attempts) | **FAIL** – PSM 17 *security block*, remote disconnect 0x13 |

## B. With both patches, loaded manually

| Check | Result |
|---|---|
| Native SDP on incoming connection | OK, `device_svc_resolved err 0`, `[ServiceRecords]` written |
| Input devices | gamepad, motion sensors, touchpad |
| Input events (20 s) | 707 (sticks, triggers, shoulder buttons, d-pad, face buttons) |
| Disconnect + reconnect via PS button | OK, no SDP needed, no errors |

## C. Installed via `updates/`, after a regular boot (`verify.sh` predecessor)

```
bluetooth.ko  OK Patch
btusb_v14     OK
usb_power     delay=-1 control=on runtime=active
xhci          OK
bluetoothd    active
controller    OK powered
verbindung    OK
eingaben      OK (655)
```

## D. v1.6 on ps5-linux-patches main (2026-10-29)

Software: kernel `7.2.3-Viola76` (Linux 7.2.3 + ps5-linux-patches `linux.patch` at #58 `6f18433`/`f21f65b`), `patches/main/0001` + `0002`, BlueZ (CachyOS/SteamOS base)

| Check | Result |
|---|---|
| Boot: `PS5 Pro: ACL bulk OUT 0x0d selected`, `PS5 Pro: IF3 activated, HCI routed to IF3` | OK |
| Pairing, connect, reconnect via PS button after cold boot | OK |
| unreleased v1.5 (routing as in v1.4): `btmgmt power off` + `power on` | **FAIL** – `Execution of wmt command timed out`, `Failed to send wmt patch dwnld (-110)`, adapter gone (mgmt index lost) until cold boot |
| v1.5 + routing reset in setup only: `btmgmt power off` + `power on` | partial – power on OK, but power off waits for `Failed to send wmt func ctrl (-110)` (shutdown still routed to `wIndex 3`) |
| v1.6 (routing reset in setup and shutdown): `btmgmt power off` + `power on` | OK – second setup `PS5 Pro: IF3 activated`, no WMT errors; unloading btusb without timeout |
| `btmgmt public-addr` (Linux-only address `98:…` → `9A:…`) | OK – kernel programs it via `btmtk_set_bdaddr` on power on |
| `ps5-bt-addr` service after cold boot | OK – `Controller 9A:…`, DualSense on slot 4 (PS + Square) connects; PS5 system slot 1 (PS + Triangle) still connects in the PS5 system |
| Earlier `ps5-bt-addr` attempt that ran before bluetoothd / in the auto-off window after registration | **FAIL** (adapter dropped from the mgmt index list); fixed by running after `bluetooth.service` and waiting for a really powered adapter |

DualSense firmware: update version 0630 (multi-device pairing).

## E. v1.6 on Bazzite 7.3.0 (2026-10-30)

Software: Bazzite (ps5-bazzite-deck) v1.8.4 on the internal M.2, v1.8.6 quick kernel `7.3.0`; `btusb.ko` = Bazzite's base + `patches/0001` v1.6, built out of tree against `/usr/lib/modules/7.3.0/build`. Same PS5 Pro (13.60), white DualSense (update version 0630).

| Check | Result |
|---|---|
| v1.4 control build on the same base | PS5/Viola strings and module parameters identical to Bazzite's `btusb.ko` (srcversion differs, stripped vs. unstripped build) |
| Boot with Bazzite's v1.4 | **FAIL** (both observed boots) – `Viola IF3 WMT sent; HCI routed to IF3`, then `Opcode 0x0c03 failed: -16`, no mgmt index (`No default controller available`) |
| v1.6 loaded from that state (`modprobe -r btusb`, load v1.6) | OK – `PS5 Pro: IF3 activated`, `Powered: yes` |
| v1.6: `bluetoothctl power off` + `power on` | OK – second setup, no WMT errors |
| v1.6 from `updates/` after cold boot | **FAIL** – `Opcode 0x0c03 failed: -16` at ~11–17 s after boot, same as v1.4 |
| `modprobe -r btusb && modprobe btusb` afterwards (~2 min after boot) | OK, reproducible |
| `ps5-bt-revive` with the extra `Opcode 0x0c03 failed` pattern, two cold boots | OK – `reloading btusb`, `Bluetooth adapter back` after 7 s / 22 s, `Powered: yes` |
| `tools/ps5-bt-addr` with Bazzite's `ps5-bt-addr.service` | OK – `98:FA:… -> 9A:FA:…` |
| DualSense on slot 4 (PS + Square) in Bazzite, slot 1 (PS + Triangle) in the PS5 system | OK, switching both ways |
| Unbind/bind of xHCI `0000:40:00.6` while working | **FAIL** – `PS5 Pro: IF3 WMT activation failed (-110)`, later `Failed to get device id (-110)`; cold boot needed |

Second PS5 Pro (13.40), Bazzite v1.8.4/v1.8.6 with Bazzite's v1.4 only: one boot with `-16` as above, one boot with `xhci_hcd 0000:40:00.6: HC died` during re-enumeration of `5-1` (`hub failed to enable device, error -62`, `Salina poller: lock busy`). A bind after `HC died` brought the adapter back; unbind/bind from a working state failed with `Opcode 0x0c03 failed: -110` (also with a 15 s pause). Runtime PM of `40:00.6` was `control=on` and never suspended.

## Not yet tested

- First-time pairing with an empty SDP cache after a fresh install
- Other kernels, other PS5 models, other Bluetooth devices
