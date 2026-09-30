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
| `driver/MainLink.lean` | the Lean `main_link` (the linker test driver): mirrors the OCaml-only driver of `src/main_link.lem` |
| `driver/DumpImage.lean` | the Lean `dump_image`: the I/O around `Dump_image.dump_image` (`src/dump_image.lem`, a test driver) |
| `lakefile.lean` | LemLib pinned by commit (bump it together with the `lem` you generate with); the generated-module list is rewritten by `gen-roots.sh` |
| `diff_main_elf.sh`, `diff_sharded.sh` | differential runner (and its 8-way parallel wrapper) (corpus x flags; stdout, stderr, exit class); flag `@` for tools taking the file only (`dump_image`) |
| `fuzz/`, `twins/` | fuzz lane (mutated ELF files) and twin lane (Lean twins vs OCaml helpers) |
| `docs/upstream-tray/` | upstream report drafts (README, INDEX, one report per finding) |
| `diff_main_link.sh`, `link-corpus/` | linker differential: `link-corpus/build_cases.sh` compiles freestanding x86-64 programs (`cases.txt`) and links them with `ld` as the reference `out`; the runner compares both `main_link` builds' `out.test-out`, stdout, stderr, exit class |

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

    ./diff_main_elf.sh ../src/main_elf.opt .lake/build/bin/main_elf corpus.txt out/ \
        [--file-header --program-headers --section-headers --relocs --dynamic --symbols --in-out]

`corpus.txt` lists ELF files, one path per line. The Lean drivers switch
on LemLib's fail-stop (`lemFailStop`), so a reached model failure stops them
as the OCaml exception does (the runners also set `LEAN_ABORT_ON_PANIC=1`).

Every runner caps each tool run in its own cgroup through lem-lean's
`scripts/capped` (a runaway input must not take the machine down) and
refuses to start without it:

    export CAPPED=/path/to/lem-lean/scripts/capped    # DIFF_MEM=4G per run by default

The full-corpus run is sharded (`diff_sharded.sh`, 8 parallel shards,
~3 min without `--in-out`) and runs once, just before a merge; day to day,
run the lane for what changed (linker, twins, DWARF, memory image):

    ./diff_sharded.sh ../src/main_elf.opt .lake/build/bin/main_elf corpus.txt out/ \
        --file-header --program-headers --section-headers --relocs --dynamic --symbols

Memory-image lane (the same runner, tools taking the file only):

    ./diff_main_elf.sh ../src/dump_image.opt .lake/build/bin/dump_image corpus.txt out/ @

Linker lane (needs gcc, as, ld, ar for x86-64):

    link-corpus/build_cases.sh /tmp/link-cases
    ./diff_main_link.sh ../src/main_link.opt .lake/build/bin/main_link /tmp/link-cases out/

Linker execution oracle (linksem's own correctness, independent of the
port): link every case, run ld's executable and linksem's, compare their
exit statuses; a readelf warning on linksem's output is also a finding:

    link-corpus/exec_check.sh ../src/main_link.opt /tmp/link-cases exec-out/

Fuzz lane (deterministic mutants of the corpus files up to 200 KB; seed,
mutants per file):

    fuzz/run_fuzz.sh corpus.txt fuzz-out/ 1 20

Twin lane (the hand-written Lean twins against the OCaml helpers; seed,
rounds; `OCAML_SRC=...` compares against another checkout's helpers):

    lake build twin_probe && twins/run.sh twins-out/ 1 500

Verdicts: `yes`; `no` (mismatch); `panic` (hard condition: a Lean panic
that is not the rendering of a failure OCaml also raises); `bothfail` (both
fail with the same message); `bothfail-msg` (both fail, different messages:
review); `stderrorder` (identical except the order of stderr lines: OCaml
evaluates constructor arguments right to left, lem-lean audit A4; review);
`bothtimeout`; `bothresource` (both exhausted the memory cap, the stack,
the host's allocation limit or the time limit). A runner exits 1 on any
`no` or `panic`.

Upstream reports: [`docs/upstream-tray/INDEX.md`](docs/upstream-tray/INDEX.md)
(drafts; each fix also on a branch `upstream-pr/<name>` based on upstream
`master`).
