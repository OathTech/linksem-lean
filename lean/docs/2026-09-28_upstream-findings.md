# linksem upstream findings (Lean port, 2026-09-28)

Branch `lean/setup`. Findings about linksem itself, surfaced while porting it
to Lean with lem-lean's Lean backend. Findings about the backend are recorded
in lem-lean `doc/lean-backend/2026-09-28_linksem-findings.md`.

Provenance: [AGENT] = decided by the agent doing the port; [USER] = by the
operator. The operator's charter for this work [USER 2026-09-28]: match the
upstream behaviour structurally and behaviourally, identify obviously wrong
upstream behaviours and fix them, and shake out lem-lean bugs.

Each fix below is made on BOTH sides (the OCaml helper in `src/*.ml` and its
Lean twin in `lean/handwritten/`), so the OCaml build stays the Lean build's
differential reference. "Confirmed" means reproduced by an executed probe
against the upstream build (probe text quoted), not inferred from reading.

## F1. `Uint32_wrapper` / `Uint64_wrapper` compute modulo 2^N − 1 (confirmed, fixed)

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

## F2. `bytes_of_int32` / `bytes_of_int64` are `assert false` (latent, fixed)

`src/ml_bindings.ml` implements the serialisers of the signed ELF types
(`elf32_sword`, `elf64_sword`, `elf64_sxword`) as `assert false`. Not reached
by the `main_elf` flags on the corpus (`--in-out` re-serialises section
contents as raw bytes), but any path writing a signed field would crash.
Fix [AGENT]: least-significant byte first, the order `bytes_of_elf32_sword`
and `bytes_of_elf64_sxword` destructure.

## F3. Target reps naming functions that do not exist (latent, fixed)

`elf64_addr_minus`'s OCaml rep is `Uint64_wrapper.sub` and
`elf64_xword_lxor`'s is `Uint64_wrapper.logxor`; neither exists. Both
functions are unused, so OCaml never noticed. Fix [AGENT]: the rep of
`elf64_addr_minus` is `Uint64_wrapper.minus`; `logxor` is added.

## F4. `byte_sequence_generic.lem` does not parse (confirmed, fixed)

Two unterminated `match`es in `find_byte`; `-isa`, `-coq`, `-hol` and `-lean`
all failed on the file ("Syntax error", line 40), so the prover extractions
cannot have been run for some time. Fixed in the first commit on the branch.

## F5. Hex printing raises on values ≥ 2^63 (confirmed, fixed)

The `hex_string_of_big_int_pad*` family formatted through
`Nat_big_num.to_int64`. Probe against the upstream build:

    hex_string_of_big_int_pad16 (2^64 - 2^31)  ->  EXN: Failure("int64_of_big_int")

so `main_elf` cannot print any upper-half address (kernel images, `-1`
sentinels). Fix [AGENT]: format the big number directly; values below 2^63
print exactly as before (negative values keep their 64-bit two's-complement
rendering), so output is unchanged wherever it used to succeed.

## F6. `zero_pad_to_length` pads the wrong way (confirmed, latent, fixed)

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

## F8. Debug trace on stdout in `--debug-dump` (confirmed, fixed)

`dwarf.lem`'s `my_debug4`/`my_debug5` printed to stdout (`my_debug` ..
`my_debug3` are no-ops), and `my_debug4 (pp_compilation_unit_header cuh)`
runs for every compilation unit, so every `--debug-dump=info`/`dies` output
had a duplicate `**Compilation Unit @ offset ...` block interleaved (7 lines
per CU on the probe binary). Found by the differential: Lean erases the
unused pure `let _ = print ...` (the documented backend limitation), OCaml
prints it. Fix [AGENT]: the two debug printers write to stderr
(`Missing_pervasives.errln`); stdout is now identical on both targets.

## F9. `unsigned_char` did not wrap at 256 (fixed; was N3)

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
- `lemFailStop` (lem-lean A2) makes a reached failure stop the program (exit
  1; OCaml exits 2 on the uncaught exception); it used to continue with a
  default value unless `LEAN_ABORT_ON_PANIC=1` was set.
- Known limitation: file names that are not valid UTF-8 cannot be opened
  (Lean's file API takes a UTF-8 `String`); loud failure.

### New lanes (2026-09-29)

[USER 2026-09-29] approved three additions: a Lean `main_link` driver with a
differential lane, a memory-image lane, and zero panics as a hard pass
condition.

- **Linker** (`diff_main_link.sh`, `link-corpus/`): freestanding x86-64
  programs (asm and C at -O0/-O2, several objects in both orders, archives
  with used and unused members, COMMON and weak symbols, function/data
  sections, `.eh_frame`, PIE-style objects, TLS), linked by `ld -static` for
  the reference executable `main_link` reads. Before lem-lean A1 the Lean
  linker produced an image with entry point 0 and no `.text` (auditor
  finding); the lane then found lem-lean B14 (tuple-arity instances: the
  "Got N input items" line) and B15 (dropped `let _ = errln ...`
  diagnostics).
- **Memory image** (`src/dump_image.lem`, `diff_main_elf.sh ... @`): the
  annotated memory image of each file (elements with checksums, `by_range`
  annotations in set order, so every range-tag comparison A1 fixed is
  exercised) and the serialisation round trip of `copy_elf`.
- **Runner verdicts** (both runners): stderr is compared when both sides
  exit 0; a Lean panic is a hard failure unless it is the rendering of a
  failure OCaml also raises (`panic`); both-fail cases compare the failure
  messages (`bothfail` / `bothfail-msg`); a stderr that differs only in line
  order is its own reviewed category (`stderrorder`, lem-lean A4).

### Results (2026-09-29, lem-lean `18f6ef7`)

- `main_elf`, 183 files x 7 flags (1281 cases), 120 s, stdout AND stderr:
  1270 identical, 6 both fail with the same message, 5 OCaml `--in-out`
  timeouts where Lean finished, 0 panics. The 5 OCaml runs, completed
  without a timeout, are byte-identical to Lean's (stdout and stderr): zero
  behavioural differences.
- DWARF lanes, 24 files x 2 flags (48 cases): 38 identical, 10 both fail
  with the same message (F7; four are multi-line messages), 0 mismatches.
- Memory image, the 183 corpus files + the linker corpus's 36 objects and
  executables (219): 208 identical dumps (202 with an identical serialisation
  round trip; 6 ELF32 files are rejected identically by the ELF64 reader),
  11 both fail with the same message (unrecognised relocation), 0
  mismatches.
- Linker, 13 cases: 12 linked outputs byte-identical (with identical stdout;
  9 of them with stderr differing only in the order of the model's
  "Considering relocatable file" lines, lem-lean A4: OCaml's `count_map`
  applies f from the last element), 1 both fail with the same message
  (`R_X86_64_TPOFF32` unimplemented, upstream). 0 mismatches, 0 panics.
- Targeted: F10 (`e_shoff = 2^62`: upstream raises `int_of_big_int`, branch
  and Lean print the model's error identically); non-ASCII names (a UTF-8
  and a raw 0xEF byte) byte-identical to OCaml; fail-stop without
  `LEAN_ABORT_ON_PANIC` (exit 1, message on stderr, no partial stdout).

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
- `dump_image.lem` (new, a test driver only): the memory-image view of an
  ELF64 file (elements, `by_range` annotations in set order, serialisation
  round trip), for the memory-image lane; `src/dump_image.opt` and the Lean
  `dump_image`.
- `declare lean target_rep` lines beside every OCaml rep; the Lean twins of
  the OCaml helpers live in `lean/handwritten/` with the same names.
- `error.lem`: `declare {lean} ascii_rep function (>>=) = error_bind` (Lean
  cannot name a definition `>>=`; lem-lean B1).
- `src/lem.mk`: `lean-extraction` target (same module list and native
  byte-sequence implementation as the OCaml build).

## Differential results (2026-09-28)

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
same Lem code (cause not located). The Lean `--symbols` figure is after
replacing `toList`-based string helpers in `handwritten/Ml_bindings.lean`
(before: 124 s on libicui18n: string tables are sliced once per symbol).

## Bugs in the port itself, caught by the differential

- `Byte_sequence_wrapper.concat` (Lean twin) copied from the accumulator
  instead of each window: every `--section-headers`/`--program-headers`/
  `--symbols`/`--relocs`/`--in-out` run failed or diverged. Now pinned by
  `handwritten/HandwrittenTest.lean` (plant-tested).
- The list-based string helpers above (performance only).
