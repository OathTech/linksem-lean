#!/usr/bin/env python3
"""Seeded cases for the twin differential (OCaml src/*.ml helpers vs their
Lean twins in lean/handwritten). usage: gen_cases.py SEED N > cases.txt

One case per line: FUNCTION<TAB>ARG... Encodings: n:<decimal nat>,
i:<decimal int>, c:<byte 0-255>, s:<hex of the string's bytes>,
b:<hex bytes>@<k> (a byte sequence: those bytes with the first k dropped,
so sequences with a non-zero start are covered), l:<n,n,...> (list of nats).
Arguments stay inside each function's domain as the model uses it
(uint32/uint64 values already reduced, shift counts small, indices in
range where the OCaml signature takes an OCaml int); failures inside that
domain are expected to agree and are checked per process."""
import random, sys

seed, N = int(sys.argv[1]), int(sys.argv[2])
R = random.Random(seed)
B32, B64 = 1 << 32, 1 << 64
def edge(mod):
    return R.choice([0, 1, 2, mod - 1, mod - 2, mod >> 1, (mod >> 1) - 1, R.randrange(mod), R.randrange(mod)])
def byte(): return R.choice([0, 1, 0x7f, 0x80, 0xff, R.randrange(256), R.randrange(256)])
def raw(maxlen=24):
    n = R.choice([0, 1, 2, R.randrange(maxlen + 1)])
    return bytes(byte() for _ in range(n))
def bs():
    d = raw(); k = R.randrange(len(d) + 1) if d else 0
    return 'b:%s@%d' % (d.hex(), k)
def text(maxlen=24):
    alphabet = b'ab/.x0\\1&$:\x80\xc3\xa9 '
    n = R.choice([0, 1, R.randrange(maxlen + 1)])
    return bytes(R.choice(alphabet) for _ in range(n))
def s(t=None): return 's:' + (text() if t is None else t).hex()
def n(v): return 'n:%d' % v
def c(v): return 'c:%d' % v
def small(): return R.choice([0, 1, 7, 8, 31, 32, 33, 63, 64, 65, R.randrange(80)])

cases = []
def add(*a): cases.append('\t'.join(a))
for _ in range(N):
    # uint32 / unsigned char (values reduced mod 2^32 / 2^8, as the model keeps them)
    add('u32.add', n(edge(B32)), n(edge(B32)))
    add('u32.of_bigint', n(R.choice([edge(B32), edge(B64), R.randrange(1 << 80)])))
    add('u32.shift_left', n(edge(B32)), n(small()))
    add('u32.shift_right', n(edge(B32)), n(small()))
    add('u32.logand', n(edge(B32)), n(edge(B32)))
    add('u32.logor', n(edge(B32)), n(edge(B32)))
    add('u32.to_bytes', n(edge(B32)))
    add('u32.to_dual_bytes', n(edge(B32)))
    add('u32.of_quad', c(byte()), c(byte()), c(byte()), c(byte()))
    add('u32.uchar_of_bigint', n(R.choice([edge(256), edge(B32), R.randrange(1 << 70)])))
    add('u32.uchar_add', n(edge(256)), n(edge(256)))
    add('u32.uchar_shift_left', n(edge(256)), n(R.choice([0, 1, 7, 8, 9])))
    # uint64
    add('u64.add', n(edge(B64)), n(edge(B64)))
    add('u64.minus', n(edge(B64)), n(edge(B64)))
    add('u64.shift_left', n(edge(B64)), n(small()))
    add('u64.shift_right', n(edge(B64)), n(small()))
    add('u64.logand', n(edge(B64)), n(edge(B64)))
    add('u64.logor', n(edge(B64)), n(edge(B64)))
    add('u64.logxor', n(edge(B64)), n(edge(B64)))
    add('u64.of_bigint', n(R.choice([edge(B64), R.randrange(1 << 100)])))
    add('u64.to_bytes', n(edge(B64)))
    add('u64.of_oct', *[c(byte()) for _ in range(8)])
    # byte sequences
    add('bs.length', bs())
    add('bs.read_char', bs())
    add('bs.find_byte', bs(), c(byte()))
    add('bs.make', n(R.choice([0, 1, R.randrange(40)])), c(byte()))
    add('bs.concat', *[bs() for _ in range(R.randrange(4))])
    add('bs.zero_pad', n(R.randrange(40)), bs())
    add('bs.to_string', bs())
    add('bs.compare', bs(), bs())
    add('bs.equal', bs(), bs())
    add('bs.dropbytes', n(R.choice([0, 1, R.randrange(30), 1 << 62, 1 << 64])), bs())
    add('bs.takebytes', n(R.choice([0, 1, R.randrange(30), 1 << 62, 1 << 64])), bs())
    # ml_bindings
    add('ml.string_of_unix_time', n(R.choice([0, 1, 951782400, 4102444800, 253402300799, R.randrange(1 << 40), R.randrange(1 << 64)])))
    for pad in ['pad2', 'pad4', 'pad5', 'pad6', 'pad7', 'pad8', 'pad16', 'no_padding']:
        add('ml.hex_' + pad, n(R.choice([0, 1, 15, 16, 255, edge(B32), edge(B64), R.randrange(1 << 80)])))
    add('ml.hex_nat_pad2', n(R.choice([0, 9, 10, 99, 100, R.randrange(1000)])))
    add('ml.bytes_of_int32', 'i:%d' % R.choice([0, -1, 1, -(1 << 31), (1 << 31) - 1, R.randrange(-(1 << 31), 1 << 31)]))
    add('ml.bytes_of_int64', 'i:%d' % R.choice([0, -1, 1, -(1 << 63), (1 << 63) - 1, R.randrange(-(1 << 63), 1 << 63)]))
    add('ml.int32_of_quad', *[c(byte()) for _ in range(4)])
    add('ml.int64_of_oct', *[c(byte()) for _ in range(8)])
    t = text()
    add('ml.string_suffix', n(R.choice([0, 1, len(t), len(t) + 1, R.randrange(30)])), s(t))
    add('ml.string_prefix', n(R.choice([0, 1, len(t), len(t) + 1, R.randrange(30)])), s(t))
    add('ml.string_index_of', c(R.choice(b'ab/.x\x80')), s(t))
    add('ml.find_substring', s(text(3)), s(t))
    add('ml.split_string_on_char', s(t), c(R.choice(b'/a.\x80')))
    add('ml.string_replace', s(t), s(R.choice([b'a', b'$', b'ab', b'/'])), s(R.choice([b'', b'X', b'\\0', b'\\\\', b'&', b'\\1', b'\\', b'ok\\0ok'])))
    lst = [R.randrange(100) for _ in range(R.randrange(5))]
    add('ml.list_index_big_int', n(R.choice([0, 1, len(lst), R.randrange(8)])), 'l:' + ','.join(map(str, lst)))
    # filesystem (pure path functions)
    p = R.choice([b'', b'/', b'a', b'/a/b', b'a/b/', b'/a/../b', b'./a', b'a/./b/..', b'//x', b'/..', b'../../a', text(12)])
    add('fs.dirname', s(p)); add('fs.normalize', s(p)); add('fs.is_abs_path', s(p))
    add('fs.to_absolute', s(R.choice([b'/', b'/wd', b'/wd/sub/'])), s(p))
for line in cases:
    print(line)
