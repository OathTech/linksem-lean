#!/usr/bin/env bash
# Differential runner for main_link: runs two main_link builds (A = OCaml
# src/main_link.opt, B = Lean) over the corpus built by
# link-corpus/build_cases.sh and compares, per case:
#   - the exit class (ok | fail:<status> | timeout),
#   - the linked output `out.test-out` (presence and bytes),
#   - stdout, byte for byte, and
#   - stderr, byte for byte, when both exit 0 (the driver's diagnostics and
#     the model's `errln` output, which the Lean side keeps since lem-lean
#     B15).
# Verdicts: yes; no (mismatch); panic (hard condition "zero panics": a Lean
# panic that is not the rendering of a failure OCaml also raises -- any panic
# where OCaml did not fail, or a backend-internal one); bothfail (both fail
# with the SAME message: OCaml's Failure text = Lean's panic text);
# bothfail-msg (both fail, different messages: review, cf. lem-lean audit
# A3/A4); stderrorder (everything equal except the ORDER of stderr lines:
# lem-lean A4, OCaml evaluates constructor arguments right to left, e.g.
# Lem's count_map applies f from the last element; reviewed, not a
# mismatch); bothtimeout. Each side runs in its own copy of the case (both
# write out.test-out next to the reference executable `out`).
# Usage: diff_main_link.sh A_BIN B_BIN CASES_DIR OUTDIR
# Exit 1 if any case differs; 2 on a usage or corpus error.
set -uo pipefail
A="$1"; B="$2"; CASES="$3"; OUT="$4"
TIMEOUT="${DIFF_TIMEOUT:-600}"
[ -x "$A" ] && [ -x "$B" ] || { echo "diff_main_link: A or B not executable" >&2; exit 2; }
A=$(realpath "$A"); B=$(realpath "$B")   # the runs cd into each case
mkdir -p "$OUT"; : > "$OUT/summary.tsv"
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
run() { # bin workdir -> prints exit class
  local st args
  mapfile -t args < "$2/inputs"
  (cd "$2" && LEAN_ABORT_ON_PANIC=1 timeout "$TIMEOUT" "$1" -o out "${args[@]}" > stdout 2> stderr); st=$?
  if [ $st -eq 126 ] || [ $st -eq 127 ]; then
    echo "diff_main_link: could not execute $1 (exit $st)" >&2; exit 2; fi
  if [ $st -eq 0 ]; then echo ok; elif [ $st -eq 124 ]; then echo timeout; else echo "fail:$st"; fi
}
for c in "$CASES"/*/; do
  c=${c%/}; name=$(basename "$c")
  [ -s "$c/inputs" ] && [ -f "$c/out" ] || { echo "diff_main_link: malformed case $c" >&2; exit 2; }
  n=$((n+1))
  rm -rf "$OUT/$name"; mkdir -p "$OUT/$name"
  cp -r "$c" "$OUT/$name/a"; cp -r "$c" "$OUT/$name/b"
  ca=$(run "$A" "$OUT/$name/a") || exit 2
  cb=$(run "$B" "$OUT/$name/b") || exit 2
  a="$OUT/$name/a"; b="$OUT/$name/b"
  same_file() { # both absent, or both present and identical
    if [ -f "$a/out.test-out" ] && [ -f "$b/out.test-out" ]; then cmp -s "$a/out.test-out" "$b/out.test-out"
    else [ ! -f "$a/out.test-out" ] && [ ! -f "$b/out.test-out" ]; fi
  }
  ka=${ca%%:*}; kb=${cb%%:*}
  if bad_panic "$b/stderr" "$ka"; then v=panic
  elif [ "$ca" = timeout ] && [ "$cb" = timeout ]; then v=bothtimeout
  elif [ "$ka" = fail ] && [ "$kb" = fail ]; then
    ma=$(fail_msg "$a/stderr"); mb=$(fail_msg "$b/stderr")
    if [ -n "$ma" ] && [ "$ma" = "$mb" ]; then v=bothfail; else v=bothfail-msg; fi
  elif [ "$ca" = "$cb" ] && same_file && cmp -s "$a/stdout" "$b/stdout"; then
    if [ "$ca" != ok ] || cmp -s "$a/stderr" "$b/stderr"; then v=yes
    elif cmp -s <(LC_ALL=C sort "$a/stderr") <(LC_ALL=C sort "$b/stderr"); then v=stderrorder
    else v=no; fi
  else v=no; fi
  ea=$(tail -1 "$a/stderr" | head -c 160 | tr '\t' ' ')
  eb=$(tail -1 "$b/stderr" | head -c 160 | tr '\t' ' ')
  fa=$([ -f "$a/out.test-out" ] && echo written || echo none)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$name" "$ca" "$cb" "$fa" "$ea" "$eb" >> "$OUT/summary.tsv"
  case $v in
    no|panic) bad=$((bad+1)) ;;
    bothfail-msg|stderrorder) ;;   # kept for review
    *) rm -rf "$OUT/$name" ;;
  esac
done
[ $n -gt 0 ] || { echo "diff_main_link: no cases in $CASES (vacuous)" >&2; exit 2; }
bf=$(grep -c '^bothfail\s' "$OUT/summary.tsv" || true)
bm=$(grep -c '^bothfail-msg' "$OUT/summary.tsv" || true)
so=$(grep -c '^stderrorder' "$OUT/summary.tsv" || true)
bt=$(grep -c '^bothtimeout' "$OUT/summary.tsv" || true)
pn=$(grep -c '^panic' "$OUT/summary.tsv" || true)
wr=$(awk -F'\t' '($1=="yes" || $1=="stderrorder") && $5=="written"' "$OUT/summary.tsv" | wc -l)
echo "diff_main_link: $n cases, $bad mismatches ($pn with a Lean panic), $wr identical linked outputs, $so stderr-order-only, $bf both-failed (same message), $bm both-failed (different messages), $bt both-timed-out (summary: $OUT/summary.tsv)"
[ $bad -eq 0 ]
