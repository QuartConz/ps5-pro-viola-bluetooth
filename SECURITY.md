# Security

## Scope of patch 0002 (L2CAP)

`0002` modifies `net/bluetooth/l2cap_core.c` in the kernel's Bluetooth core. It is **not limited to the PS5 Pro controller**: it affects every Bluetooth adapter handled by the patched `bluetooth.ko`.

What it changes: an incoming L2CAP connection request (other than SDP) on a link that is not yet encrypted, where a link key exists and the feature-mask exchange is done, is no longer rejected immediately with *security block*. Instead the normal security check runs and the channel waits (*pending / authentication pending*).

Why we consider this safe (code review against Linux 7.3, see [docs/technical-analysis.md §5](docs/technical-analysis.md#does-0002-weaken-security-code-review-linux-73)):

- On SSP links the waiting channel is only accepted after the link is encrypted and the encryption key size check passed.
- Encryption switched off or failed on an SSP link leads to `AUTH_FAILURE`, *security block* and disconnect.
- If encryption never completes, the channel timer closes the channel.
- On non-SSP (legacy) links stock behaviour already accepts unencrypted links; nothing changes.

Limitations:

- Established by code review, **not** by a negative test with encryption deliberately withheld.
- Valid for the reviewed kernel version (Linux 7.3). Re-review when rebasing to other kernels.
- The same workaround is carried by other PS5 Linux patch sets (see README, prior community work).

## Other risks

- USB runtime autosuspend of `0e8d:3605` crashes the Salina xHCI; the udev rule disables it. Removing the rule can make the USB controller unusable until a cold boot.
- `systemctl restart bluetooth` was once followed by WMT timeouts and failed USB re-enumeration on the test system.

## Reporting

Please open a GitHub issue. For anything that should not be public, use GitHub's private vulnerability reporting for this repository if enabled, or contact the maintainer via GitHub.
