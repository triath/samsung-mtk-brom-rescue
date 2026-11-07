# mtkclient script files

These are [mtkclient](https://github.com/bkerler/mtkclient) `script` files, the exact BROM
reads and writes that diagnosed and repaired the A14. They run as:

```bash
python3 mtk.py --skipwdt script /a/scripts/fix_bootchain.txt
```

Paths are container paths. Every `/a/...` is the repo root mounted inside the Docker
container (`-v "$REPO:/a"`, see `tools/brom-catcher.sh`). Running mtkclient bare-metal?
Replace `/a/` with your repo path. `parts/` holds the target-version reference images
extracted from firmware, `verify/` and `dumps/` hold read-back output. None of those are
committed (see `.gitignore`), so create them and point them at your own images.

| File | What it does |
|------|--------------|
| `dump_bootchain.txt` | Reads the boot-critical partitions (`boot`, `vbmeta*`, `lk`, `param`, `misc`, ...) for before/after comparison. One BROM catch, many reads. |
| `diag3.txt` | Reads the co-processor partitions (`spmfw`, `scp1`, `sspm_1`, `gz1`, `tee1`, `tzar`, `dpm_1`, `mcupm_1`, `pi_img`, `uh`) plus `seccfg` and `proinfo`. |
| `fix_bootchain.txt` | Writes `init_boot`, `vendor_boot`, `recovery`, `dtbo`, `vbmeta_system` to the target version, then reads each back. |
| `fix_coprocs.txt` | Writes the nine co-processor images plus `md1img` (modem) to the target version, then reads each back. The `--length` values are per-partition sizes. Device-specific, recompute for yours. |
| `fix_super2.txt` | Writes `super` from a raw (de-sparsed) image, reads it back for hashing, resets. Driven by `tools/brom-catcher.sh`. |

Verify after writing: `w`, then `r`, then `sha256sum` on the host. A clean mtkclient log line
is not proof the bytes landed. The read-back hash is.

`proinfo` and `seccfg` dumps contain device identifiers. Keep `dumps/` out of git.
