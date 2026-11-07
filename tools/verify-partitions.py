#!/usr/bin/env python3
"""Hash-compare dumped phone partitions against firmware reference images.
Usage: verify-partitions.py <dumps_dir> <parts_dir>
Prints MATCH/DIFF per partition. Your rollback safety net."""
import hashlib, os, sys

def sha256(path, limit=None):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        sz = limit or os.path.getsize(path)
        while sz > 0:
            b = f.read(min(8<<20, sz))
            if not b: break
            h.update(b); sz -= len(b)
    return h.hexdigest()

def main(dumps, parts):
    pairs = {
        'boot': 'boot.img', 'init_boot': 'init_boot.img',
        'vendor_boot': 'vendor_boot.img', 'recovery': 'recovery.img',
        'dtbo': 'dtbo.img', 'vbmeta': 'vbmeta.img',
        'vbmeta_system': 'vbmeta_system.img',
        'lk': 'lk-verified.img', 'param': 'param.bin',
        'up_param': 'up_param.bin', 'spmfw': 'spmfw-verified.img',
        'scp1': 'scp-verified.img', 'sspm_1': 'sspm-verified.img',
        'gz1': 'gz-verified.img', 'tee1': 'tee-verified.img',
        'tzar': 'tzar.img', 'dpm_1': 'dpm-verified.img',
        'mcupm_1': 'mcupm-verified.img', 'pi_img': 'pi_img-verified.img',
        'md1img': 'md1img.img',
    }
    for name, ref in pairs.items():
        dump = os.path.join(dumps, f'{name}.cur')
        refp = os.path.join(parts, ref)
        if not os.path.exists(dump): continue
        if not os.path.exists(refp):
            print(f"{name:14s} (no reference)"); continue
        rsz = os.path.getsize(refp)
        print(f"{name:14s} {'MATCH' if sha256(dump, rsz) == sha256(refp) else '** DIFF **'}")

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
