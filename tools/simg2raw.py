import sys, struct, hashlib
def readn(f, n):
    buf = b''
    while len(buf) < n:
        c = f.read(n - len(buf))
        if not c:
            raise EOFError(f"short read: got {len(buf)} of {n}")
        buf += c
    return buf
inp = sys.stdin.buffer
outh = open(sys.argv[1], 'wb')
hdr = readn(inp, 28)
magic, major, minor, fhs, chs, blk, tblks, tchunks, csum = struct.unpack('<IHHHHIIII', hdr)
assert magic == 0xED26FF3A, hex(magic)
print(f"sparse v{major}.{minor} blk={blk} total={tblks*blk} chunks={tchunks}", file=sys.stderr)
if fhs > 28: readn(inp, fhs - 28)
sha = hashlib.sha256(); written = 0
for ci in range(tchunks):
    ch = readn(inp, chs)
    ctype, _res, sz, _tsz = struct.unpack('<HHII', ch[:12])
    nbytes = sz * blk
    if ctype == 0xCAC1:  # RAW
        left = nbytes
        while left:
            buf = inp.read(min(left, 8*1024*1024))
            if not buf: raise EOFError("raw chunk truncated")
            outh.write(buf); sha.update(buf); written += len(buf); left -= len(buf)
    elif ctype == 0xCAC2:  # FILL
        fill = readn(inp, 4) * (blk // 4)
        for _ in range(sz):
            outh.write(fill); sha.update(fill); written += blk
    elif ctype == 0xCAC3:  # DONTCARE
        z = bytes(blk)
        for _ in range(sz):
            outh.write(z); sha.update(z); written += blk
    elif ctype == 0xCAC4:  # CRC
        readn(inp, 4)
    else:
        raise ValueError(f"chunk type {ctype:#x}")
    if ci % 40 == 0:
        print(f"  chunk {ci}/{tchunks} {written/1e9:.2f}GB", file=sys.stderr, flush=True)
outh.close()
print(f"DONE written={written} expected={tblks*blk}", file=sys.stderr)
print(sha.hexdigest())
