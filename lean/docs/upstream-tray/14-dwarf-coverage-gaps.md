# DWARF reader gaps: DWARF 5 units, `DW_TAG_unspecified_type`, GNU location views

**Affected:** `src/dwarf.lem:2651-2672` (`parse_compilation_unit_header`:
DWARF 2-4 layout only), `:4840` (`analyse_type_info_top`, unknown tags),
`:3048-3090` (location lists), `master` @ `4464128`.

## Description

Three missing features, each an uncaught `Failure` on output of a current
GCC (13.3):

1. **DWARF 5** (GCC's default since 11): the unit header is read with the
   version-4 layout (version, abbrev offset, address size), but DWARF 5
   has version, `unit_type`, address size, abbrev offset. The reader gets
   a garbage abbrev offset and address size 0, then fails.
2. **`DW_TAG_unspecified_type`** (0x3b; e.g. C++ `decltype(nullptr)`; we
   also met it in OCaml-compiled objects) is not recognised by the type
   analysis.
3. **Location views** (a GNU extension, emitted by default by current GCC
   for optimised code): `.debug_loc` entries preceded by view pairs are not parsed.

## Reproducers

(`main_elf.opt` of `master`, verbatim, 2026-09-29.)

1. `int g(int x){return x+1;} int main(void){return g(41);}`, `gcc -g -O0`:

```
exit=2
Fatal error: exception Failure("mydrop of debug_abbrev")
```
   linksem's own header dump just before the failure:
```
   Version:       5
   Abbrev Offset: 0x801
   Pointer Size:  0
```
   `readelf --debug-dump=info`: `Version: 5`, `Abbrev Offset: 0`,
   `Pointer Size: 8`. With `-gdwarf-4` the same program dumps fine.

2. `#include <cstddef>` / `std::nullptr_t np;` /
   `int main(){return np==nullptr?0:1;}`, `g++ -g -gdwarf-4 -O0`:

```
exit=2
Fatal error: exception Failure("analyse_type_info_top didn't recognise tag: 0x3b for DIE <da>/<b>/<0>")
```
   readelf: `<1><da>: Abbrev Number: 12 (DW_TAG_unspecified_type)`,
   `DW_AT_name: decltype(nullptr)`.

3. A 15-line C program (lists, unions, function pointers, `printf`),
   `gcc -g -gdwarf-4 -O2`:

```
exit=2
Fatal error: exception Failure("parse_location_list: Parse fail\nparse_n_bytes n=0x1080 at pc_offset = 0x7e\n")
```
   `readelf --debug-dump=loc` shows `location view pair` entries; compiled
   with `-gno-variable-location-views` the same program dumps fine (exit 0,
   1964 lines).

## Impact

`--debug-dump` fails on most binaries a current default toolchain produces
(1 and 3 alone cover `gcc -g` and `gcc -g -O2`).

## Proposed remedy

None prepared (features, not fixes): DWARF 5 unit headers (and its new
forms/sections: `.debug_str_offsets`, `.debug_addr`, `.debug_rnglists`,
`.debug_loclists`), tag 0x3b as a named type without size, and skipping
(or reading) view pairs in `.debug_loc`. A graceful error value instead of
`failwith` would already help callers.

## Classification

**INTENDED GAP** (missing features; behaviour is a crash, not wrong output).
