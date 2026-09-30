# Linker binds a global reference to another file's `static`; COMMON and weak symbols not unified

**Affected:** `src/linkable_list.lem:154-290` (`resolve_one_reference_default`:
the candidate filter `def_is_eligible` from line 184, in particular line 236
`if ref_is_to_defined_or_common_symbol then def_sym_is_ref_sym`, and the
tie-break from line 260), `master` @ `4464128`.

## Description

When `main_link` resolves a symbol reference, the candidate definitions are
every `SymbolDef` in every input, **including LOCAL (file-static)
definitions of other files**. A local definition that happens to come first
wins: `extern int counter;` in one file is bound to another file's `static
int counter`. The resulting executable is silently wrong.

Separately, a reference through a symbol the referencing object *itself*
defines (a COMMON symbol, or a weak definition) is bound only to that
symbol (`def_sym_is_ref_sym`) and never competes with the other objects'
definitions of the same name: two objects' COMMON `shared_counter`s are not
merged, and a weak definition beats the strong one in either link order.

## Reproducer

Freestanding x86-64 programs (no libc; each exits with a computed status),
compiled with `gcc -c -O0 -fno-pie -ffreestanding -fno-stack-protector
-fno-builtin -nostdlib -fno-asynchronous-unwind-tables -fcommon`:

```c
/* exit.h */
static inline void sys_exit(long code) {
  __asm__ volatile ("mov $60, %%eax\n\tsyscall" : : "D"(code) : "rax", "rcx", "r11", "memory");
  __builtin_unreachable();
}
/* c_static_a.c */ static int counter = 5;  int get_local(void) { return counter; }
/* c_static_b.c */ #include "exit.h"
                   extern int counter; extern int get_local(void);
                   void _start(void) { sys_exit(counter * 10 + get_local()); }
/* c_static_c.c */ int counter = 9;
/* c_weak_a.c */   #include "exit.h"
                   __attribute__((weak)) int maybe_defined = 1;
                   void _start(void) { sys_exit(maybe_defined); }
/* c_weak_b.c */   int maybe_defined = 40;
/* c_comm_a.c */   #include "exit.h"
                   int shared_counter; extern void bump(void);
                   void _start(void) { bump(); bump(); sys_exit(shared_counter + 7); }
/* c_comm_b.c */   int shared_counter; void bump(void) { shared_counter++; }
```

For each link: `ld -static -e _start -o out OBJS`, run `./out`; then
`main_link.opt -o out OBJS` (it reads `out` to pick the ABI and writes
`out.test-out`), run `./out.test-out`. Verbatim (2026-09-29):

```
static_first: link c_static_a.o c_static_b.o c_static_c.o -> exit status: ld 95, upstream linksem 55, patched linksem 95
static_last: link c_static_b.o c_static_c.o c_static_a.o -> exit status: ld 95, upstream linksem 95, patched linksem 95
weak_strong: link c_weak_a.o c_weak_b.o -> exit status: ld 40, upstream linksem 1, patched linksem 40
strong_weak: link c_weak_b.o c_weak_a.o -> exit status: ld 40, upstream linksem 1, patched linksem 40
common: link c_comm_a.o c_comm_b.o -> exit status: ld 9, upstream linksem 7, patched linksem 9
```

("upstream linksem" = `master` @ `4464128`; "patched" = branch
the proposed fix.)

## Observed vs expected

- `static_first`: 55 = 5*10 + 5, i.e. `counter` in `c_static_b.c` bound to
  `c_static_a.c`'s static; expected 95 = 9*10 + 5 (ld). Link order decides
  (`static_last` is right by luck).
- `weak_strong`/`strong_weak`: 1 (the weak definition) instead of 40.
- `common`: 7 (two separate `shared_counter`s; the one `_start` reads was
  never incremented) instead of 9.

Oracle: ld's executable of the same objects.

## Impact

Silent miscompilation for common C patterns: any program with a file-static
variable or function whose name matches a global elsewhere (e.g. two
`static int count;` helpers plus a global `count`), any use of weak
defaults overridden by strong definitions, and tentative definitions
(`-fcommon`, the default before GCC 10 and still common in older code). No
diagnostic is produced.

## Proposed remedy

Proposed fix: only a LOCAL symbol resolves
to itself; a local definition never satisfies another symbol's reference;
a global/weak/COMMON symbol an object defines competes with the other
objects' definitions; ties rank strong over COMMON over weak (the largest
COMMON among COMMONs), then the existing command-line / left-to-right
order. Archive members are not searched to override a weak or COMMON
definition (conservative). Remaining differences from ld: two strong
definitions of one name are not an error (the first wins), and an unchosen
COMMON symbol is still allocated (unused space).

## Classification

**TRUE BUG.** Contradicts ELF symbol-binding rules (LOCAL symbols are not
visible outside their object; STB_WEAK yields to STB_GLOBAL; COMMON symbols
are merged) and ld's behaviour, silently.
