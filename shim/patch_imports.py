#!/usr/bin/env python3
"""Rewrite the import-DLL name of a PE file in place (copy).

Used to point Apple's D3DMetal Wine modules at gptk.dll instead of ntdll.dll
for the __wine_unix_call import that modern Wine no longer exports.
"""
import struct
import sys


def patch(src, dst, old_name, new_name):
    data = bytearray(open(src, "rb").read())
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    nsec = struct.unpack_from("<H", data, pe + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe + 20)[0]
    opt = pe + 24
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + (112 if magic == 0x20B else 96)
    imp_rva = struct.unpack_from("<I", data, dd + 8)[0]
    secs = []
    so = opt + opt_size
    for i in range(nsec):
        vs, va, raw, ro = struct.unpack_from("<IIII", data, so + i * 40 + 8)
        secs.append((va, max(vs, raw), ro))

    def r2o(rva):
        for va, size, ro in secs:
            if va <= rva < va + size:
                return rva - va + ro
        raise ValueError("rva %#x outside sections" % rva)

    patched = 0
    o = r2o(imp_rva)
    while True:
        name_rva = struct.unpack_from("<I", data, o + 12)[0]
        if name_rva == 0:
            break
        no = r2o(name_rva)
        end = data.index(b"\0", no)
        if data[no:end].lower() == old_name.lower().encode():
            if len(new_name) > end - no:
                raise SystemExit("new name longer than %d" % (end - no))
            data[no:end + 1] = new_name.encode() + b"\0" * (end - no + 1 - len(new_name))
            patched += 1
        o += 20
    open(dst, "wb").write(data)
    return patched


if __name__ == "__main__":
    src, dst, old, new = sys.argv[1:5]
    n = patch(src, dst, old, new)
    print("%s -> %s: patched %d import(s) %s -> %s" % (src, dst, n, old, new))
