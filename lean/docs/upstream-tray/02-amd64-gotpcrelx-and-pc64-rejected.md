# amd64 linker rejects `R_X86_64_GOTPCRELX` / `R_X86_64_REX_GOTPCRELX`; `R_X86_64_PC64` unimplemented

**Affected:** `src/abis/amd64/abi_amd64_relocation.lem:27-59` (relocation
constants: 41 and 42 missing) and `:65-133` (`string_of_amd64_relocation_type`,
falling through to `"Invalid X86_64 relocation"`); `src/abis/abis.lem:407-410`
(`amd64_reloc_needs_got_slot`), `:1290` (`amd64_reloc`'s catch-all
`failwith ("unrecognised relocation " ^ ...)`) and `:1281` (`R_X86_64_PC64`
is `failwith "amd64_reloc: unimplemented R_X86_64_PC64" (* FIXME *)`);
`master` @ `4464128`.

## Description

The x86-64 psABI (version 1.0, 2015) added `R_X86_64_GOTPCRELX` (41) and
`R_X86_64_REX_GOTPCRELX` (42): GOT-indirect loads that a linker MAY relax
to a direct form, and otherwise computes exactly as `R_X86_64_GOTPCREL`
(G + GOT + A - P). GNU as emits them by default for every
`sym@GOTPCREL(%rip)` load (binutils >= 2.26). linksem does not know the
numbers, so `main_link` stops on any such object. Independently,
`R_X86_64_PC64` (S + A - P, 64-bit; e.g. a `.quad sym - .` across sections)
is a FIXME failure.

## Reproducer

`asm_relocs.s` (one use each of the common static-link relocations; `_start`
exits with a checksum of values read through them):

```asm
.globl _start
.text
_start:
  xor %ebx, %ebx
  mov $v32, %eax            # R_X86_64_32
  add (%rax), %ebx
  mov v32s, %ecx            # R_X86_64_32S
  add %ecx, %ebx
  movabs $v64, %rax         # R_X86_64_64
  add (%rax), %ebx
  mov vpc(%rip), %eax       # R_X86_64_PC32
  add %eax, %ebx
  mov gotv@GOTPCREL(%rip), %rax   # assembled as R_X86_64_REX_GOTPCRELX
  add (%rax), %ebx
  lea pc64tab(%rip), %rax
  mov (%rax), %rdx
  add %rax, %rdx
  add (%rdx), %ebx
  call fn
  add %eax, %ebx
  lea ptrs(%rip), %rax
  mov 8(%rax), %rax
  add (%rax), %ebx
  mov %ebx, %edi
  and $0x7f, %edi
  mov $60, %eax
  syscall
fn:
  mov $3, %eax
  ret
.data
.align 8
v32:  .long 1
v32s: .long 2
v64:  .long 4
vpc:  .long 8
gotv: .long 16
ptrs: .quad v32, gotv
pc64tab: .quad pcv - pc64tab    # R_X86_64_PC64 (pcv is in another section)
.section .rodata
.align 8
pcv:  .long 32
```

`as --64 -o asm_relocs.o asm_relocs.s; ld -static -e _start -o out
asm_relocs.o`, then `main_link.opt -o out asm_relocs.o` (reads `out` for
the ABI, writes `out.test-out`). Verbatim (2026-09-29):

```
      1 R_X86_64_32
      1 R_X86_64_32S
      3 R_X86_64_64
      3 R_X86_64_PC32
      1 R_X86_64_PC64
      1 R_X86_64_REX_GOTPCRELX
ld executable exit status: 82
== linksem-upstream: main_link exit 2
Fatal error: exception Failure("unrecognised relocation Invalid X86_64 relocation")
== with the proposed fix: main_link exit 0
linksem executable exit status: 82
```

PC64 alone (`tab: .quad val - tab`, `val` in `.rodata`; `_start` exits with
`*(tab + *tab)` = 32):

```
R_X86_64_PC32
R_X86_64_PC64
ld executable exit status: 32
== linksem-upstream: main_link exit 2
Fatal error: exception Failure("amd64_reloc: unimplemented R_X86_64_PC64")
== with the proposed fix: main_link exit 0
linksem executable exit status: 32
```

## Observed vs expected

Observed: uncaught `Failure`, no output. Expected: a linked executable
computing what ld's does (oracle: ld's executable's exit status, 82 and 32).

## Impact

Most objects produced by a current toolchain that load anything through the
GOT (PIC/PIE code, `-fno-plt`, any `@GOTPCREL` in assembly) cannot be linked:
e.g. Ubuntu 24.04's static `libc.a` has 74 `R_X86_64_REX_GOTPCRELX`
relocations, and linking a hello-world statically stops at the first one
(see report 15).

## Proposed remedy

Proposed fix: define `r_x86_64_gotpcrelx = 41` and
`r_x86_64_rex_gotpcrelx = 42` with their names; include both in
`amd64_reloc_needs_got_slot`; compute both as `R_X86_64_GOTPCREL` (no
relaxation, which the psABI makes optional); `R_X86_64_PC64` =
`i2n_signed 64 (s + a - site_addr)`.

## Classification

**TRUE BUG** for GOTPCRELX (a standard relocation, mandatory to accept since
2015, rejected with a misleading "Invalid X86_64 relocation"); **INTENDED
GAP** for PC64 (marked FIXME), fixed alongside because it is one line.
