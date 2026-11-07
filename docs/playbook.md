# Samsung MTK unbrick playbook

Tested on: Galaxy A14 5G (SM-A146U, MT6833 / Dimensity 700, UFS), A13 to A15 upgrade brick.

## Prerequisites

- Linux PC with Docker
- The full firmware package for your target version (BL/AP/CP/CSC `.tar.md5`)
- [mtkclient](https://github.com/bkerler/mtkclient) cloned locally, with `patches/` applied
- A Windows PC with Odin3 for the final step

## Phase 1: get BROM access

The phone needs to be in a boot loop where the preloader runs its USB download phase, a
window of about 2.5 s every 17 s watchdog cycle.

Caveat up front: button combos get you Samsung's Download mode, not MediaTek BROM. The loop
that gives repeating BROM windows is a spontaneous watchdog reset loop (for example a
mismatched bootloader and bootchain that fails to boot). You can't reliably trigger it from
the keys. If you already have such a loop, arm the catcher and go. If the phone sits in
Download mode instead, see [If you can't get BROM access](#if-you-cant-get-brom-access).

To confirm you can catch a window at all, run a read-only script with the hash gate off:

```bash
EXPECTED=none SCRIPT=scripts/dump_bootchain.txt VERIFY_OUT=dumps/misc.cur ./tools/brom-catcher.sh
```

## Phase 2: find what's stale

Dump the bootchain and co-processor partitions (`scripts/dump_bootchain.txt`,
`scripts/diag3.txt`) and compare against the extracted firmware:

```bash
python3 tools/verify-partitions.py dumps/ parts/
```

This shows which partitions are still on the old version. On my A14 most of the bootchain
was still A13. Only boot and vbmeta had been written by the failed Odin session.

## Phase 3: write everything except super over BROM

Write each stale partition's target-version image via mtkclient, then read it back and hash
it. `scripts/fix_bootchain.txt` and `scripts/fix_coprocs.txt` do write-then-read for the
bootchain and co-processors. `tools/brom-catcher.sh` drives `scripts/fix_super2.txt` with a
sha256 gate; point it at the other scripts if you want the retry loop for them too.

Flags and host setup:

- `--skipwdt`, mandatory on Samsung MTK
- Blacklist the kernel serial/modem drivers first (`cdc_acm`, and/or `option` + `usb_wwan`,
  whichever `dmesg` shows claiming the port). See README gotcha 2.

## Phase 4: full Odin flash from Windows

Once the whole bootchain except `super` is at the target version:

1. Copy all four firmware files to Windows
2. Phone into Download mode
3. Odin3: load BL, AP, CP and the full CSC (not HOME_CSC)
4. Start

The flash that was an impossible cross-version upgrade is now a same-version re-flash.
`super` commits with everything else. 20 to 40 minutes.

## Phase 5: restore user data

The full CSC wipes userdata. Restore from your backup.

## If you can't get BROM access

The preloader USB window only appears on PMIC-level resets. If the phone warm-boots straight
to Download mode, here are the options. Two require taking the phone apart and only one of those
works. The no-teardown ones either didn't work or happened by accident.

1. **Battery disconnect, then hold Vol+ and Vol- while plugging in USB.** You have to open
   the phone to get at the battery connector on this model. Having done that, it did not
   land me in BROM. Vol+ and Vol- is the combo for Samsung's own Download mode
   (`04e8:685d`), not MediaTek's BROM (`0e8d:0003`). A cold boot with no buttons gives the
   normal 2.5 s preloader window once, and once is not enough to catch reliably.
   So you've taken the phone apart for a trick that doesn't work.

2. **Corrupt a co-processor partition from Download mode to force a watchdog loop.** No
   teardown, but it didn't produce a loop. Flashing the A13 `tee1` committed cleanly with
   no Auth rejection and the phone came back to Download mode. Worse, it leaves you with a
   mixed-version co-processor set, which can be harder to recover from than where you
   started. My original loop came from a full A13 co-proc set under an EZH3 bootloader and
   I could not reproduce it on purpose. Unproven and possibly harmful. Don't treat it as a
   fallback.

3. **MTK test point short.** Same teardown as the battery pull, but this one works. Short
   the test pad to ground while plugging in USB and the SoC parks in BROM. It's what repair
   shops do. The pads vary by board revision and are easy to misidentify, so find a
   confirmed photo for your exact board before touching anything.

4. **Bootloader / bootchain version mismatch.** This is what actually gave me my loop, by
   accident. I flashed the EZH3 BL alone from Odin onto a phone whose co-processors and
   bootchain were still A13. The EZH3 lk and ATF came up against A13 `tee1`, `gz1`, `scp1`
   and friends, boot died in ATF / co-processor init, and the PMIC watchdog reset the SoC
   every 17 s or so. Every reset re-ran the preloader, which is the repeating 2.5 s USB
   window the catcher needs. `expdb` showed the `wdt_status:0x6` records (see
   `docs/expdb-analysis.md`). So the mismatch has to be across the whole co-processor set,
   not one partition. A single stale `tee1` (option 2) was not enough. I did not manage to
   reproduce it on purpose, so treat it as an explanation of why the loop exists, not a
   recipe.

Summary: the reliable way into BROM for me was a watchdog loop I didn't engineer. If you
don't have one and you're going to open the phone anyway, go straight for the test point.
Don't pull the battery expecting a button combo to do the rest.

## What not to do

- Don't try to write `super` from Download mode on a version-mismatched phone. It Auth-rejects forever.
- Don't flash BL alone as a fix. It makes the brick worse, though it may accidentally give you BROM access.
- Don't trust progress bars. Read the device's actual response lines (`EndSequenceFlash` / `EndSession`).
- Don't trust log greps as success gates. Hash-verify the written data.
