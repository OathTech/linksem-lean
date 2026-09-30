# OCaml target reps name functions that do not exist (`Uint64_wrapper.sub`, `logxor`)

**Affected:** `src/elf_types_native_uint.lem:305` (`elf64_addr_minus` →
`Uint64_wrapper.sub`) and `:1054` (`elf64_xword_lxor` →
`Uint64_wrapper.logxor`); `src/uint64_wrapper.ml` defines neither;
`master` @ `4464128`.

## Description

Both Lem functions are unused inside linksem, so the OCaml build never
generates a call and never notices. Any client that uses them fails to
compile.

## Reproducer

A client module:

```lem
open import Elf_types_native_uint
let diff (a : elf64_addr) (b : elf64_addr) : elf64_addr = elf64_addr_minus a b
let x (a : elf64_xword) (b : elf64_xword) : elf64_xword = elf64_xword_lxor a b
```

`lem -ocaml` (with linksem's modules) then `ocamlfind ocamlopt -c` against
`master`'s build, verbatim:

```
File "f3_client.ml", line 3, characters 92-110:
3 | let diff (a : Uint64_wrapper.uint64) (b : Uint64_wrapper.uint64) : Uint64_wrapper.uint64=  (Uint64_wrapper.sub a b)
                                                                                                ^^^^^^^^^^^^^^^^^^
Error: Unbound value Uint64_wrapper.sub
```

With the proposed fix applied (checked 2026-09-29) the same client compiles
(`Uint64_wrapper.minus a b`, `Uint64_wrapper.logxor a b`).

## Proposed remedy

Proposed fix: `elf64_addr_minus` →
`Uint64_wrapper.minus`; add `Uint64_wrapper.logxor`.

## Classification

**TRUE BUG** (latent).
