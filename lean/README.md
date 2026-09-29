# linksem in Lean 4

A Lean 4 version of linksem's ELF/DWARF model, generated from the same Lem
sources as the OCaml build by the Lean backend of the
[lem-lean fork](https://github.com/OathTech/lem-lean) (`lem -lean`), plus
hand-written Lean twins of linksem's OCaml helpers (`handwritten/`, same
module and function names as `src/*.ml`). The OCaml build is the
behavioural reference: `diff_main_elf.sh` compares the two `main_elf`
programs byte for byte.

Status and findings: [`docs/2026-09-28_upstream-findings.md`](docs/2026-09-28_upstream-findings.md)
(upstream linksem bugs found and fixed on both targets, differential results,
performance). Backend bugs found by this port are recorded in lem-lean's
`doc/lean-backend/2026-09-28_linksem-findings.md`.

## Layout

| Path | What |
|------|------|
| `handwritten/` | Lean twins of `src/uint32_wrapper.ml`, `uint64_wrapper.ml`, `byte_sequence_wrapper.ml`, `ml_bindings.ml`, `filesystem_wrapper.ml`; `HandwrittenTest.lean` holds build-time `#guard` checks against the OCaml outputs |
| `generated/` | output of `lem -lean` (not committed; `make -C ../src -f lem.mk lean-extraction`) |
| `driver/MainElf.lean` | the Lean `main_elf`: the I/O around the generated `Main_elf.main_elf_run` |
| `lakefile.lean` | LemLib pinned by commit (bump it together with the `lem` you generate with); the generated-module list is rewritten by `gen-roots.sh` |
| `diff_main_elf.sh` | differential runner (corpus x flags; stdout and exit class) |

## Build

Prerequisites: the lem-lean fork's `lem` at the commit pinned for LemLib in
`lakefile.lean` (build it in its checkout with `make`; the fork's
`doc/lean-backend/README.md` has the quickstart), the OCaml dependencies of
linksem (`opam`: `ocamlfind`, `zarith`, `num`, and lem's OCaml library from
the same checkout), and elan with the toolchain in `lean-toolchain`
(Lean 4.32.2).

    # OCaml reference build (from linksem's src/)
    make -C src LEM=/path/to/lem-lean/lem
    # Lean: generate, then build (whole model, checks, main_elf)
    make -C src -f lem.mk LEM=/path/to/lem-lean/lem lean-extraction
    cd lean && lake build

The generated code must be built against the LemLib of the same lem-lean
commit as the `lem` that generated it. For unpushed lem-lean work, redirect
the URL in `lakefile.lean` to a local checkout, e.g.

    git config --file mygitconfig url./path/to/lem-lean.insteadOf https://github.com/OathTech/lem-lean
    GIT_CONFIG_GLOBAL=$PWD/mygitconfig lake update LemLib

## Differential

    ./diff_main_elf.sh ../src/main_elf.opt .lake/build/bin/main_elf corpus.txt out/ \
        [--file-header --program-headers --section-headers --relocs --dynamic --symbols --in-out]

`corpus.txt` lists ELF files, one path per line. The Lean side runs under
`LEAN_ABORT_ON_PANIC=1`, so a reached model failure stops it as the OCaml
exception does. Cases where both sides fail or both time out are reported as
their own categories; their messages must be reviewed, not assumed equal.
