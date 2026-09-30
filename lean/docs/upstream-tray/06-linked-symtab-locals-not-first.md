# Linked executable's `.symtab`: locals interleaved with globals, `sh_info = 0`

**Affected:** `src/elf64_file_of_elf_memory_image.lem:226-285` (the symbol
list, in image order) and `:380` (`.symtab` header `elf64_section_info = 0`),
`master` @ `4464128`.

## Description

The ELF specification requires all STB_LOCAL symbols of a symbol table to
precede the others, with the section header's `sh_info` holding the index
of the first non-local symbol. `main_link`'s output lists symbols in image
order (locals and globals interleaved) and sets `sh_info` to 0.

## Reproducer

Any link; e.g. the three objects of report 01 (`c_static_b.o c_static_c.o
c_static_a.o`). `readelf -W -a out.test-out`, verbatim (first lines):

```
readelf: Warning: local symbol 0 found at index >= .symtab's sh_info value of 0
readelf: Warning: local symbol 1 found at index >= .symtab's sh_info value of 0
readelf: Warning: local symbol 2 found at index >= .symtab's sh_info value of 0
```

Warning count and `.symtab` header, `master` vs branch
the proposed fix (verbatim):

```
linksem-upstream: readelf warnings=15
  [10] .symtab           SYMTAB          0000000000000000 001108 0001b0 18     11   0  8
     10 LOCAL       1 GLOBAL       4 LOCAL       2 GLOBAL       1 LOCAL
with the proposed fix: readelf warnings=0
  [10] .symtab           SYMTAB          0000000000000000 001108 0001b0 18     11  15  8
     15 LOCAL       3 GLOBAL
```

(the last line of each: runs of binding in symbol-table order.)

## Observed vs expected

Oracle: readelf's conformance check (0 warnings on ld's output of the same
link) and the ELF gABI rule quoted above.

## Impact

Every executable `main_link` writes is non-conforming; tools that rely on
`sh_info` (to skip locals, e.g. when looking up globals) misread it.

## Proposed remedy

Proposed fix: stable partition (locals first;
the null entry, LOCAL, stays at index 0), `sh_info` = number of locals.

## Classification

**TRUE BUG.**
