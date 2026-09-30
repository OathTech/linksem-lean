# `Byte_sequence_wrapper.zero_pad_to_length` pads the wrong way

**Affected:** `src/byte_sequence_wrapper.ml:66-79`, `master` @ `4464128`.

## Description

The padding is computed as `bs.len - len`: a sequence shorter than `len` is
never padded, and a longer one gets `bs.len - len` ASCII `'0'` (0x30) bytes
appended. The specification (`byte_sequence.lem:75`: "pads (on the right)
consecutive zeros until the resulting byte sequence is len long") and the
generic implementation (`byte_sequence_generic.lem:70`) pad with NUL bytes
to `len`. The function is exported (`Byte_sequence.zero_pad_to_length`) but
not used by the model today.

## Reproducer

`master`, verbatim:

```
zero_pad_to_length 8 [01 02 03 04] -> 01 02 03 04
zero_pad_to_length 2 [01 02 03 04] -> 01 02 03 04 30 30
```

Proposed fix:

```
zero_pad_to_length 8 [01 02 03 04] -> 01 02 03 04 00 00 00 00
zero_pad_to_length 2 [01 02 03 04] -> 01 02 03 04
```

## Proposed remedy

Proposed fix: `if bs.len >= len then bs else concat [bs;
make (len - bs.len) '\000']`.

## Classification

**TRUE BUG** (latent).
