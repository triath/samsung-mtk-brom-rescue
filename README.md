# Samsung MTK super rescue

Notes, scripts and patches from unbricking a Galaxy A14 5G (SM-A146U, MT6833 / Dimensity 700)
after a failed Android 13 to Android 15 Odin flash. Odin kept rejecting `super` with
`0xFFFFFFFB (Auth)`. The fix was to get the rest of the bootchain onto the target version
over MediaTek BROM first, then let Odin do a plain same-version flash.

This worked once, on one phone. Read it as a field report, not a guarantee.

## The short version

If your Samsung MTK phone is bricked from a failed cross-version Odin flash and Odin keeps
giving you `FAIL! (Write)` or Auth rejections on `super`:

1. Stop re-flashing. The rejection is a version-mismatch wall, not a bad cable or a bad tool.
2. Use mtkclient over BROM to write every bootchain partition except `super` to the target
   firmware version. Hash-verify each write by reading it back.
3. Do a full four-slot Odin flash (BL + AP + CP + CSC) from Windows. It is now a same-version
   re-flash, not a cross-version upgrade. The Auth wall is gone and `super` goes in with
   everything else.

## Why it works

Samsung's Download-mode agent enforces anti-rollback per partition. During a cross-version
flash the bootloader is changing versions mid-write. Individually signed partitions
(co-processor images, boot) still commit because they pass signature check on their own.
`super`, the dynamic-partition container for system/vendor/product, is checked against the
bootloader's own version chain. If that chain doesn't match what you're writing, the commit
is refused with `0xFFFFFFFB (Auth)`.

Once the bootchain is already at the target version, a full Odin flash is a same-version
operation. Anti-rollback is satisfied and the wall isn't there.

## What's in here

### `scripts/`

The mtkclient script-mode files that did the work: dump the bootchain, see what's stale,
write everything except `super`, then write `super`. See [scripts/README.md](scripts/README.md).

### `tools/`

| Tool | Purpose |
|------|---------|
| `brom-catcher.sh` | Retries an mtkclient script until a BROM window is caught, then gates success on a sha256 of the read-back. flock single-writer, per-attempt logs, disk preflight, per-attempt timeout. |
| `simg2raw.py` | Streaming Android sparse to raw converter with sha256. Handles sparse v1.0 chunks (RAW/FILL/DONTCARE/CRC). Use before writing sparse images over BROM. |
| `verify-partitions.py` | Hash-compare dumped partitions against firmware reference images. Pre- and post-flight check. |

### `patches/`

Local changes to [bkerler/mtkclient](https://github.com/bkerler/mtkclient) at commit
`118a000`. Each file sits next to its `.orig`.

| File | Change | Why |
|------|--------|-----|
| `Port.py` | Handshake byte timeout 500 to 100 ms; USB poll sleep 300 to 5 ms; log handshake failures at info | The preloader's USB window is about 2.5 s every 17 s on a boot-looping phone. Default polling can miss it. |
| `seriallib.py` | Fall back to the last detected serial port instead of failing | After a BROM crash and reconnect the port number can shift. |
| `mtk_class.py` | Port config as dict; close, sleep, redetect after DA crash | The crash-to-BROM path reconnects on a different port. |

These are what the successful catches ran under. I didn't A/B each line, and at least one
timeout path I touched never ran on this device. Starting point, not proven-minimal.

### `docs/`

- `playbook.md`: step-by-step procedure
- `pit-notes.md`: Samsung MTK PIT quirks (filename matching, part-index bugs in third-party tools)
- `expdb-analysis.md`: reading MediaTek's exception database to find where boot dies

## Gotchas that cost me days

1. `--skipwdt` is mandatory. Samsung's preloader rejects watchdog writes and hangs without it.
2. Blacklist the kernel serial/modem drivers or they grab the MTK port before mtkclient can.
   Which one binds depends on the enumerated interface: `cdc_acm` takes the CDC-ACM serial
   interface, `option` + `usb_wwan` take the BROM device (`0e8d:0003`) as a GSM modem. On my
   host it was the modem pair. Watch `dmesg -w` while plugging in and blacklist whatever claims it:
   ```bash
   printf 'blacklist cdc_acm\nblacklist option\nblacklist usb_wwan\n' | sudo tee /etc/modprobe.d/mtk-temp.conf
   sudo modprobe -r cdc_acm option usb_wwan 2>/dev/null
   ```
3. Warm reboots skip the preloader USB phase. Only PMIC-level resets (watchdog timeout,
   battery pull) re-run the 2.5 s download window. If the phone warm-boots to Download mode
   you will never catch BROM.
4. `usbfs_memory_mb`. Linux caps USB transfer memory at 16 MB by default. Raise it or bulk
   writes fail with `ENOMEM`:
   ```bash
   echo 0 | sudo tee /sys/module/usbcore/parameters/usbfs_memory_mb
   ```
5. Sparse images must be expanded before BROM writes. mtkclient writes raw bytes and does not
   expand sparse containers. Check for the `0xED26FF3A` magic at offset 0 first.
6. PIT filenames don't include `.lz4`. Third-party tools that match tar member names against
   PIT entries find nothing in SamFw's `.lz4` archives. Tool bug, not firmware bug.

## Credits

- [bkerler/mtkclient](https://github.com/bkerler/mtkclient), the BROM access that made this possible
- [Samsung-Loki/Thor](https://github.com/Samsung-Loki/Thor), Download-mode session control
- [Gabriel2392/ErosFlashTool](https://github.com/Gabriel2392/ErosFlashTool), Android-side flashing
- [Llucs/odin4](https://github.com/Llucs/odin4), Linux Odin (has a PIT part-index bug on some MTK Samsungs, see `docs/pit-notes.md`)

## License

MIT
