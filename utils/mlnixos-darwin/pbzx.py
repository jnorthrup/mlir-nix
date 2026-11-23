#!/usr/bin/env python3
"""pbzx decoder (Apple's chunked-xz Payload format):  pbzx.py IN OUT
A pbzx stream is "pbzx", a big-endian u64 of flags, then chunks: u64 flags (bit 24 = another chunk follows), u64 length,
then `length` bytes, which are an xz stream or, when not, the raw bytes.  The output of an SDK payload is a cpio archive."""
import lzma, struct, sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, "rb") as f, open(dst, "wb") as out:
    if f.read(4) != b"pbzx":
        raise SystemExit(f"{src}: not a pbzx stream")
    flags = struct.unpack(">Q", f.read(8))[0]
    n = 0
    while flags & (1 << 24):
        flags, length = struct.unpack(">QQ", f.read(16))
        chunk = f.read(length)
        if len(chunk) != length:
            raise SystemExit(f"{src}: chunk {n} cut short")
        out.write(lzma.decompress(chunk) if chunk[:6] == b"\xfd7zXZ\x00" else chunk)
        n += 1
print(f"pbzx: {n} chunks -> {dst}")
