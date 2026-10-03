<!-- Claude: written by Claude, 3 October 2026, for M. Dodds (OathTech). -->
# notes016: the Lean port on `reloc-new-ps`, findings and status

Claude: the state of the Lean port planned in `notes015`, as built on this
branch (`25d620b` plus the port's commits), and what the differential
against the OCaml build found.  Decisions are tagged [MDD] (M. Dodds) or
[AGENT]; "confirmed" means reproduced by a run, not inferred from reading.

## Commits

| Commit    | What                                                                                                   |
|-----------|--------------------------------------------------------------------------------------------------------|
| `2e50c58` | `notes015`, the plan                                                                                   |
| `b783f20` | port infrastructure in the Lem sources (Lean target reps, `{ocaml; lean}`, driver splits); OCaml unchanged |
| `abd06f1` | `lean/`: Lake project, hand-written twins (`Sym_ocaml.lean` new), drivers, differential runner          |
| `b20c8fe` | F10: `big_num_dropbytes`/`takebytes` compare lengths as big numbers                                    |
| `9619733` | F11: `string_of_unix_time` by exact big-number calendar arithmetic                                     |
| `9929a3f` | F13: linker never binds a reference to another file's static; COMMON and weak unified                  |
| `a4ac199` | F14: linked `.symtab` lists locals first and sets `sh_info`                                            |
| `45556aa` | F17: lengths beyond the host limit reported as `Out_of_memory`                                         |

"OCaml unchanged" for `b783f20` was checked by generating the OCaml from it
and from `25d620b` with the same Lem: they differ only by the driver splits,
comments, and one source line number inside a generated test message.

## The first port's findings, rechecked here

| Finding                                                          | On `25d620b`              | In the port                                  |
|------------------------------------------------------------------|---------------------------|----------------------------------------------|
| F1 uint32/uint64 wrappers reduce modulo 2^N - 1                  | fixed here (`modulus_`)   | twins follow (modulo 2^N)                    |
| F2 `bytes_of_int32`/`bytes_of_int64` are `assert false`          | present                   | mirrored                                     |
| F3 `Uint64_wrapper.logxor` named by a rep but not defined        | present                   | mirrored (the Lean twin defines it to compile) |
| F5 hex printing raises on values >= 2^63                         | fixed here                | twins follow                                 |
| F6 `zero_pad_to_length` pads the wrong way                       | present                   | mirrored (no caller)                         |
| F9 `unsigned_char_plus` does not wrap at 256                     | present                   | mirrored                                     |
| F10 lengths >= 2^62 raise `int_of_big_int`                       | present                   | fixed, `b20c8fe`                             |
| F11 `string_of_unix_time` via float `gmtime`                     | present                   | fixed, `9619733`                             |
| F13 linker binds a reference to another file's static            | present                   | fixed, `9929a3f`                             |
| F14 linked `.symtab`: locals not first, `sh_info = 0`            | present                   | fixed, `a4ac199`                             |
| F15 GOTPCRELX rejected                                           | present                   | mirrored (a refusal) [MDD 2026-09-30]        |
| F17 allocation-size crash reported as `int_of_big_int`           | present                   | fixed, `45556aa`                             |
| F18 `is_abs_path ""` raises                                      | present                   | mirrored (no caller)                         |

F11 was checked against the `gmtime` version on 200,000 random timestamps
below 10^12 and the edge cases (identical).  F13 and F14 were checked with
the first port's linker cases (26 small C/assembly programs linked by `ld`
and by `main_link`, each exiting with a computed status): on `25d620b`
every linked output draws a readelf warning (F14); with the fixes 24 of 26
exit as `ld`'s program does, the other two being `asm_relocs` (GOTPCRELX,
F15) and `c_tls` (whose `ld` reference itself crashes: a test defect).  The
Lean `main_link` writes byte-identical files to the OCaml one for all 24.

## Differential: OCaml `main_elf` vs Lean `main_elf`

Corpus: the first port's 183 files (system binaries, linksem's `test/`)
and all ELF files of the `validation/dwarf` corpora as built here
(binutils 479, LLVM 1242, elfutils 301): 2205 files.  Flags:
`--file-header --program-headers --section-headers --relocs --symbols
--dynamic --in-out` and `--debug-dump=info<raw|resolved|objdump|analysis>`.
Per run memory cap 4G, timeout 300 s, Lean with `LEAN_ABORT_ON_PANIC=1`.

| Verdict                                     | Cases  |
|---------------------------------------------|--------|
| identical (exit class, stdout, stderr)      | 21,987 |
| both failed, same message                   |  2,189 |
| both failed, different failure point        |     44 |
| both over the 4G cap                        |     22 |
| mismatch                                    |     13 |
| total                                       | 24,255 |

**The 13 mismatches** are one cause, all `--debug-dump=info<analysis>`
(two binutils `dw2-*` objects, eleven LLVM `llvm-dwarfdump` test objects):
OCaml fails with "compilation unit did not have a DW_AT_stmt_list
attribute", Lean prints the dump.  `decl_of_die` and `call_site_of_die`
(`dwarf.lem`) bind `lnp = line_number_program_of_compilation_unit d cu`
before matching on the DIE's `DW_AT_decl_file`/`DW_AT_call_file`; OCaml
evaluates the binding and fails for every DIE of a CU without a line
table, while Lean's compiler moves the binding into the branch that uses
it.  This is the Lean backend's open finding A5 (a `let` floated into an
untaken branch), reported to the lem-lean maintainers; the port does not
work around it in the Lem sources [AGENT].

**The 44 different failure points** are the same family: both sides fail,
with the model's own messages, but at different places: OCaml at the
`DW_AT_stmt_list` binding where Lean goes on to a later check (A5), or a
different DIE first in `analyse_type_info_top` (OCaml evaluates
constructor and tuple arguments right to left, Lean left to right: the
backend's A3 family).

**The 22 cases over the cap** are elfutils'
`testfile-dwp-{4,5}-cu-index-overflow.dwp`, 4 GiB files, on every flag.
Rerun with larger caps: `--file-header` is identical (both 4.2 GB peak);
`--section-headers` is identical too, but Lean's peak is 46 GB against
OCaml's 12.6 GB.  Open: a memory overhead in the Lean port on very large
inputs; the byte-sequence twin's construction of large sequences through a
boxed `Array` is the first suspect (not yet confirmed).

## Open

- The Lean memory overhead above.
- `lean/generated/` (the Lem output, not committed) sits beside the sources;
  `notes013` asks for generated files under an `output/` or `build/`
  directory.
