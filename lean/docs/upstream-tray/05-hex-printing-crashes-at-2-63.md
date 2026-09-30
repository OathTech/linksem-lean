# Hex printing raises on values ≥ 2^63; `main_elf` cannot print upper-half addresses

**Affected:** `src/ml_bindings.ml:22-64` (`hex_string_of_big_int_pad2/4/5/6/7/8/16`
and `_no_padding`), `master` @ `4464128`.

## Description

All go through `Nat_big_num.to_int64` and `Printf "%0NLx"`. `to_int64` raises
`Failure "int64_of_big_int"` for every value ≥ 2^63, i.e. every address in
the upper half of the 64-bit space (MIPS64 `xkphys`/`kseg` addresses,
x86-64 kernel images, `-1` sentinels).

## Reproducer

linksem's own test binary `test/mixed-binaries/mips64-test_raw_lui.elf`
(`.text` at `0x9000000040000000`):

```
$ main_elf.opt --section-headers test/mixed-binaries/mips64-test_raw_lui.elf
exit=2
Fatal error: exception Failure("int64_of_big_int")
```

(verbatim, `master`, 2026-09-29). With the proposed fix applied (checked 2026-09-29)
the table prints; its `.text` line (verbatim):

```
  [ 1] .text             PROGBITS        9000000040000000 010000 000030 00  AX  0   0  4
```

## Observed vs expected

Oracle, `readelf -S` on the same file:

```
  [ 1] .text             PROGBITS         9000000040000000  00010000
       0000000000000030  0000000000000000  AX       0     0     4
```

## Impact

`main_elf` crashes on any ELF64 file with an upper-half address in a
printed field. Values below 2^63 are unaffected (e.g. an x86-64 entry
point `0xffffffff81000000` patched into `/bin/true`'s header still prints,
as that field goes through a different path).

## Proposed remedy

Proposed fix: format the big number directly (digit
by digit); negative values keep their previous 64-bit two's-complement
rendering, so the output is unchanged wherever it used to succeed. On our
183-file corpus × 7 flags, an OCaml build carrying all the fixes in this
tray differs from `master`'s output only on this file (3 flags), where
`master` crashed.

## Classification

**TRUE BUG.**
