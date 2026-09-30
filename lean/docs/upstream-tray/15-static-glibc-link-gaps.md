# Static linking against glibc: capability gaps (GOT entry for an absolute symbol, IFUNC, TLS)

**Affected:** `src/abis/abis.lem:951` (`failwith ("matching definition for
GOT entry named " ^ symname ^ " has no range")`), `:1289`
(`R_X86_64_IRELATIVE` unimplemented), `:1280` (`R_X86_64_TPOFF32`
unimplemented), `master` @ `4464128`.

## Description

A statically linked hello-world is the natural end-to-end test of the
linker. It does not link, for several reasons in sequence:

1. `master` stops at the first `R_X86_64_REX_GOTPCRELX` (report 02).
2. With report 02's fix, it stops at a GOT slot for
   `_nl_current_LC_TIME_used`, which glibc defines as an **absolute**
   symbol (`SHN_ABS`, value 2) and references weakly through the GOT;
   linksem's GOT construction requires the definition to have a range
   inside an element.
3. Beyond that, glibc's 76 `STT_GNU_IFUNC` functions need
   `R_X86_64_IRELATIVE` (unimplemented, FIXME) and its 33
   `R_X86_64_TPOFF32` (local-exec TLS) are unimplemented (FIXME).

## Reproducer

```c
#include <stdio.h>
int main(void){ puts("hello"); return 3; }
```

`gcc -c -O0 -o h.o h.c`, then with Ubuntu 24.04's toolchain (gcc 13.3,
glibc 2.39) the inputs of `gcc -static`:

```
crt1.o crti.o crtbeginT.o h.o --start-group libgcc.a libgcc_eh.a libc.a --end-group crtend.o crtn.o
```

Verbatim (2026-09-29; `ld -static -o out` with those inputs, then
`main_link.opt -o out` with the same inputs):

```
hello
ld executable exit status: 3
== linksem-upstream: main_link exit 2; 1.33 s, 49000 KB
Fatal error: exception Failure("unrecognised relocation Invalid X86_64 relocation")
== with the proposed fix: main_link exit 2; 26.52 s, 951928 KB
Fatal error: exception Failure("matching definition for GOT entry named _nl_current_LC_TIME_used has no range")
```

`readelf -s libc.a` (one member): `GLOBAL DEFAULT ABS
_nl_current_LC_TIME_used` (value 2); others: `WEAK DEFAULT UND
_nl_current_LC_TIME_used`.

## Impact

linksem cannot link a C program against glibc statically, so its linker
can be exercised only on freestanding code.

## Proposed remedy

None prepared. In order: a GOT slot for an absolute symbol holds its value;
`R_X86_64_IRELATIVE` (plus the `__rela_iplt_start/end` range that glibc's
start-up code walks); `R_X86_64_TPOFF32` (needs the TLS segment layout,
cf. the FIXME at `abis.lem:936`).

## Classification

**INTENDED GAP** (FIXME-marked features).
