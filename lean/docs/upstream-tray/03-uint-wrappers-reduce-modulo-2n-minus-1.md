# `Uint32_wrapper` / `Uint64_wrapper` reduce modulo 2^N − 1 instead of 2^N

**Affected:** `src/uint32_wrapper.ml:4-8` (`max_int = 2^32 - 1`) and every
reduction using it (lines 11, 19, 23, 27, 34, 38, 42, 46, 66);
`src/uint64_wrapper.ml:4-8` and lines 11, 15, 19, 23, 27, 31, 35, 39, 43, 81;
`master` @ `4464128`.

## Description

Every arithmetic operation reduces with `Nat_big_num.modulus _ max_int`
where `max_int` is 2^N − 1. Arithmetic modulo 2^N − 1 is not N-bit unsigned
arithmetic: 2^N − 1 itself becomes 0, 2^N becomes 1, and subtraction wraps
to 2^N − 2.

## Reproducer

```ocaml
let p s f = Printf.printf "%s = %s\n" s (try Nat_big_num.to_string (f ()) with e -> "EXN " ^ Printexc.to_string e)
let b = Nat_big_num.of_string
let () =
  p "Uint32_wrapper.of_bigint 0xFFFFFFFF" (fun () -> Uint32_wrapper.to_bigint (Uint32_wrapper.of_bigint (b "4294967295")));
  p "Uint32_wrapper.of_bigint 0x100000000" (fun () -> Uint32_wrapper.to_bigint (Uint32_wrapper.of_bigint (b "4294967296")));
  p "Uint64_wrapper.of_bigint (2^64-1)" (fun () -> Uint64_wrapper.to_bigint (Uint64_wrapper.of_bigint (b "18446744073709551615")));
  p "Uint64_wrapper.minus 0 1" (fun () -> Uint64_wrapper.to_bigint (Uint64_wrapper.minus (Uint64_wrapper.of_bigint (b "0")) (Uint64_wrapper.of_bigint (b "1"))))
```

linked against `src/build_zarith/linksem.cmxa` of `master`; verbatim:

```
Uint32_wrapper.of_bigint 0xFFFFFFFF = 0
Uint32_wrapper.of_bigint 0x100000000 = 1
Uint64_wrapper.of_bigint (2^64-1) = 0
Uint64_wrapper.minus 0 1 = 18446744073709551614
```

With the proposed fix applied (checked 2026-09-29):

```
Uint32_wrapper.of_bigint 0xFFFFFFFF = 4294967295
Uint32_wrapper.of_bigint 0x100000000 = 0
Uint64_wrapper.of_bigint (2^64-1) = 18446744073709551615
Uint64_wrapper.minus 0 1 = 18446744073709551615
```

## Observed vs expected

Expected: N-bit unsigned arithmetic (the Isabelle/HOL target reps of the
same Lem types are N-bit words: `uint32`/`uint64`, `n2w`).

## Impact

These back every ELF address/offset/word type (`elf64_addr`, `elf64_xword`,
`elf32_word`, ...). Values READ from a file are unaffected (`of_quad`/`of_oct`
build them without reducing, which is why `main_elf` prints `e_flags =
0xffffffff` correctly), but every value CONSTRUCTED from a natural
(`elf64_addr_of_natural`, `elf64_xword_of_natural`, ...: 131 uses, in the
linker and the serialisers) or computed with `add`/`minus`/shifts is: the
all-ones sentinel (`(Elf64_Addr)-1`, `0xffffffff`) becomes 0, and
wrap-around arithmetic is off by one.

## Proposed remedy

Proposed fix: reduce modulo 2^N (a new `modulus`
binding; `max_int` kept for its other uses).

## Classification

**TRUE BUG.**
