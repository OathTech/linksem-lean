# ELF64 offsets/sizes ≥ 2^62 crash the tool (`int_of_big_int`)

**Affected:** `src/byte_sequence_wrapper.ml:158-162` (`big_num_dropbytes`,
`big_num_takebytes`), `master` @ `4464128`.

## Description

Both convert the length with `Nat_big_num.to_int`, which raises
`Failure "int_of_big_int"` for values ≥ 2^62 (OCaml's native int), before
the bounds check that would produce the model's own
`Fail "dropbytes: cannot drop more bytes than are contained in sequence"`.
Any ELF64 offset or size field ≥ 2^62 (`e_shoff`, `sh_offset`, `sh_size`,
`p_offset`, `p_filesz`) therefore crashes the tool instead of being
reported as a malformed file. An automated fuzzing pass found the boundary
exactly (2^62 − 1 is handled).

## Reproducer

A copy of `/bin/true` with `e_shoff` (offset 0x28) set to 2^62:

```sh
python3 -c "
d=bytearray(open('/bin/true','rb').read()); d[0x28:0x30]=(1<<62).to_bytes(8,'little'); open('f10.elf','wb').write(d)"
main_elf.opt --section-headers f10.elf
```

Verbatim, `master`:

```
upstream exit=2
Fatal error: exception Failure("int_of_big_int")
```

Proposed fix:

```
[!]: dropbytes: cannot drop more bytes than are contained in sequence
exit=0
```

API level (`master`):

```
big_num_dropbytes (2^62) [01 02] -> EXN: Failure("int_of_big_int")
big_num_dropbytes (2^62-1) [01 02] -> Fail dropbytes: cannot drop more bytes than are contained in sequence
```

## Observed vs expected

Oracle: `readelf -S f10.elf` reports the file as malformed and continues:

```
There are 30 section headers, starting at offset 0x4000000000000000:
readelf: Error: Reading 1920 bytes extends past end of file for section headers
```

## Impact

A crafted or corrupt file takes the tool down with an internal exception
rather than the model's error value; relevant to any use of linksem on
untrusted input.

## Proposed remedy

Proposed fix: compare the length with the sequence
length as big numbers first; convert only when it fits.

## Classification

**TRUE BUG** (the model specifies a `Fail` for exactly this case; the crash
comes from a host-language integer limit).
