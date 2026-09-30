# `--debug-dump=info/dies`: a debug trace is printed to stdout for every compilation unit

**Affected:** `src/dwarf.lem:131-132` (`my_debug4`, `my_debug5` =
`print_endline`), called at `:2901` (`my_debug4 (pp_compilation_unit_header
cuh)`), `master` @ `4464128`.

## Description

`my_debug` … `my_debug3` are no-ops; `my_debug4`/`my_debug5` print to
stdout, and `my_debug4` runs for every compilation unit, so every
`--debug-dump=info` / `--debug-dump=dies` output carries a duplicate
"**Compilation Unit @ offset ..." block interleaved with the readelf-style
output.

## Reproducer

```c
int g(int x){return x+1;}
int main(void){return g(41);}
```

`gcc -g -gdwarf-4 -O0 -o d4 d.c; main_elf.opt --debug-dump=info d4`, `master`,
first lines of stdout (verbatim):

```
**Compilation Unit @ offset 0x0
  Compilation Unit @ offset 0x0:
   Length:        0x79 (32-bit)
   Version:       4
   Abbrev Offset: 0x0
   Pointer Size:  8

* emacs outline-mode configuration -*-outline-*-   C-c C-{t,a,d,e}
************** .debug_info section - full ************************
**Compilation Unit @ offset 0x0
  Compilation Unit @ offset 0x0:
```

(the header block appears twice on stdout: once as the trace, once in the
real output.) With the proposed fix applied (checked 2026-09-29):
`stdout_headers=1 stderr_headers=1`.

## Observed vs expected

`readelf --debug-dump=info d4` prints the header once. Expected: debug
traces off stdout.

## Impact

Every DWARF dump is polluted (7 extra lines per compilation unit), which
breaks diffing against readelf-style references.

## Proposed remedy

Proposed fix: `my_debug4/5` use
`Missing_pervasives.errln` (stderr).

## Classification

**TRUE BUG** (probably a left-over debug switch).
