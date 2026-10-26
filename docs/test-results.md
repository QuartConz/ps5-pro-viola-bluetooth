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

## Not yet tested

- First-time pairing with an empty SDP cache after a fresh install
- Other kernels, other PS5 models, other Bluetooth devices
