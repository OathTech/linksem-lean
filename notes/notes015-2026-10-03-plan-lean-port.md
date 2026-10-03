<!-- Claude: written by Claude, 3 October 2026, for M. Dodds (OathTech). -->
# notes015: plan, a Lean port of linksem on `reloc-new-ps`

Claude: this plan moves the Lean port of linksem (first built on `master`,
[github.com/OathTech/linksem-lean](https://github.com/OathTech/linksem-lean)
branch `mdd/linksem-lean-port`) onto this branch, at the owner's suggestion.
It follows `notes013` where it can.  One difference in how it is run: the
choice points below are not left open for `PS:` answers; each is decided
by M. Dodds ([MDD]) or by the agent ([AGENT]) so that work can proceed, and
each is open to the owner's review after the fact (a disagreement becomes a
change like any other).

## What the port is

The Lean code is generated from these Lem sources by the Lean backend of
the lem-lean fork of Lem (`lem -lean`, branch `mdd/lean-backend`); the parts
linksem implements directly in OCaml (`src/*_wrapper.ml`, `src/ml_bindings.ml`,
`src/sym_ocaml.ml`, `src/filesystem_wrapper.ml`) get hand-written Lean twins
with the same names.  The OCaml build of the same sources, with the same
Lem, is the reference: a Lean driver mirrors `main_elf` and the two
programs are compared byte for byte (stdout, stderr, exit status) over a
corpus of ELF files.  Nothing in the port changes what the OCaml build
does, except the fixes listed below.

## Choice points (decided; open to review)

| #  | Question                     | Decision                                                                                                                                                                                                                                | By      |
|----|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| 1  | Base                         | This branch at `25d620b`, pinned; moving to a later commit is a deliberate step (re-port, re-check)                                                                                                                                       | [MDD]   |
| 2  | Scope                        | All of `src/` as the OCaml build has it, including the pKVM, symbolic-resolution and DWARF 5 modules                                                                                                                                      | [AGENT] |
| 3  | Lean front end               | Mirror `main_elf` (a Lem driver, still the dumps' entry point) and `main_link`; not the `src_ocaml/` cmdliner tool, which is a thin OCaml front end over the same Lem functions                                                            | [AGENT] |
| 4  | Validation                   | OCaml vs Lean `main_elf` over the previous 183-file corpus plus the ELF files of `validation/dwarf`'s corpora (elfutils as fetched; binutils/LLVM objects as far as this host's tools build them); not the readelf/objdump harness itself | [AGENT] |
| 5  | Upstream changes             | Only where this branch wrongly models the ELF artifact in a way the port's use exercises, malformed or hostile input included; refusals are mirrored; each fix one commit, `Claude:`-marked, with a report                               | [MDD]   |
| 6  | Records                      | Prompts that lead to changes appended verbatim to `notes012` under their own heading; a paragraph per strand appended to `notes014`; `notes013` left as the owner's; the port's own rules and findings in new notes                       | [MDD]   |
| 7  | Where it lives               | OathTech's fork, a branch based on this one; nothing is pushed to rems-project; fixes reach the owner as reports                                                                                                                          | [MDD]   |

## Fixes from the first port, against this branch

Rechecked on `25d620b` with its own OCaml build:

| Finding                                                   | On this branch                                    | In the port                       |
|-----------------------------------------------------------|---------------------------------------------------|-----------------------------------|
| F1 uint32/uint64 wrappers reduce modulo 2^N - 1           | fixed here already (`modulus_`)                   | twins follow this branch          |
| F5 hex printing raises on values >= 2^63                  | fixed here already (MIPS64 test file dumps)       | twins follow this branch          |
| F10 lengths >= 2^62 raise `int_of_big_int`                | present (crafted `e_shoff = 2^62`)                | fix (crash on hostile input)      |
| F11 `string_of_unix_time` via float `gmtime`              | present (code unchanged)                          | fix (crash / wrong output)        |
| F13 linker binds a reference to another file's static     | present (`linkable_list.lem` unchanged)           | fix (silent miscompilation)       |
| F14 linked `.symtab`: locals not first, `sh_info = 0`     | present (unchanged)                               | fix (malformed output)            |
| F17 allocation-size crash reported as `int_of_big_int`    | present (unchanged)                               | fix (explicit `Out_of_memory`)    |
| everything else in the first port's tray                  | to recheck                                        | mirrored unless case 5 applies    |

## Steps

1. Port infrastructure in the Lem sources, OCaml behaviour unchanged: `declare
   lean target_rep` beside the OCaml ones, `{ocaml}` definitions widened to
   `{ocaml; lean}`, `main_elf`'s driver split into a pure part and an
   OCaml-only top level, the `lean-extraction` target in `lem.mk`.
2. The `lean/` directory (README, Lake project, twins, drivers, the
   differential runner), carried over from the first port and extended for
   this branch's helpers (`sym_ocaml.ml`, the changed `ml_bindings.ml` and
   wrappers).
3. Build; fix lem-lean issues met on the way as notes for the lem-lean team
   (not here).
4. The fixes above, one commit each.
5. The corpus differential; then the records (notes012, notes014, a findings
   note).
