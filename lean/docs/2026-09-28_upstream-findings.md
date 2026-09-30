# linksem upstream findings (Lean port, 2026-09-28)

Branch `lean/port`. Findings about linksem itself, surfaced while porting it
to Lean with lem-lean's Lean backend. Findings about the backend are recorded
in lem-lean `doc/lean-backend/2026-09-28_linksem-findings.md`; upstream bug
reports are drafted in `upstream-tray/`.

Provenance: [AGENT] = decided by the agent doing the port; [USER] = by the
operator. "Confirmed" means reproduced by an executed probe against the
upstream build, not inferred from reading.

Policy [USER 2026-09-30]: the port is faithful to upstream. Upstream is
changed only where it wrongly models the real-world artifact in a way our
use case exercises; malformed / hostile input is in scope, so explicit
crashes or misbehaviour on adversary-chosen input count. A deliberate
refusal (the model's own error) is not misbehaviour. Everything else is
MIRRORED by the port (the Lean twins reproduce upstream, bugs included) and
recorded here and in the tray. Host machine-integer limits the port does
not fix are refused by Lean (loud failure). The history of this policy: the
first iteration (branch `lean/setup`, archived) fixed more; see the tray.

## Status

| Item | What | In the port |
|------|------|-------------|
| F1 | uint32/uint64 wrappers reduce modulo 2^N - 1 | mirrored (not exercised by our use case) |
| F2 | signed serialisers are `assert false` | mirrored (upstream gap) |
| F3 | target reps naming functions that do not exist | mirrored (latent) |
| F4 | `byte_sequence_generic.lem` does not parse | not on the port's path; not changed |
| F5 | hex printing raises on values >= 2^63 | FIXED (crash on a real corpus file) |
| F6 | `zero_pad_to_length` pads the wrong way | mirrored (no caller) |
| F7 | DWARF coverage gaps | mirrored (upstream gap) |
| F8 | DWARF debug trace on stdout | mirrored |
| F9 | `unsigned_char` does not wrap at 256 | mirrored (never exceeds 255 in the model) |
| F10 | crash on lengths >= 2^62 | FIXED (crash on crafted input) |
| F11 | `string_of_unix_time` raises / rounds on large values | FIXED (crash / wrong output on crafted input) |
| F12 | Lean twin of `string_replace` ignored the template | fixed (our bug) |
| F13 | linker binds a reference to another file's static; COMMON/weak not unified | FIXED (silent miscompilation) |
| F14 | linked `.symtab`: locals not first, `sh_info = 0` | FIXED (malformed output) |
| F15 | GOTPCRELX rejected, PC64 unimplemented | mirrored (a refusal; not needed for parity) |
| F16 | static glibc programs cannot be linked | mirrored (upstream gap) |
| F17 | allocation-size crash reported as `int_of_big_int` | FIXED as an explicit `Out_of_memory` (no modelling decision) |
| F18 | `is_abs_path ""` raises | not changed (latent, no caller in the port) |

## F1. `Uint32_wrapper` / `Uint64_wrapper` compute modulo 2^N − 1 (confirmed; mirrored)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

`src/uint32_wrapper.ml` and `src/uint64_wrapper.ml` reduce every operation
with `Nat_big_num.modulus _ max_int` where `max_int = 2^N − 1`. Probe against
the upstream build (verbatim output):

    Uint32.of_bigint 0xFFFFFFFF = 0
    Uint32.of_bigint 0x100000000 = 1
    Uint32.add 0xFFFFFFFF 0 = 0
    Uint64.of_bigint 2^64-1 = 0
    Uint64.minus 0 1 = 18446744073709551614
    Uint64.shift_left 1 63 |> shift_left 1 = 1

These back every ELF address/offset/word type (`elf64_addr`, `elf64_xword`,
`elf32_word`, ...), so any value equal to 2^N − 1 (a common "all ones"
sentinel, e.g. `(Elf64_Addr)-1`) reads as 0, and wrap-around arithmetic is
off by one. Fix [AGENT]: reduce modulo 2^N (`modulus`). After the fix the
same probe gives 4294967295, 0, 4294967295, 18446744073709551615,
18446744073709551615, 0.

## F2. `bytes_of_int32` / `bytes_of_int64` are `assert false` (upstream gap, mirrored)

`src/ml_bindings.ml` implements the serialisers of the signed ELF types
(`elf32_sword`, `elf64_sword`, `elf64_sxword`) as `assert false`. Not reached
by the `main_elf` flags on the corpus (`--in-out` re-serialises section
contents as raw bytes), but any path writing a signed field would crash.
Originally implemented on both sides [AGENT] (least-significant byte first);
REVERTED 2026-09-30: an unimplemented function is an upstream gap, and gaps
are mirrored, not closed, unless they are unambiguous blockers [USER
2026-09-30] (closing one means making modelling decisions upstream has not
made). The Lean twin mirrors the failure (`failwithI`). Tray report 11
stays, as a gap report without a patch.

## F3. Target reps naming functions that do not exist (latent; mirrored)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

`elf64_addr_minus`'s OCaml rep is `Uint64_wrapper.sub` and
`elf64_xword_lxor`'s is `Uint64_wrapper.logxor`; neither exists. Both
functions are unused, so OCaml never noticed. Fix [AGENT]: the rep of
`elf64_addr_minus` is `Uint64_wrapper.minus`; `logxor` is added.

## F4. `byte_sequence_generic.lem` does not parse (confirmed; not changed)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

Two unterminated `match`es in `find_byte`; `-isa`, `-coq`, `-hol` and `-lean`
all failed on the file ("Syntax error", line 40), so the prover extractions
cannot have been run for some time. Fixed in the first commit on the branch.

Update 2026-09-29 (upstream tray, report 08): the generic `find_byte` also
never compared bytes at all, lacked `let rec`, mis-parenthesised `Just n +
1` and missed `open import Maybe`; all fixed on `upstream-pr/generic-find-byte`.

## F5. Hex printing raises on values ≥ 2^63 (confirmed, fixed)

The `hex_string_of_big_int_pad*` family formatted through
`Nat_big_num.to_int64`. Probe against the upstream build:

    hex_string_of_big_int_pad16 (2^64 - 2^31)  ->  EXN: Failure("int64_of_big_int")

so `main_elf` cannot print any upper-half address (kernel images, `-1`
sentinels). Fix [AGENT]: format the big number directly; values below 2^63
print exactly as before (negative values keep their 64-bit two's-complement
rendering), so output is unchanged wherever it used to succeed.

## F6. `zero_pad_to_length` pads the wrong way (confirmed, latent; mirrored)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

`byte_sequence_wrapper.ml` computed the padding as `bs.len - len`. Probe:

    pad to 8: [01 02 03 04]          (not padded)
    pad to 2: [01 02 03 04 30 30]    (ASCII '0' bytes appended)

The generic implementation (`byte_sequence_generic.lem`) specifies right-
padding with NUL bytes to `len`. Not used by the model today. Fix [AGENT]:
follow the generic specification.

## F7. DWARF coverage gaps (confirmed, not fixed)

Identical failures in the OCaml and Lean builds on the corpus (both report
the same message):
- DWARF 5 units (GCC's default since 11) are read with the version-4 header
  layout ("Pointer Size: 0", a garbage abbrev offset) and then fail with
  `mydrop of debug_abbrev`; `-gdwarf-4` binaries work.
- `DW_TAG_unspecified_type` (0x3b) is not recognised
  (`analyse_type_info_top didn't recognise tag: 0x3b`; OCaml-compiled objects).
- Location lists in optimised (`-O2`) DWARF-4 code fail
  (`parse_location_list: Parse fail`).
- One `parse_die returned Nothing` (a large SBCL object).
Missing features rather than wrong behaviour; recorded, not fixed.

Update 2026-09-29 (upstream tray, report 14): the location-list failure is
caused by GCC's location views (`DW_LLE_view_pair`); the same program built
with `-gno-variable-location-views` dumps fine.

## F8. Debug trace on stdout in `--debug-dump` (confirmed; mirrored)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

`dwarf.lem`'s `my_debug4`/`my_debug5` printed to stdout (`my_debug` ..
`my_debug3` are no-ops), and `my_debug4 (pp_compilation_unit_header cuh)`
runs for every compilation unit, so every `--debug-dump=info`/`dies` output
had a duplicate `**Compilation Unit @ offset ...` block interleaved (7 lines
per CU on the probe binary). Found by the differential: Lean erases the
unused pure `let _ = print ...` (the documented backend limitation), OCaml
prints it. Fix [AGENT]: the two debug printers write to stderr
(`Missing_pervasives.errln`); stdout is now identical on both targets.

## F9. `unsigned_char` does not wrap at 256 (mirrored; was N3)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

`unsigned_char` is backed by `Uint32_wrapper`, and its operations used the
32-bit ones: `unsigned_char_of_natural 256` was 256, `unsigned_char_plus 255
1` was 256, `unsigned_char_of_elf32_word` was the identity, and
`byte_of_unsigned_char` then raised (`Char.chr`) on any value above 255.
linksem's own specification says the conversion wraps "if the size of the
nat exceeds the storage capacity of an unsigned char", and the Isabelle/HOL
reps are 8-bit words. Reachable only with invalid inputs (e.g.
`make_symbol_info` with a binding >= 16). Fix [USER 2026-09-28: upstream
flaws are fixed, per the charter; AGENT design]: `Uint32_wrapper.uchar_*`
(modulo 256) on both sides for construction, `plus`, `lshift` and the word
conversion (`land`/`lor`/`rshift` cannot leave [0, 256)).

## Audit of the Lean port (2026-09-29)

[USER 2026-09-29] asked for independent auditors; five ran (hand-written
twins, target-rep mappings, translation-level semantics, adversarial fuzzing
of ~23,000 cases, coverage of the modules `main_elf` does not reach). Every
reported discrepancy was reproduced before acting. Backend-side results are
in lem-lean's record (audit A1-A4); linksem-side:

### F10. Lengths >= 2^62 raised in OCaml (confirmed, fixed)

`big_num_dropbytes`/`big_num_takebytes` converted the length with
`Nat_big_num.to_int`, which raises `Failure "int_of_big_int"` from 2^62 (the
fuzzer found the boundary exactly: 2^62 - 1 agrees). Any ELF64 offset or
size field >= 2^62 crashed OCaml (`e_shoff`, `sh_offset`, `sh_size`,
`p_offset`, `p_filesz`), where the logical result, and Lean's, is the
model's own `dropbytes`/`takebytes` failure. Fix: compare as big numbers
first (the lem-lean ruling [USER 2026-09-03]: OCaml's hard-coded int limits
are deviations; the logical semantics is the reference).

### F11. `string_of_unix_time` rounded / raised for large timestamps (confirmed, fixed)

Int64 -> float -> `Unix.gmtime`: DT_GNU_PRELINKED values above 2^53 printed
the wrong second, and from ~6.8e16 raised `Unix_error(EINVAL, "gmtime")`
(2^63: `Failure "int64_of_big_int"`). Fix: exact big-number civil-from-days
arithmetic, the Lean twin's algorithm; on 210 timestamps (epoch, leap days,
century boundaries, 9999-12-31, 200 random) upstream `gmtime`, the new OCaml
and Lean agree byte for byte.

### F12. `string_replace`: Lean twin ignored the replacement template (fixed, Lean side)

OCaml's `Str.global_replace` interprets its replacement (`\\` backslash,
`\0` the match, `\1`-`\9` and a trailing `\` raise, other `\c` kept), and
only when a match occurs. The Lean twin inserted the text literally. The
twin now mirrors the probed semantics (`#guard`s). Only `ldconfig`
(`$ORIGIN` substitution) uses it.

### Lean driver (`driver/MainElf.lean`)

- Output is written as raw bytes (one per character), as OCaml's
  `print_string` does; `IO.println` had UTF-8-encoded every byte >= 0x80 in
  names (symbol/section/library/DWARF strings; reached by any UTF-8
  identifier from gcc). A character >= 256 fails loudly (none can occur:
  linksem has no non-ASCII literals).
- Fail-stop: the drivers call LemLib's `lemRequireAbortOnPanic`, which
  refuses to run (exit 2) unless `LEAN_ABORT_ON_PANIC=1`, so a reached
  failure aborts the program as the OCaml exception stops the OCaml one
  (lem-lean replaced its earlier `lemFailStop` runtime switch, 2026-09-30).
- Known limitation: file names that are not valid UTF-8 cannot be opened
  (Lean's file API takes a UTF-8 `String`); loud failure.

### F13. Linker symbol resolution: statics, COMMON and weak symbols (confirmed, fixed)

Found on the archived first iteration by running small C/asm programs
linked by both ld and linksem and comparing their exit statuses (each
program exits with a computed value). `resolve_one_reference_default`
(linkable_list.lem) had two errors:
- the candidate definitions for a reference include every `SymbolDef`,
  LOCAL ones too: `extern int counter;` was bound to ANOTHER file's `static
  int counter` whenever that file came first (`c_static_first`: exit 55
  where ld's program exits 95) -- a silent miscompilation;
- a reference through a symbol the referencing object DEFINES (a weak
  definition, a COMMON symbol) was bound only to that symbol itself, never
  unified with the other objects' definitions: COMMON symbols were not
  merged (two `shared_counter`s: exit 7 vs 9) and a weak definition beat
  the strong one in either link order (exit 1 vs 40).
Fix: only a LOCAL symbol resolves to itself, and a local definition is
never a candidate for another symbol; a global/weak/COMMON symbol an object
defines competes with the other objects' definitions; ties rank strong over
COMMON over weak (the largest COMMON among COMMONs), then the existing
command-line / left-to-right order. Archive members are not searched to
override a weak or COMMON definition (conservative). Remaining difference
from ld: two strong definitions of one name are not an error (the first
wins), and an unchosen COMMON symbol is still allocated (unused space).

### F14. Output symbol table: locals not first, `sh_info = 0` (confirmed, fixed)

The linked executable's `.symtab` interleaved LOCAL and GLOBAL symbols and
its header's `sh_info` was 0 (ELF: all locals first, `sh_info` = index of
the first non-local); `readelf -a` warns on every linked output of the
upstream linker. Fix (elf64_file_of_elf_memory_image.lem): stable
partition, locals first, `sh_info` set.

### F15. amd64 linker: `R_X86_64_(REX_)GOTPCRELX` rejected, `R_X86_64_PC64` unimplemented (confirmed; mirrored)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

`amd64_reloc` (abis/abis.lem) failed with `unrecognised relocation Invalid
X86_64 relocation` on relocation types 41/42 (x86-64 psABI 1.0, 2015),
which modern assemblers emit for every `sym@GOTPCREL(%rip)` load, so most
modern objects with a GOT load could not be linked (the same message is
behind the 11 both-fail files of the memory-image lane, via `main_elf`'s
relocation names); `R_X86_64_PC64` was a `FIXME` failure. Fix: the two
types named (abi_amd64_relocation.lem), added to the GOT-slot set and
computed as `R_X86_64_GOTPCREL` (relaxation is optional in the psABI);
`PC64` = `S + A - P`, 64-bit. Link-corpus case `asm_relocs` (32, 32S, 64,
PC32, PC64, REX_GOTPCRELX): exit status 82 as with ld.

### F16. Static glibc programs cannot be linked (capability gap, not fixed)

`main_link` on a static glibc "hello" (crt1.o crti.o crtbeginT.o h.o
--start-group libgcc.a libgcc_eh.a libc.a --end-group crtend.o crtn.o)
elaborates 2487 input objects (26 s, OCaml) and fails with `matching
definition for GOT entry named _nl_current_LC_TIME_used has no range`: an
SHN_ABS symbol reached through the GOT, which the GOT construction assumes
has a location. Beyond it, relocations static glibc needs are unimplemented
(`R_X86_64_IRELATIVE` for IFUNCs, `R_X86_64_TPOFF32` for TLS). Recorded as
the linker's current limit; the link corpus stays freestanding.

### F17. Host allocation limits reported as `int_of_big_int` / `Bytes.create` (fixed, OCaml)

Found by the fuzz lane: a corrupted `sh_offset` near 2^62 makes
`bytes_of_elf64_file` (reached from `main_elf` through the section-name
lookup) pad the file image up to it, i.e. ask for a ~2^62-byte sequence.
`big_num_make` / `big_num_zero_pad_to_length` then failed in the int
conversion (`Failure "int_of_big_int"`) or in `Bytes.create`. The logical
result cannot be allocated on any host, so this is a resource limit, now
reported as such (`Out_of_memory`) when the length exceeds
`Sys.max_string_length`; the Lean runtime refuses the same allocation
(`INTERNAL PANIC: integer overflow in runtime computation`). The runners
classify both as `bothresource`.

### F18. `Filesystem_wrapper.is_abs_path ""` raises (latent; not changed)

In the port: NOT fixed; the port mirrors upstream (see Status). Any remedy
below is the proposed upstream fix, recorded for the tray.

Found by the twin lane: `is_abs_path` and `to_absolute` index the first
character of the path, so an empty path raises `Invalid_argument "index out
of bounds"`. The Lean twin fails the same way. No caller is known to pass an
empty path (`ldconfig`/`main_load` paths); recorded, not changed.

## Divergences mirrored deliberately (not fixed)

- **N1** `Byte_sequence_wrapper.compare` returns `bs2 - bs1` (by length, then
  first differing byte): the reverse of the obvious order, and of what the
  generic implementation's lexicographic list order would give. It is a
  consistent total order and only fixes the iteration order of sets/maps
  keyed by byte sequences, so the Lean twin reproduces it exactly [AGENT].
- **N2** Records holding a byte sequence are compared (derived `Ord`/`=`)
  on the representation `{bytes; start; len}` in OCaml (polymorphic
  compare), i.e. on the whole underlying buffer, not on the window's
  contents. The Lean twin's `Ord`/`BEq` on `byte_sequence` mirror this.

## Structural changes for the Lean target (behaviour-preserving for OCaml)

- `main_elf.lem`: the top-level effectful driver is split into
  `main_elf_run` (pure: flag, file name, bytes -> `error string`),
  `main_elf_render`, and the unchanged OCaml driver `let {ocaml} _ = ...`.
- `let {ocaml}` definitions of the model are widened to `{ocaml; lean}`
  (the Lean build contains the same code as the OCaml build), except
  `command_line` (reads `argv`; OCaml linker driver only).
- `command_line.lem`: the argument interpretation is split out of
  `command_line ()` as `command_line_of_args` (all targets);
  `command_line ()` is `command_line_of_args (tail argv)`.
- `main_link.lem`: the top-level driver is `let {ocaml} _ = ...` (it calls
  `command_line ()`); `lean/driver/MainLink.lean` mirrors it line for line.
- `declare lean target_rep` lines beside every OCaml rep; the Lean twins of
  the OCaml helpers live in `lean/handwritten/` with the same names.
- `error.lem`: `declare {lean} ascii_rep function (>>=) = error_bind` (Lean
  cannot name a definition `>>=`; lem-lean B1).
- `src/lem.mk`: `lean-extraction` target (same module list and native
  byte-sequence implementation as the OCaml build).

## Differential results (`lean/port`, 2026-09-30)

Pre-merge corpus run on `lean/port` @ 7a65ed0 (code identical to the
records commit that follows), LemLib = lem-lean `66e3cf8`:
`lean/diff_main_elf.sh`, 183 ELF files x 6 flags (`--file-header
--program-headers --section-headers --relocs --dynamic --symbols`), 120 s,
each run memory-capped. 1098 cases: 1092 identical (exit class, stdout, and
stderr), 6 both fail with the same message (`--symbols` on the six ELF32
files: upstream `main_elf` refuses with "Unrecognised flag", the ELF32
branch being commented out; the Lean driver refuses identically), 0
mismatches.

## Differential results on `lean/setup` (historical, 2026-09-28/29)

`lean/diff_main_elf.sh`, corpus of 183 ELF files (x86-64 executables, PIEs,
shared objects, relocatables; i386; big-endian PowerPC64; MIPS64; AArch64;
linksem's own `test/` binaries), flags `--file-header --program-headers
--section-headers --relocs --dynamic --symbols --in-out`: 1281 cases. Lean
runs under `LEAN_ABORT_ON_PANIC=1`.

Branch OCaml (`src/main_elf.opt`) vs Lean (`lean/.lake/build/bin/main_elf`),
stdout byte-for-byte and exit class:
- 1271 identical;
- 6 both fail with the same message (`--symbols` on ELF32 files:
  "Unrecognised flag", the ELF32 branch is commented out in main_elf.lem);
- 4 OCaml timeouts at 300 s where Lean finished (`--in-out` on the four
  largest files); run to completion (733-816 s), all 4 OCaml outputs are
  byte-identical to Lean's.
So: zero behavioural differences.

Upstream OCaml (`master`, worktree) vs branch OCaml, same corpus and flags,
60 s timeout (the largest `--in-out` cases take 12-14 min on OCaml): 1266
identical; 6 both fail identically (as above); 6 both time out (`--in-out`,
not compared); 3 differ, all on `test/mixed-binaries/mips64-test_raw_lui.elf`
(`--section-headers`, `--program-headers`, `--symbols`), where upstream
raises `Failure("int64_of_big_int")` on the `.text` address
0x9000000040000000 (F5) and the branch prints it as readelf does. The
upstream fixes change nothing else on the corpus.

Re-run after lem-lean B13 (`lem_if`) and F9, same corpus, 120 s timeout:
1270 identical; 6 identical both-fail; 5 OCaml timeouts on `--in-out`
(python3.4m, quassel, sbcl.o, libicui18n, libgprofng), each byte-identical
to its complete OCaml output (libgprofng re-run to completion, 203 s; the
other four against the earlier complete runs, the OCaml build having changed
since only by F9, which reading cannot reach). Zero behavioural differences.
DWARF lanes after B13: 48 cases, 0 mismatches.

Re-run on Lean 4.32.2 without lem-lean B9 (toolchain move, lem-lean
`fe0347b`, 2026-09-29), 120 s timeout: 1270 identical; 6 identical
both-fail; 5 OCaml `--in-out` timeouts, all byte-identical to their complete
OCaml outputs. DWARF lanes: 48 cases, 0 mismatches. Zero behavioural
differences.

DWARF lanes (`--debug-dump=info`, `--debug-dump=dies`) on the 24 files with
`.debug_info` (20 corpus files + 4 `-gdwarf-4` builds at -O0/-O2, an object
and a shared library): 48 cases, 38 identical, 10 both fail with the same
message (F7), 0 mismatches (after F8).

Axioms: `#print axioms main_elf_run` gives `[propext, Classical.choice,
Quot.sound]`; no `sorry` in `generated/` or `handwritten/`.

## Performance observations (measured, not changed)

Lean build: closed-term extraction off (lem-lean B9). Wall-clock, this
machine, same inputs, identical output:

| case | OCaml | Lean |
|------|-------|------|
| `--section-headers` python3.4m (4 MB) | 0.78 s | 0.37 s |
| `--symbols` python3.4m | 0.86 s | 1.89 s |
| `--symbols` libicui18n.so (9146 symbols) | 1.95 s | 5.10 s |
| `--in-out` python3.4m | 775 s | 1.38 s |

The `--in-out` gap is super-linear behaviour of the OCaml extraction of the
same Lem code (cause not located). Re-measured 2026-09-30 (other jobs running
concurrently): `--in-out` on the five largest corpus files, OCaml 546-1212
s, Lean 1-2 s, outputs byte-identical. The Lean `--symbols` figure is after
replacing `toList`-based string helpers in `handwritten/Ml_bindings.lean`
(before: 124 s on libicui18n: string tables are sliced once per symbol).

## Bugs in the port itself, caught by the differential

- `Byte_sequence_wrapper.concat` (Lean twin) copied from the accumulator
  instead of each window: every `--section-headers`/`--program-headers`/
  `--symbols`/`--relocs`/`--in-out` run failed or diverged. Now pinned by
  `handwritten/HandwrittenTest.lean` (plant-tested).
- The list-based string helpers above (performance only).
