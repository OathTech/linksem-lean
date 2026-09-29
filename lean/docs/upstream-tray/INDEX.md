# Upstream report drafts — index

> linksem developers: start with [README.md](README.md), the reader's guide to this directory.

Prepared reports for linksem (and one for Lem), from the Lean port of
linksem (branch `lean/setup`). Code references are to linksem `master` @
`4464128` and were checked on 2026-09-29. Filing is the operator's call
[USER 2026-09-29: "F1-F12 - we can adopt the same 'tray' approach that
cerberus-lean is using"]; drafting [AGENT].

## Submission status

**Draft** = prepared, no recorded submission; **Sent** = transmitted without
an issue/PR URL; **Filed** = recorded issue/PR URL; **Closed** = recorded
upstream closure. A pushed patch branch does not mean Filed.

Inventory (2026-09-29): 17 report files, **17 Draft, 0 Sent, 0 Filed, 0 Closed**.

| Report | Findings-doc id | State | Patch branch (local, based on `master` @ `4464128`) |
|---|---|---|---|
| [01-linker-binds-reference-to-other-files-static.md](01-linker-binds-reference-to-other-files-static.md) | F13 | Draft | `upstream-pr/link-symbol-resolution` |
| [02-amd64-gotpcrelx-and-pc64-rejected.md](02-amd64-gotpcrelx-and-pc64-rejected.md) | F15 | Draft | `upstream-pr/gotpcrelx-pc64` |
| [03-uint-wrappers-reduce-modulo-2n-minus-1.md](03-uint-wrappers-reduce-modulo-2n-minus-1.md) | F1 | Draft | `upstream-pr/uint-modulus` |
| [04-byte-lengths-at-least-2-62-crash.md](04-byte-lengths-at-least-2-62-crash.md) | F10 | Draft | `upstream-pr/bignum-drop-take` |
| [05-hex-printing-crashes-at-2-63.md](05-hex-printing-crashes-at-2-63.md) | F5 | Draft | `upstream-pr/hex-big-values` |
| [06-linked-symtab-locals-not-first.md](06-linked-symtab-locals-not-first.md) | F14 | Draft | `upstream-pr/symtab-locals-first` |
| [07-unix-time-rounds-and-crashes.md](07-unix-time-rounds-and-crashes.md) | F11 | Draft | `upstream-pr/unix-time-exact` |
| [08-byte-sequence-generic-does-not-parse.md](08-byte-sequence-generic-does-not-parse.md) | F4 | Draft | `upstream-pr/generic-find-byte` |
| [09-dwarf-debug-trace-on-stdout.md](09-dwarf-debug-trace-on-stdout.md) | F8 | Draft | `upstream-pr/dwarf-debug-stderr` |
| [10-unsigned-char-does-not-wrap.md](10-unsigned-char-does-not-wrap.md) | F9 | Draft | `upstream-pr/uchar-wrap` |
| [11-signed-serialisers-assert-false.md](11-signed-serialisers-assert-false.md) | F2 | Draft | `upstream-pr/signed-serialisers` |
| [12-zero-pad-pads-wrong-way.md](12-zero-pad-pads-wrong-way.md) | F6 | Draft | `upstream-pr/zero-pad` |
| [13-missing-uint64-target-rep-functions.md](13-missing-uint64-target-rep-functions.md) | F3 | Draft | `upstream-pr/missing-uint64-reps` |
| [14-dwarf-coverage-gaps.md](14-dwarf-coverage-gaps.md) | F7 | Draft | none (features) |
| [15-static-glibc-link-gaps.md](15-static-glibc-link-gaps.md) | — (new) | Draft | none (features) |
| [16-byte-sequence-compare-order-question.md](16-byte-sequence-compare-order-question.md) | N1, N2 | Draft | none (question) |
| [lem/01-assert-extra-fail-applied-prints-invalid-ocaml.md](lem/01-assert-extra-fail-applied-prints-invalid-ocaml.md) | — (new) | Draft | none (remedy in report) |

Out of scope: F12 (`string_replace`) was a bug in our Lean twin of
`ml_bindings.ml`, not in linksem; F7's DWARF gaps are report 14.

Each patch branch holds that fix only (the generic-find-byte branch: two
commits); each was built with `make` in `src/` (the upstream OCaml build)
and its report's reproducer re-run on it (outputs quoted in the reports).
The branches are independent: all 78 pairs merge without textual conflict
(`git merge-tree`, 2026-09-29). One semantic interaction: branch 13 adds
`Uint64_wrapper.logxor` reducing with `max_int`, like every operation on
`master`; if branch 03 is also taken, that one line should use its new
`modulus` too.

## Ranking (by upstream value)

Per the cerberus-lean tray convention, every report carries a concrete
remedy (or says why none is proposed) and a classification: TRUE BUG /
INTENDED GAP / UNCLEAR.

1. **01** — TRUE BUG, silent miscompilation. The linker binds `extern int
   counter` to another file's `static int counter` (link-order dependent),
   does not merge COMMON symbols, and lets a weak definition beat a strong
   one. Found by running linked programs against ld's. Fix on branch.
2. **02** — TRUE BUG (+ one-line INTENDED GAP). `R_X86_64_(REX_)GOTPCRELX`,
   standard since 2015 and emitted by gas for every `@GOTPCREL` load, are
   rejected as "Invalid X86_64 relocation"; `R_X86_64_PC64` is a FIXME.
   Blocks linking most modern objects that use the GOT. Fix on branch.
3. **03** — TRUE BUG. 32/64-bit arithmetic modulo 2^N − 1: the all-ones
   value becomes 0, subtraction wraps to 2^N − 2. Affects every value
   constructed (not read) in the linker/serialisers. Fix on branch.
4. **04** — TRUE BUG, crash. ELF64 offsets/sizes ≥ 2^62 raise
   `int_of_big_int` instead of the model's `Fail`. Fix on branch.
5. **05** — TRUE BUG, crash. Hex printing raises on values ≥ 2^63;
   `main_elf` dies on linksem's own MIPS64 test binary. Fix on branch.
6. **06** — TRUE BUG. Linked `.symtab` interleaves locals/globals with
   `sh_info = 0`; readelf warns on every output. Fix on branch.
7. **07** — TRUE BUG, low impact. `string_of_unix_time` rounds above 2^53
   and crashes from ~6.8·10^16 (prelink timestamps). Fix on branch.
8. **08** — TRUE BUG. `byte_sequence_generic.lem` does not parse, so the
   prover extractions cannot be regenerated; its `find_byte` is wrong too.
   Fix on branch.
9. **09** — TRUE BUG. `--debug-dump` output carries a duplicate debug trace
   per compilation unit on stdout. Fix on branch.
10. **10** — TRUE BUG, low impact. `unsigned_char` does not wrap at 256
    (contrary to its own doc and the prover reps). Fix on branch.
11. **12** — TRUE BUG, latent. `zero_pad_to_length` pads the wrong way.
12. **13** — TRUE BUG, latent. Two OCaml target reps name nonexistent
    functions.
13. **11** — INTENDED GAP, latent. Signed serialisers are `assert false`.
14. **14** — INTENDED GAP. DWARF 5, `DW_TAG_unspecified_type`, location
    views: `--debug-dump` fails on default `gcc -g` / `-g -O2` output.
15. **15** — INTENDED GAP. Static linking against glibc fails (GOT slot for
    an absolute symbol; IFUNC/IRELATIVE; TPOFF32).
16. **16** — UNCLEAR, question. Byte-sequence ordering (descending) and
    representation-based comparison of windows: intended?
17. **lem/01** — TRUE BUG in Lem. `Assert_extra.fail` applied to an
    argument prints `(assert false "msg")`, invalid OCaml.

## Duplicate searches

**Not performed** (2026-09-29): the drafting environment has no network
access (HTTPS through its proxy refused; `gh` unavailable). Before filing,
search rems-project/linksem issues and PRs for, at least: `GOTPCRELX`,
`PC64`, `static` + `symbol resolution`/`COMMON`/`weak`, `sh_info`,
`max_int`/`modulus`, `int64_of_big_int`, `int_of_big_int`, `gmtime`,
`byte_sequence_generic`, `my_debug4`, `unsigned_char`, `zero_pad`,
`DWARF 5`/`DW_TAG_unspecified_type`/`location view`, `glibc`; and
rems-project/lem for `assert false` / `Assert_extra.fail`. Also check
whether upstream Lem `master` has changed `library/assert_extra.lem` since
`f5529b2`.
