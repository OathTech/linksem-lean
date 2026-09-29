#!/usr/bin/env python3
"""Deterministic ELF mutator for the OCaml-vs-Lean fuzz lane.

usage: mutate.py SEED PER_FILE OUTDIR FILE...

For every input FILE writes PER_FILE mutants OUTDIR/<stem>.<i>.elf and
prints their paths (one per line). Mutant i of a file depends only on
(SEED, file name, i): a finding is reproduced by re-running with the same
arguments. Strategies target the fields linksem decodes: ELF header,
section and program header fields set to boundary values (0, all ones,
2^31, 2^32, 2^62, 2^63, file size +- 1), random byte flips inside the
header tables, and truncation. 64-bit little-endian inputs get the
field-aware strategies; others get byte flips and truncation only.
"""
import os, random, struct, sys, zlib

BOUND64 = [0, 1, 0xffffffffffffffff, 1 << 31, 1 << 32, 1 << 62, 1 << 63, (1 << 63) - 1]
BOUND32 = [0, 1, 0xffffffff, 1 << 31, 0x7fffffff]
BOUND16 = [0, 1, 0xffff, 0x7fff]

def put(d, off, size, val):
    if off + size <= len(d):
        d[off:off + size] = (val % (1 << (8 * size))).to_bytes(size, 'little')

def fields64(d):
    """(offset, size) of decoded fields of an ELF64 LE file."""
    f = [(0x10, 2), (0x12, 2), (0x18, 8), (0x20, 8), (0x28, 8), (0x34, 2), (0x36, 2),
         (0x38, 2), (0x3a, 2), (0x3c, 2), (0x3e, 2)]
    try:
        phoff, shoff = struct.unpack_from('<QQ', d, 0x20)
        phentsz, phnum, shentsz, shnum = struct.unpack_from('<HHHH', d, 0x36)
    except struct.error:
        return f
    if 0 < phoff < len(d) and phentsz == 56:
        for i in range(min(phnum, 32)):
            b = phoff + 56 * i
            f += [(b, 4), (b + 4, 4), (b + 8, 8), (b + 16, 8), (b + 32, 8), (b + 40, 8), (b + 48, 8)]
    if 0 < shoff < len(d) and shentsz == 64:
        for i in range(min(shnum, 64)):
            b = shoff + 64 * i
            f += [(b, 4), (b + 4, 4), (b + 8, 8), (b + 16, 8), (b + 24, 8), (b + 32, 8),
                  (b + 40, 4), (b + 44, 4), (b + 48, 8), (b + 56, 8)]
    return [(o, s) for (o, s) in f if o + s <= len(d)]

def mutate(data, rng):
    d = bytearray(data)
    elf64le = len(d) >= 64 and d[:4] == b'\x7fELF' and d[4] == 2 and d[5] == 1
    kind = rng.choice(['field', 'field', 'field', 'flip', 'trunc'] if elf64le else ['flip', 'trunc'])
    if kind == 'field':
        for _ in range(rng.randint(1, 3)):
            off, size = rng.choice(fields64(d))
            pool = {8: BOUND64, 4: BOUND32, 2: BOUND16}[size] + [len(d) - 1, len(d), len(d) + 1]
            put(d, off, size, rng.choice(pool))
    elif kind == 'flip':
        hi = min(len(d), 4096)
        for _ in range(rng.randint(1, 8)):
            if hi:
                d[rng.randrange(hi)] ^= 1 << rng.randrange(8)
    else:
        d = d[:rng.randrange(max(1, len(d)))]
    return bytes(d)

def main():
    seed, per, out = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
    os.makedirs(out, exist_ok=True)
    for path in sys.argv[4:]:
        data = open(path, 'rb').read()
        stem = os.path.basename(path).replace('.', '_')
        tag = zlib.crc32(path.encode())
        for i in range(per):
            rng = random.Random((seed << 40) ^ (tag << 8) ^ i)
            p = os.path.join(out, '%s.%x.%d.elf' % (stem, tag, i))
            open(p, 'wb').write(mutate(data, rng))
            print(p)

if __name__ == '__main__':
    main()
