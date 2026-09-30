# Serialisers of the signed ELF types are `assert false`

**Affected:** `src/ml_bindings.ml:66-70` (`bytes_of_int32`, `bytes_of_int64`),
used by `bytes_of_elf32_sword`, `bytes_of_elf64_sword`, `bytes_of_elf64_sxword`
(`src/elf_types_native_uint.lem:905-906, 967-968, 1154-1155`), `master` @
`4464128`.

## Description

Both helpers are `assert false`, so serialising any `elf32_sword`,
`elf64_sword` or `elf64_sxword` crashes. No code in linksem calls these
serialisers today (checked: no use outside their definitions), so this is
latent: it bites a client of the library, or any future code that writes a
signed field through them.

## Reproducer

`master`, verbatim:

```
Elf_types_native_uint.bytes_of_elf32_sword Little (-1l) -> EXN: File "ml_bindings.ml", line 66, characters 35-41: Assertion failed
Elf_types_native_uint.bytes_of_elf64_sxword Little (-1L) -> EXN: File "ml_bindings.ml", line 69, characters 35-41: Assertion failed
```

Proposed fix:

```
Elf_types_native_uint.bytes_of_elf32_sword Little (-1l) -> ff ff ff ff
Elf_types_native_uint.bytes_of_elf64_sxword Little (-1L) -> ff ff ff ff ff ff ff ff
```

## Proposed remedy

Proposed fix: least significant byte first, the
order the Lem callers destructure (`let (b0, b1, b2, b3) = ... in [b0; b1;
b2; b3]` for Little, reversed for Big).

## Classification

**INTENDED GAP** (placeholder), latent; trivially fillable.
