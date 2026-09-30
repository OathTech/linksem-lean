# Question: `Byte_sequence_wrapper.compare` orders by descending length, and compares windows by representation

**Affected:** `src/byte_sequence_wrapper.ml:108-125` (`compare`), and the
polymorphic comparison of records containing a `byte_sequence` (OCaml's
`compare` on `{bytes; start; len}`), `master` @ `4464128`.

## Description

- `compare bs1 bs2` computes `bs2.len - bs1.len` first, so longer sequences
  sort FIRST, and equal-length ones by `Char.code c2 - Char.code c1` at the
  first differing byte, i.e. descending too. The generic implementation (`byte_sequence_generic.lem`,
  a list) would give ascending lexicographic order.
- Where a record holding a `byte_sequence` is compared with Lem's default
  (polymorphic) comparison, OCaml compares the representation `{bytes;
  start; len}`, i.e. the whole underlying buffer and the window position,
  not the window's contents: two equal windows of different buffers
  compare unequal.

## Reproducer

`master`, verbatim:

```
Byte_sequence_wrapper.compare [01] [02] -> 1
Byte_sequence_wrapper.compare [01] [01 00] -> 1
```

(`[01]` sorts after both `[02]` and the longer `[01 00]`.)

## Impact

Both are consistent total orders, so correctness is unaffected; they only
fix the iteration order of sets and maps keyed by byte sequences (and
hence output order), and the OCaml build's order differs from the prover
builds'. Our Lean build mirrors both exactly.

## Proposed remedy

None proposed unilaterally: changing the order changes output order. If
the intent is lexicographic, `compare` could compare contents; and a
`byte_sequence` type with a content-based comparison instance would make
the record case well-defined.

## Classification

**UNCLEAR** (a question: intended?).
