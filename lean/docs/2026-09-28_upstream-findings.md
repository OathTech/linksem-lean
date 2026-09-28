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
