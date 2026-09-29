#!/usr/bin/env bash
# Differential runner for main_elf: runs two main_elf builds (A, B) over a
# corpus of ELF files x flags and compares, per (file, flag):
#   - the exit class (ok | fail:<status> | timeout),
#   - stdout, byte for byte, and
#   - stderr, byte for byte, when both exit 0 (the model's `[!]:` errors and
#     its `errln` diagnostics, which the Lean side keeps since lem-lean B15).
# Verdicts as in diff_main_link.sh: yes, no, panic (zero-panics hard
# condition), bothfail / bothfail-msg (same / different failure message),
# stderrorder (lem-lean A4), bothtimeout.
# Usage: diff_main_elf.sh A_BIN B_BIN CORPUS_LIST OUTDIR [FLAGS...]
# The flag `@` runs the tools with the file only: the memory-image lane is
#   diff_main_elf.sh ../src/dump_image.opt .lake/build/bin/dump_image LIST OUT @
# CORPUS_LIST is a file of paths, one per line. OUTDIR receives per-case
# outputs of mismatching cases and summary.tsv. Exit 1 if any case differs.
# B (the Lean build) runs with LEAN_ABORT_ON_PANIC=1 so a reached failure
# stops the process as an OCaml exception does; A is run with the same env
# (it has no effect on OCaml).
set -uo pipefail
A="$1"; B="$2"; LIST="$3"; OUT="$4"; shift 4
FLAGS=("$@")
[ ${#FLAGS[@]} -gt 0 ] || FLAGS=(--file-header --program-headers --section-headers --relocs --dynamic --symbols --in-out)
TIMEOUT="${DIFF_TIMEOUT:-120}"
[ -x "$A" ] && [ -x "$B" ] || { echo "diff_main_elf: A or B not executable" >&2; exit 2; }
[ -s "$LIST" ] || { echo "diff_main_elf: empty corpus list $LIST" >&2; exit 2; }
mkdir -p "$OUT"
: > "$OUT/summary.tsv"
n=0; bad=0
# The failure message of a failed run: OCaml's uncaught `Failure("msg")`,
# Lean's `PANIC at <decl> <mod>:<line>:<col>: msg` (fail-stop / abort).
# OCaml prints the message escaped (a newline as \n); Lean prints it raw,
# up to its `backtrace:` line. Both are compared as raw text.
fail_msg() {
  local m
  m=$(grep -a -o 'Fatal error: exception Failure(".*")$' "$1" | tail -1 | sed 's/^Fatal error: exception Failure("//; s/")$//')
  if [ -n "$m" ]; then printf '%b' "$m"; return; fi
  awk '/^PANIC at /{sub(/^PANIC at [^ ]+ [^ ]+:[0-9]+:[0-9]+: /, ""); on=1}
       /^backtrace:/{on=0} on{print}' "$1"
}
# A panic that is not the Lean rendering of a failure OCaml also raises: a
# backend-internal message, or any panic where the OCaml run did not fail.
bad_panic() { # lean_stderr ocaml_exit_kind
  grep -a -q 'PANIC' "$1" || return 1
  [ "$2" != fail ] && return 0
  grep -a -q 'PANIC.*\(Lean backend\|comparison residual\)' "$1"
}
run() { # bin file flag outfile -> prints exit class
  local st
  if [ "$3" = @ ]; then  # a tool taking the file only (dump_image)
    LEAN_ABORT_ON_PANIC=1 timeout "$TIMEOUT" "$1" "$2" > "$4" 2> "$4.err"; st=$?
  else
    LEAN_ABORT_ON_PANIC=1 timeout "$TIMEOUT" "$1" "$3" "$2" > "$4" 2> "$4.err"; st=$?
  fi
  if [ $st -eq 126 ] || [ $st -eq 127 ]; then
    echo "diff_main_elf: could not execute $1 (exit $st)" >&2; exit 2; fi
  if [ $st -eq 0 ]; then echo ok; elif [ $st -eq 124 ]; then echo timeout; else echo "fail:$st"; fi
}
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || { echo "diff_main_elf: corpus file missing: $f" >&2; exit 2; }
  for fl in "${FLAGS[@]}"; do
    n=$((n+1))
    ca=$(run "$A" "$f" "$fl" "$OUT/a.out") || exit 2
    cb=$(run "$B" "$f" "$fl" "$OUT/b.out") || exit 2
    # Both failed: agreement on the OUTCOME only (OCaml exits 2 on an
    # uncaught exception, Lean aborts with 134); reported as its own
    # category `bothfail` with each side's first stderr line, for review.
    ka=${ca%%:*}; kb=${cb%%:*}
    # Both timed out: nothing comparable (partial outputs); own category.
    if bad_panic "$OUT/b.out.err" "$ka"; then same=panic
    elif [ "$ca" = timeout ] && [ "$cb" = timeout ]; then same=bothtimeout
    elif [ "$ka" = fail ] && [ "$kb" = fail ]; then
      ma=$(fail_msg "$OUT/a.out.err"); mb=$(fail_msg "$OUT/b.out.err")
      if [ -n "$ma" ] && [ "$ma" = "$mb" ]; then same=bothfail; else same=bothfail-msg; fi
    elif [ "$ca" = "$cb" ] && cmp -s "$OUT/a.out" "$OUT/b.out"; then
      if [ "$ca" != ok ] || cmp -s "$OUT/a.out.err" "$OUT/b.out.err"; then same=yes
      elif cmp -s <(LC_ALL=C sort "$OUT/a.out.err") <(LC_ALL=C sort "$OUT/b.out.err"); then same=stderrorder
      else same=no; fi
    else same=no; fi
    ea=$(head -c 160 "$OUT/a.out.err" | head -1 | tr '\t' ' ')
    eb=$(head -c 160 "$OUT/b.out.err" | head -1 | tr '\t' ' ')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$same" "$fl" "$ca" "$cb" "$f" "$ea" "$eb" >> "$OUT/summary.tsv"
    if [ $same = no ] || [ $same = panic ]; then
      bad=$((bad+1))
      k=$(printf '%s%s' "$f" "$fl" | md5sum | cut -c1-10)
      cp "$OUT/a.out" "$OUT/$k.a.out"; cp "$OUT/b.out" "$OUT/$k.b.out"
      cp "$OUT/a.out.err" "$OUT/$k.a.err"; cp "$OUT/b.out.err" "$OUT/$k.b.err"
      printf '%s\t%s\t%s\n' "$k" "$fl" "$f" >> "$OUT/mismatches.tsv"
    fi
  done
done < "$LIST"
rm -f "$OUT/a.out" "$OUT/b.out" "$OUT/a.out.err" "$OUT/b.out.err"
bf=$(grep -c '^bothfail\s' "$OUT/summary.tsv" || true)
bm=$(grep -c '^bothfail-msg' "$OUT/summary.tsv" || true)
so=$(grep -c '^stderrorder' "$OUT/summary.tsv" || true)
bt=$(grep -c '^bothtimeout' "$OUT/summary.tsv" || true)
pn=$(grep -c '^panic' "$OUT/summary.tsv" || true)
echo "diff_main_elf: $n cases, $bad mismatches ($pn with a Lean panic), $so stderr-order-only, $bf both-failed (same message), $bm both-failed (different messages), $bt both-timed-out (summary: $OUT/summary.tsv)"
[ $bad -eq 0 ]
