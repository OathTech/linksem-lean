<!-- Claude: written by Claude for M. Dodds (OathTech); updated 3 October 2026 for reloc-new-ps. -->
# linksem in Lean 4

A Lean 4 version of linksem's ELF/DWARF model, generated from the same Lem
sources as the OCaml build by the Lean backend of the
[lem-lean fork](https://github.com/OathTech/lem-lean) (`lem -lean`), plus
hand-written Lean twins of linksem's OCaml helpers (`handwritten/`, same
module and function names as `src/*.ml`). The OCaml build is the
behavioural reference: `diff_main_elf.sh` compares the two `main_elf`
programs byte for byte.

Plan, choice points and status: `../notes/notes015-2026-10-03-plan-lean-port.md`;
findings and the differential results on this branch:
`../notes/notes016-2026-10-03-lean-port-findings.md`. The first port (on
`master`) and its full findings record are on OathTech/linksem-lean branch
`mdd/linksem-lean-port` (`lean/docs/`).

## Layout

| Path | What |
|------|------|
| `handwritten/` | Lean twins of `src/uint32_wrapper.ml`, `uint64_wrapper.ml`, `byte_sequence_wrapper.ml`, `ml_bindings.ml`, `filesystem_wrapper.ml`, `sym_ocaml.ml`; `HandwrittenTest.lean` holds build-time `#guard` checks against the OCaml outputs |
| `generated/` | output of `lem -lean` (not committed; `make -C ../src -f lem.mk lean-extraction`) |
| `driver/MainElf.lean` | the Lean `main_elf`: the I/O around the generated `Main_elf.main_elf_run` |
| `driver/MainLink.lean` | the Lean `main_link` (the linker test driver): mirrors the OCaml-only driver of `src/main_link.lem` |
| `lakefile.lean` | LemLib pinned by commit (bump it together with the `lem` you generate with); the generated-module list is rewritten by `gen-roots.sh` |
| `diff_main_elf.sh` | differential runner: OCaml vs Lean `main_elf`, corpus x flags; stdout, stderr, exit class |

## Build

Prerequisites: an OCaml toolchain with `ocamlfind`, `zarith` and `num`
(opam), elan with the toolchain in `lean-toolchain` (Lean 4.32.2), and the
lem-lean fork checked out at the commit pinned for LemLib in `lakefile.lean`.
Build `lem` and make its OCaml library visible to findlib (linksem's
`src/lem.mk` checks for it, also for the Lean extraction):

    cd /path/to/lem-lean && git checkout <commit pinned in lean/lakefile.lean> && make
    make -C ocaml-lib INSTALLDIR=/path/to/findlib-dir install
    export OCAMLPATH=/path/to/findlib-dir     # or: opam pin the fork's lem

Then, from the root of this repository:

    # OCaml reference build
    make -C src LEM=/path/to/lem-lean/lem
    # Lean: generate, then build (whole model, checks, main_elf)
    make -C src -f lem.mk LEM=/path/to/lem-lean/lem lean-extraction
    cd lean && lake build

Generation rewrites the module list in `lakefile.lean` (byte order, so it is
the same for everyone); a clean checkout stays clean unless the Lem module
set changed.

The generated code must be built against the LemLib of the same lem-lean
commit as the `lem` that generated it. For unpushed lem-lean work, redirect
the URL in `lakefile.lean` to a local checkout, e.g.

    git config --file mygitconfig url./path/to/lem-lean.insteadOf https://github.com/OathTech/lem-lean
    GIT_CONFIG_GLOBAL=$PWD/mygitconfig lake update LemLib

## Differential

    export CAPPED=/path/to/lem-lean/scripts/capped    # per-run memory cap (cgroup)
    ./diff_main_elf.sh ../src/main_elf.opt .lake/build/bin/main_elf corpus.txt out/

`corpus.txt` lists ELF files, one path per line; the default flags are
`--file-header --program-headers --section-headers --relocs --dynamic
--symbols`; further flags (e.g. `--in-out '--debug-dump=info<raw>'`) can be
given after the output directory. A case is identical when the exit class and stdout match (and
stderr, when both succeed); cases where both sides fail or both time out
are listed separately and their messages must be reviewed. The Lean
drivers refuse to run unless `LEAN_ABORT_ON_PANIC=1` (LemLib's
`lemRequireAbortOnPanic`), so the first reached model failure aborts the
program, as the OCaml exception stops the OCaml one; the runner sets it.

Upstream bugs found by the port: `../notes/notes016-2026-10-03-lean-port-findings.md`. The port mirrors upstream except where upstream
wrongly models the ELF artifact in a way our use case exercises
(including malformed/hostile input); those fixes are listed there.
