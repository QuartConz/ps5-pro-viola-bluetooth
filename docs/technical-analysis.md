# Technical analysis – PS5 Pro (Viola) Bluetooth `0e8d:3605`

All measurements on one PS5 Pro, firmware 13.60, kernel `7.3.0-PinkSoup` (Linux 7.3 + ps5-linux-patches), BlueZ 5.87. Device addresses are omitted.

## 1. USB topology

The controller is the only device on the Salina xHCI `0000:40:00.6` (bus 5, one root port). Other USB ports belong to the APU xHCIs `20:00.4/.5`.

Interfaces of `0e8d:3605` (alt 0):

| IF | Endpoints | Role |
|---|---|---|
| 0 | `0x81` int IN, `0x01` bulk OUT, `0x82` bulk IN, `0x02` bulk OUT, `0x8f` int IN | function 1: firmware download / WMT |
| 1 | `0x83`/`0x03` isoc | function 1: SCO |
| 2 | `0x8a`/`0x0a` interrupt | function 1: MTK ISO-over-interrupt |
| 3 | `0x8c` int IN, `0x0b` bulk OUT, `0x8d` bulk IN, `0x0d` bulk OUT | **function 2: HCI controller** |
| 4 | `0x8e`/`0x0e` isoc | function 2: SCO |

IF3 mirrors IF0 with an endpoint offset of 11.

## 2. HCI on interface 3

- Firmware is loaded through function 1 (btmtk, unchanged).
- Function 2 only accepts HCI commands after the WMT command `6f fc 06 01 06 02 00 00 01` is sent as class/interface control request with `wIndex 3`.
- Without it, or with commands sent to `wIndex 0`, the controller replies `Command Disallowed (0x0c)`.
- With it, HCI Reset returns `0e 04 01 03 0c 00`, events arrive on `0x8c`. HCI/LMP version 0x0d, manufacturer 0x0046.

## 3. ACL bulk OUT: `0x0b` vs `0x0d`

With stock endpoint selection btusb uses the first bulk OUT of IF3, `0x0b`.

xHCI debugfs endpoint contexts (relevant fields):

| EP | DCI | Type | maxp | burst | CErr |
|---|---|---|---|---|---|
| 0x01 | 2 | Bulk OUT | 512 | 0 | 3 |
| 0x02 | 4 | Bulk OUT | 512 | 0 | 3 |
| 0x0b | 22 | Bulk OUT | 512 | 0 | 3 |
| 0x0d | 26 | Bulk OUT | 512 | 0 | 3 |

Kernel software ring pointers after a pairing attempt on `0x0b`: dequeue at TRB 1, enqueue at TRB 25. The first ACL packet (14 bytes) completed, all following ones stayed queued although the doorbell was rung for each.

Cross-checks:
- Zero-length bulk OUT via usbfs on IF0 `0x02` and `0x01`: both complete → Salina bulk OUT and doorbell work in general.
- ACL IN on `0x8d` works (7 transfers completed in the same attempt).

Conclusion: transfers on `0x0b` stall after the first one; this is consistent with a persistent device-side NAK/stall (not proven at bus level – no USB analyzer capture). With ACL routed to `0x0d` (patch `0001`): in a captured DualSense SDP/L2CAP session, usbmon recorded 20 submitted and 20 successfully completed ACL bulk OUT URBs on `0x0d` with no outstanding transfers; the xHCI enqueue/dequeue pointers of that endpoint converged. Pairing and HID work.

## 4. USB autosuspend kills the Salina xHCI

usbmon sequence when runtime PM suspends the device: `SET_FEATURE(remote wakeup)` → `PORT_SUSPEND` → `HC died` → endless `Host Controller Error`. Only a cold boot recovers. With `autosuspend_delay_ms=-1` no failure was observed (btusb resets `control` to `auto`, the delay of -1 still prevents suspend; the udev rule sets both).

## 5. L2CAP security block (patch `0002`)

btmon with the **unmodified** `bluetooth.ko` (srcversion verified), bonded DualSense, PS button:

```
12.832  HCI Event: Connect Request          Encryption: Disabled
        L2CAP: Connection Request  PSM 1    -> pending, then successful (SDP)
        L2CAP: Connection Request  PSM 17   -> Connection refused - security block (0x0003)
13.505  HCI Event: Encryption Change        Encryption: Enabled with E0
13.547  HCI Event: Disconnect Complete      Reason: Remote User Terminated Connection (0x13)
```

Identical on a second attempt. With `0002` both HID channels (PSM 17 and 19) connect.

### Does `0002` weaken security? (code review, Linux 7.3)

`0002` only skips the immediate `SEC_BLOCK` when the link is not yet encrypted, a link key exists (`key_type != 0xff`) and the feature-mask exchange is done. Control flow afterwards:

1. `l2cap_connect()` calls `l2cap_chan_check_security()` → `hci_conn_security()`. For an SSP link at security level LOW or MEDIUM this returns 1 only if `HCI_CONN_ENCRYPT` is set and the key size has been read. Otherwise it starts authentication/encryption and returns 0 → channel goes to `BT_CONNECT2`, response *pending / authentication pending*.
2. A channel in `BT_CONNECT2` leaves that state only via `l2cap_security_cfm()` or the `l2cap_conn_start()` recheck. The recheck again uses `hci_conn_security()` (needs encryption, see 1).
3. `l2cap_security_cfm()` is called only from `hci_auth_cfm()` and `hci_encrypt_cfm()`:
   - `hci_auth_cfm()` returns early while `HCI_CONN_ENCRYPT_PEND` is set. `hci_conn_auth()` sets that flag whenever it requests authentication on an unencrypted link; it is cleared only by an Encryption Change event or a failed authentication (which reports `status != 0` → `SEC_BLOCK`).
   - `hci_encrypt_change_evt()` runs `hci_conn_check_link_mode()` before notifying. On an SSP link without encryption this fails, `status` becomes `HCI_ERROR_AUTH_FAILURE`, upper layers get the failure (`SEC_BLOCK`) and the link is disconnected.
4. If encryption never comes, the channel timer closes the channel.

Result: on SSP links (DualSense) a channel deferred by `0002` can only be accepted after encryption is on and the key size check passed. On non-SSP links `hci_conn_check_link_mode()` already accepts unencrypted links in stock code, so behaviour is unchanged.

Limitations: this is a code review for Linux 7.3, not a test. A negative test (encryption never enabled) has not been run.

## 6. BlueZ: `Could not parse HID SDP record` (no patch)

Code path in BlueZ 5.87:

1. The input profile service exists as soon as the HID UUID is in the device's UUID list (EIR or `info: Services=`), independent of a stored record (`input_device_register()`).
2. Incoming HID channels are accepted if that service exists (`profiles/input/server.c:confirm_event_cb()`), then authorization calls `device_wait_for_svc_complete()`, which starts reverse SDP **only if `bredr_state.svc_resolved` is false**.
3. `search_cb()` on error calls `device_svc_resolved(..., err)`, which sets `state->svc_resolved = true` regardless of `err` (`src/device.c`). Unchanged in upstream `master` at the time of writing.
4. Hence one failed outgoing attempt (`bluetoothctl connect` to a switched-off DualSense → Page Timeout → `Host is down`) disables reverse SDP for the lifetime of `bluetoothd`; `extract_hid_record()` then finds `idev->rec == NULL` and returns `-ENOENT`.

Observed: `search_cb ... Host is down` at 13:23:52, ENOENT at 13:23:55 with no SDP in between; cache contained only `[General]`.

After a fresh `bluetoothd` and only the PS button: host-initiated SDP transactions (tid 0–2: L2CAP UUID, PnP, public browse group) ran over the incoming link, `device_svc_resolved err 0`, `[ServiceRecords]` was written, HID connected. Reconnects then work without SDP.

## 7. Open questions

- Why encryption completes ~0.7 s after the HID connection request on this controller.
- Purpose of IF3 bulk OUT `0x0b`.
- Whether `0002` is needed for first-time pairing with an empty cache (only reconnect with cached record was A/B-tested).
