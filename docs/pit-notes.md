# Samsung MTK PIT Notes

The PIT (Partition Information Table) is the phone's Download-mode partition map. It's dumped from the device via the Odin protocol (Thor's `dumpPit` command).

## Filename matching

PIT entries store a `filename` field that tools use to match incoming files to partitions. On Samsung MTK devices, this field does **not** include the `.lz4` extension:

```
PIT says:      super.img, boot.img, lk-verified.img, spmfw-verified.img
SamFw tar has: super.img.lz4, boot.img.lz4, lk-verified.img.lz4
```

Tools that match exactly (Thor's `flashTar`) will find zero matches for SamFw archives. Tools that strip `.lz4` (Odin, Eros) work.

## Part-index bug in odin4

odin4 v7.3.0 (`Llucs/odin4`) has a pre-flight check that fails on this PIT generation with:
```
Bootloader file part index mismatch: expected 30 got 0
```
This is a tool bug, not a firmware issue. The XDA-recommended workaround is to use a different tool. The public source code for this version is no longer available; the bug doesn't exist in later or earlier commits.

## Key partition names (A14 5G / MT6833)

| PIT name | GPT name | Purpose |
|----------|----------|---------|
| preloader.img | (lu1/lu2) | Boot ROM to preloader |
| lk-verified.img | lk | Little Kernel (Android bootloader) |
| tee-verified.img | tee1 | ARM Trusted Firmware + TEE |
| gz-verified.img | gz1 | Guardian Zone / TrustZone |
| spmfw-verified.img | spmfw | System Power Manager |
| scp-verified.img | scp1 | Sensor Co-Processor |
| sspm-verified.img | sspm_1 | Security Sub-System PM |
| mcupm-verified.img | mcupm_1 | MCU Power Manager |
| dpm-verified.img | dpm_1 | Deep Power Manager |
| pi_img-verified.img | pi_img | Platform Infrastructure |
| tzar.img | tzar | TrustZone Archive |
| super.img | super | Dynamic partitions (system/vendor/product/odm) |
| md1img.img | md1img | Modem firmware |
| vbmeta.img | vbmeta | AVB metadata |

## 60 entries on the A14

The full PIT has 60 entries including many non-flashable system partitions (EFS, nvdata, protect1/2, etc.). Only ~25 are flashable from firmware archives.
