# Upstream report drafts — index

> linksem developers: start with [README.md](README.md), the reader's guide to this directory.

Prepared reports for linksem (and one for Lem), from the Lean port of
linksem (branch `lean/port`). Code references are to linksem `master` @
`4464128` and were checked on 2026-09-29. Filing is the operator's call
[USER 2026-09-29: "F1-F12 - we can adopt the same 'tray' approach that
cerberus-lean is using"]; drafting [AGENT].

## Submission status

**Draft** = prepared, no recorded submission; **Sent** = transmitted without
an issue/PR URL; **Filed** = recorded issue/PR URL; **Closed** = recorded
upstream closure.

Inventory (2026-09-29): 17 report files, **17 Draft, 0 Sent, 0 Filed, 0 Closed**.

| Report | Findings-doc id | State | In the port |
|---|---|---|---|
| [01-linker-binds-reference-to-other-files-static.md](01-linker-binds-reference-to-other-files-static.md) | F13 | Draft | fixed (misbehaviour exercised by our use case) |
| [02-amd64-gotpcrelx-and-pc64-rejected.md](02-amd64-gotpcrelx-and-pc64-rejected.md) | F15 | Draft | mirrored (a refusal) |
| [03-uint-wrappers-reduce-modulo-2n-minus-1.md](03-uint-wrappers-reduce-modulo-2n-minus-1.md) | F1 | Draft | mirrored (not exercised) |
| [04-byte-lengths-at-least-2-62-crash.md](04-byte-lengths-at-least-2-62-crash.md) | F10 | Draft | fixed (crash on crafted input) |
| [05-hex-printing-crashes-at-2-63.md](05-hex-printing-crashes-at-2-63.md) | F5 | Draft | fixed (crash on a real corpus file) |
| [06-linked-symtab-locals-not-first.md](06-linked-symtab-locals-not-first.md) | F14 | Draft | fixed (malformed output) |
| [07-unix-time-rounds-and-crashes.md](07-unix-time-rounds-and-crashes.md) | F11 | Draft | fixed (crash / wrong output on crafted input) |
| [08-byte-sequence-generic-does-not-parse.md](08-byte-sequence-generic-does-not-parse.md) | F4 | Draft | not changed (not on the port's path) |
| [09-dwarf-debug-trace-on-stdout.md](09-dwarf-debug-trace-on-stdout.md) | F8 | Draft | mirrored |
| [10-unsigned-char-does-not-wrap.md](10-unsigned-char-does-not-wrap.md) | F9 | Draft | mirrored (not exercised) |
| [11-signed-serialisers-assert-false.md](11-signed-serialisers-assert-false.md) | F2 | Draft | mirrored (upstream gap) |
| [12-zero-pad-pads-wrong-way.md](12-zero-pad-pads-wrong-way.md) | F6 | Draft | mirrored (no caller) |
| [13-missing-uint64-target-rep-functions.md](13-missing-uint64-target-rep-functions.md) | F3 | Draft | mirrored (latent) |
| [14-dwarf-coverage-gaps.md](14-dwarf-coverage-gaps.md) | F7 | Draft | mirrored (upstream gap) |
| [15-static-glibc-link-gaps.md](15-static-glibc-link-gaps.md) | — (new) | Draft | mirrored (upstream gap) |
| [16-byte-sequence-compare-order-question.md](16-byte-sequence-compare-order-question.md) | N1, N2 | Draft | mirrored (question) |
| [lem/01-assert-extra-fail-applied-prints-invalid-ocaml.md](lem/01-assert-extra-fail-applied-prints-invalid-ocaml.md) | — (new) | Draft | not changed (a Lem OCaml-backend quirk; the port does not hit it) |

Out of scope: F12 (`string_replace`) was a bug in our Lean twin of
`ml_bindings.ml`, not in linksem; F7's DWARF gaps are report 14.

Remedies are proposed in each report's text; no patches are offered. The
port changes upstream only where marked "fixed" (see the findings record's
policy); everywhere else it mirrors upstream.

## Ranking (by upstream value)

Per the cerberus-lean tray convention, every report carries a concrete
remedy (or says why none is proposed) and a classification: TRUE BUG /
INTENDED GAP / UNCLEAR.

1. **01** — TRUE BUG, silent miscompilation. The linker binds `extern int
   counter` to another file's `static int counter` (link-order dependent),
   does not merge COMMON symbols, and lets a weak definition beat a strong
   one. Found by running linked programs against ld's. Remedy in report.
2. **02** — TRUE BUG (+ one-line INTENDED GAP). `R_X86_64_(REX_)GOTPCRELX`,
   standard since 2015 and emitted by gas for every `@GOTPCREL` load, are
   rejected as "Invalid X86_64 relocation"; `R_X86_64_PC64` is a FIXME.
   Blocks linking most modern objects that use the GOT. Remedy in report.
3. **03** — TRUE BUG. 32/64-bit arithmetic modulo 2^N − 1: the all-ones
   value becomes 0, subtraction wraps to 2^N − 2. Affects every value
   constructed (not read) in the linker/serialisers. Remedy in report.
4. **04** — TRUE BUG, crash. ELF64 offsets/sizes ≥ 2^62 raise
   `int_of_big_int` instead of the model's `Fail`. Remedy in report.
5. **05** — TRUE BUG, crash. Hex printing raises on values ≥ 2^63;
   `main_elf` dies on linksem's own MIPS64 test binary. Remedy in report.
6. **06** — TRUE BUG. Linked `.symtab` interleaves locals/globals with
   `sh_info = 0`; readelf warns on every output. Remedy in report.
7. **07** — TRUE BUG, low impact. `string_of_unix_time` rounds above 2^53
   and crashes from ~6.8·10^16 (prelink timestamps). Remedy in report.
8. **08** — TRUE BUG. `byte_sequence_generic.lem` does not parse, so the
   prover extractions cannot be regenerated; its `find_byte` is wrong too.
   Remedy in report.
9. **09** — TRUE BUG. `--debug-dump` output carries a duplicate debug trace
   per compilation unit on stdout. Remedy in report.
10. **10** — TRUE BUG, low impact. `unsigned_char` does not wrap at 256
    (contrary to its own doc and the prover reps). Remedy in report.
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
