# ps5-pro-viola-bluetooth

Native Linux support for the **internal MediaTek Bluetooth controller of the PS5 Pro (Viola), USB `0e8d:3605`**. No external USB dongle required.

Status: **v0.1.0-preview**. Tested on one console, one kernel, one controller (see [Test results](docs/test-results.md)). Not tested on other PS5 models or kernels.

> Independent community project. Not affiliated with, authorized or endorsed by Sony Interactive Entertainment. "PlayStation", "PS5" and "DualSense" are trademarks of their owners and are used only to describe the hardware. This repository contains no Sony software, firmware, keys, exploits or jailbreak components.

## What it fixes

| Problem | Cause | Fix |
|---|---|---|
| No usable HCI controller | `0e8d:3605` is a two-function device. IF0–2 handle firmware download/WMT, the HCI controller is **function 2 on IF3**. HCI commands to `wIndex 0` are answered with *Command Disallowed*. | `0001`: bind IF3 only, send WMT `6f fc 06 01 06 02 00 00 01` to `wIndex 3`, route HCI commands to `wIndex 3` |
| ACL data stalls after the first packet | Bulk OUT `0x0b` completes one transfer, then NAKs forever (xHCI endpoint context identical to working endpoints) | `0001`: use bulk OUT **`0x0d`** for ACL |
| DualSense connects, blinks, disconnects | HID control (PSM 0x11) arrives ~0.7 s before *Encryption Change*; stock L2CAP replies *security block* | `0002`: defer the security block while encryption is pending (community workaround, see credits; the channel still waits for encryption, see [analysis §5](docs/technical-analysis.md#does-0002-weaken-security-code-review-linux-73)) |
| xHCI dies ("HC died") | USB runtime autosuspend of the BT device kills the Salina xHCI | udev rule: `autosuspend_delay_ms=-1`, `control=on` |
| `Could not parse HID SDP record` | BlueZ behaviour, see below | operating rule, no patch |

Details and measurements: [docs/technical-analysis.md](docs/technical-analysis.md).

## Requirements

- PS5 Pro (Viola) running Linux via [soniciso1/ps5-linux-loader](https://github.com/soniciso1/ps5-linux-loader)
- Kernel built from [ps5-linux-patches](https://github.com/ps5-linux/ps5-linux-patches) (tested: Linux 7.3 + `linux.patch`, branch `meower`)
- MediaTek Bluetooth firmware for btmtk (as shipped by your distribution)
- BlueZ (tested: 5.87), `evtest` for `verify.sh`

## Build

Both patches apply to a kernel tree that **already has `linux.patch` applied**. Newer `ps5-linux-patches` versions may already contain the L2CAP workaround of `0002`; check with `git apply --check` and skip `0002` if it is already present.

```bash
cd /path/to/ps5-kernel/linux
git apply /path/to/ps5-pro-viola-bluetooth/patches/0001-btusb-ps5-pro-viola-mediatek-0e8d-3605.patch
git apply /path/to/ps5-pro-viola-bluetooth/patches/0002-bluetooth-l2cap-defer-security-block-while-encryption-pending.patch
```

Then either rebuild your kernel, or build only `drivers/bluetooth/btusb.ko` and `net/bluetooth/bluetooth.ko` as external modules against the tree of the **running** kernel, with the same compiler/toolchain options the kernel was built with (e.g. `LLVM=1` for clang/LTO builds). The resulting modules must have the same `vermagic` as `uname -r`; `install.sh` refuses anything else.

No prebuilt `.ko` files are distributed here.

## Install

```bash
sudo scripts/install.sh path/to/bluetooth.ko path/to/btusb.ko
```

The script:

1. checks root, presence of `0e8d:3605`, `vermagic`, that the btusb module carries the `0e8d:3605` alias, that no target file already exists, and that nothing blacklists btusb/bluetooth – nothing is changed if a check fails;
2. installs both modules to `/lib/modules/$(uname -r)/updates/`, runs `depmod` and verifies that `modprobe` now resolves to `updates/`. On any error from here on, all completed steps are undone automatically;
3. installs the udev rule and `options btusb enable_autosuspend=0`;
4. removes `modprobe.blacklist=btusb` from `/boot/efi/cmdline.txt` if present (backup kept; override path with `CMDLINE_TXT=`);
5. enables `bluetooth.service` (if not already enabled) and writes `/var/lib/ps5-viola-bt/rollback.sh`, which restores the recorded previous state.

The stock modules under `kernel/` are not touched. **Cold boot**, then:

```bash
sudo scripts/verify.sh
```

Press only the PS button when asked. Every check reports `PASS` or `FAIL`; the script ends with `OVERALL: PASS` and exit status 0 only if all checks passed (USB power must be `-1/on/active`, the paired DualSense must connect and deliver input events).

## Operating rules

- **Do not run `bluetoothctl connect` to a DualSense that is switched off** before its HID service record is cached. In BlueZ 5.87 a failed outgoing SDP attempt (Page Timeout → `Host is down`) marks the device's services as resolved (`device_svc_resolved()` sets `svc_resolved = true` even on error). The following incoming connection then skips SDP and fails with `Could not parse HID SDP record: No such file or directory`. Recovery: fresh `bluetoothd` (cold boot), then press only the PS button. Once `[ServiceRecords]` exists in `/var/lib/bluetooth/<adapter>/cache/<device>`, this no longer matters.
- Paired controllers reconnect via the **PS button**; they are not reachable by outgoing paging while idle.
- Avoid `systemctl restart bluetooth` while debugging this setup. On the test system a service restart was followed by MediaTek WMT timeouts (`-110`), an unsuccessful USB reset and failed re-enumeration (`Invalid ep0 maxpacket`); recovery required a cold boot. Observed once.
- Modules in `updates/` are tied to one kernel version. Rebuild both after every kernel build.

## Rollback

```bash
sudo /var/lib/ps5-viola-bt/rollback.sh   # then cold boot
```

## Known limitations

- Only verified on one PS5 Pro, firmware 13.60, kernel `7.3.0-PinkSoup`, BlueZ 5.87, one DualSense.
- First-time pairing with an empty SDP cache on a fresh install has not been re-tested separately.
- Why encryption completes so late on this controller is not understood; `0002` is a workaround. Its security property (no unencrypted HID channel on SSP links) is established by code review for Linux 7.3, not by a negative test.
- **`0002` is not limited to this hardware.** It changes L2CAP behaviour for every Bluetooth adapter driven by the patched `bluetooth.ko`. See [SECURITY.md](SECURITY.md).
- Only the DualSense (HID) was tested. Bluetooth audio/SCO, LE devices and other HID devices have not been validated.
- `0001` still carries the inert `ps5_ep_resync` parameter (default off) so that the published patch equals the tested binary. It will be removed in the next release.

## Prior community work

- [ps5-linux/ps5-linux-patches](https://github.com/ps5-linux/ps5-linux-patches) – kernel base, Salina xHCI driver
- [soniciso1/ps5-linux-loader](https://github.com/soniciso1/ps5-linux-loader) – Linux loader for the PS5 Pro
- [WizGery/ps5-mediatek-fixes](https://github.com/WizGery/ps5-mediatek-fixes) – first published the two key ideas for MediaTek `0e8d:3603`: ACL on the second bulk OUT endpoint, and the L2CAP "encryption pending" workaround. `0002` is that community workaround; `0001` applies the endpoint idea to `0e8d:3605`.
- [rmuxnet/ps5-linux-patches-1](https://github.com/rmuxnet/ps5-linux-patches-1) (rmuxnet, VivaLaVent) – carries the L2CAP workaround in the PS5 kernel patch set.

## Development and AI-assisted research

**Project maintainer: QuartConz** – hardware investigation, all experiments on the PS5 Pro, kernel builds, USB/HCI trace collection, controlled A/B tests, validation, permanent installation and release maintenance.

**ChatGPT (OpenAI) – collaborative driver development and debugging**
- MediaTek USB interface and HCI initialization analysis (IF3, `wIndex 3`, WMT activation)
- identification, testing and validation of ACL bulk OUT endpoint `0x0d`
- analysis of usbmon traces, xHCI transfer rings and failed transfers
- L2CAP authentication/encryption timing analysis and integration of the existing community workaround
- BlueZ SDP discovery diagnostics and verification of the working HID connection
- review of module installation, reproducibility and release safety

**Claude (Anthropic) – independent technical review**
- analysis of BlueZ 5.87 service-discovery state handling (`svc_resolved` on error) and the resulting test procedure
- code review of the L2CAP security behaviour of `0002` against Linux 7.3
- xHCI endpoint-context comparison and evaluation of alternative hypotheses
- install/verify scripts and release preparation

AI assistance was used for analysis, code suggestions and review. All results were obtained on physical hardware and validated by the project maintainer. This is an independent community project, not endorsed by OpenAI, Anthropic or Sony Interactive Entertainment.

## License

GPL-2.0, see [LICENSE](LICENSE). The patches modify GPL-2.0 kernel files and keep their original copyright notices.
