# `string_of_unix_time` prints the wrong second above 2^53 and crashes from ~6.8·10^16

**Affected:** `src/ml_bindings.ml:7-16` (`string_of_unix_time`), reached from
`src/adaptors/harness_interface.lem:1028` (`DT_GNU_PRELINKED` timestamps in
`main_elf --dynamic`), `master` @ `4464128`.

## Description

The timestamp goes `Nat_big_num` → `Int64` → `float` → `Unix.gmtime`.
Above 2^53 the float conversion rounds (the printed second is wrong); from
about 6.8·10^16 `gmtime` raises `Unix_error(EINVAL, "gmtime")`; from 2^63
`to_int64` raises `Failure "int64_of_big_int"`. The value is a 64-bit field
read from the file, so every one of these is reachable with a crafted file.

## Reproducer

API level, `master` (verbatim):

```
string_of_unix_time 0 -> 1970-1-1T00:00:00
string_of_unix_time 1700000000 -> 2023-11-14T22:13:20
string_of_unix_time 9007199254740993 -> 285428751-11-12T07:36:32
string_of_unix_time 100000000000000000 -> EXN: Unix.Unix_error(Unix.EINVAL, "gmtime", "")
string_of_unix_time 9223372036854775808 -> EXN: Failure("int64_of_big_int")
```

`main_elf --dynamic` on copies of `/bin/true` whose `DT_DEBUG` entry was
rewritten to `DT_GNU_PRELINKED` (0x6ffffdf5) with value 10^17
(`f11_big.elf`) and 2^53 + 1 (`f11_2p53.elf`), `master` (verbatim):

```
f11_big.elf exit=2
Fatal error: exception Unix.Unix_error(Unix.EINVAL, "gmtime", "")
f11_2p53.elf exit=0
 0x000000006ffffdf5 (GNU_PRELINKED)      285428751-11-12T07:36:32
```

Proposed fix (verbatim):

```
 0x000000006ffffdf5 (GNU_PRELINKED)      3168875820-9-6T09:46:40
 0x000000006ffffdf5 (GNU_PRELINKED)      285428751-11-12T07:36:33
```

## Observed vs expected

- 2^53 + 1 = 9007199254740993 is odd, so its seconds field must be
  `9007199254740993 mod 60 = 33`; `master` prints `:32` (rounded to 2^53).
  readelf agrees with the fix: `(GNU_PRELINKED) 285428751-11-12T07:36:33`.
- 10^17: readelf prints `<corrupt time val: ...>` (it rejects the value);
  an exact computation (proleptic Gregorian, integer arithmetic in Python)
  gives `3168875820-9-6T09:46:40`, as the fix does. Either way, not an
  uncaught exception.

## Impact

Wrong output or a crash on large prelink timestamps (only via crafted or
corrupt files in practice).

## Proposed remedy

Proposed fix: exact big-number civil-from-days
(H. Hinnant's algorithm), same output format. Checked identical to `master`
on 210 timestamps where `gmtime` is exact (epoch, leap days, century
boundaries, 9999-12-31, 200 random).

## Classification

**TRUE BUG** (rounding and host-limit crashes; low practical impact).
