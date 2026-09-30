# `unsigned_char` does not wrap at 256; `byte_of_unsigned_char` then raises

**Affected:** `src/elf_types_native_uint.lem:53` (`unsigned_char_of_natural`
→ `Uint32_wrapper.of_bigint`), `:83` (`unsigned_char_lshift` →
`Uint32_wrapper.shift_left`), `:102` (`unsigned_char_plus` →
`Uint32_wrapper.add`), `:735` (`unsigned_char_of_elf32_word` → identity),
`:129` (`byte_of_unsigned_char` → `Char.chr`), `master` @ `4464128`.

## Description

`unsigned_char` is represented by `Uint32_wrapper` and its OCaml target reps
are the 32-bit operations, so nothing wraps at 256, contrary to the
documented behaviour ("wrapping around if the size of the nat exceeds the
storage capacity of an unsigned char", `:47-50`) and to the Isabelle/HOL
reps (8-bit words). A value above 255 then makes `byte_of_unsigned_char`
raise.

## Reproducer

(`unsigned_char_of_natural` and `unsigned_char_plus` are inlined target
reps, so the probe calls the functions they map to.) `master`, verbatim:

```
unsigned_char_of_natural 256 (OCaml rep: Uint32_wrapper.of_bigint) -> 256
bytes_of_unsigned_char (unsigned_char_plus 255 1) (rep: Uint32_wrapper.add) -> EXN: Invalid_argument("Char.chr")
```

Proposed fix:

```
unsigned_char_of_natural 256 (rep: Uint32_wrapper.uchar_of_bigint) -> 0
bytes_of_unsigned_char (unsigned_char_plus 255 1) (rep: uchar_add) -> 00
```

## Impact

Reachable only with invalid inputs (e.g. `make_symbol_info` with a binding
≥ 16 overflows `binding << 4`); then a crash instead of the specified
wrap. The OCaml build disagrees with the prover builds here.

## Proposed remedy

Proposed fix: `Uint32_wrapper.uchar_of_bigint`,
`uchar_add`, `uchar_shift_left` (modulo 256) as the reps of construction,
`plus`, `lshift` and the `elf32_word` conversion (`land`/`lor`/`rshift`
cannot leave [0, 256)).

## Classification

**TRUE BUG** (contrary to the in-source specification; low impact).
