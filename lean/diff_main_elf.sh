#!/usr/bin/env bash
# Differential runner for main_elf: runs two main_elf builds (A = OCaml
# src/main_elf.opt, the reference; B = Lean) over a corpus of ELF files x
# flags and compares, per (file, flag): the exit class (ok | fail:<status> |
# timeout), stdout byte for byte, and stderr byte for byte when both exit 0.
# Verdicts: yes, no (mismatch), bothfail and bothtimeout (listed with each
# side's stderr for review: agreement on the outcome only).
# Every run is memory-capped in its own cgroup by lem-lean's scripts/capped
# (CAPPED=/path/to/capped required; DIFF_MEM per run, default 4G).
# Usage: diff_main_elf.sh A_BIN B_BIN CORPUS_LIST OUTDIR [FLAGS...]
# Exit 1 if any case is `no`, 2 on a usage or corpus error.
set -uo pipefail
A="$1"; B="$2"; LIST="$3"; OUT="$4"; shift 4
FLAGS=("$@")
[ ${#FLAGS[@]} -gt 0 ] || FLAGS=(--file-header --program-headers --section-headers --relocs --dynamic --symbols)
TIMEOUT="${DIFF_TIMEOUT:-120}"
[ -n "${CAPPED:-}" ] && [ -x "$CAPPED" ] || { echo "diff_main_elf: set CAPPED=/path/to/lem-lean/scripts/capped" >&2; exit 2; }
[ -x "$A" ] && [ -x "$B" ] || { echo "diff_main_elf: A or B not executable" >&2; exit 2; }
[ -s "$LIST" ] || { echo "diff_main_elf: empty corpus list $LIST" >&2; exit 2; }
mkdir -p "$OUT"; : > "$OUT/summary.tsv"
run() { # bin file flag outfile -> prints exit class
  local st
  LEAN_ABORT_ON_PANIC=1 CERB_MEM_MAX="${DIFF_MEM:-4G}" "$CAPPED" timeout "$TIMEOUT" "$1" "$3" "$2" > "$4" 2> "$4.err"; st=$?
  if [ $st -eq 126 ] || [ $st -eq 127 ]; then echo "diff_main_elf: could not execute $1" >&2; exit 2; fi
  if [ $st -eq 0 ]; then echo ok; elif [ $st -eq 124 ]; then echo timeout; else echo "fail:$st"; fi
}
n=0; bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || { echo "diff_main_elf: corpus file missing: $f" >&2; exit 2; }
  for fl in "${FLAGS[@]}"; do
    n=$((n+1))
    ca=$(run "$A" "$f" "$fl" "$OUT/a.out") || exit 2
    cb=$(run "$B" "$f" "$fl" "$OUT/b.out") || exit 2
    if [ "$ca" = timeout ] && [ "$cb" = timeout ]; then v=bothtimeout
    elif [ "${ca%%:*}" = fail ] && [ "${cb%%:*}" = fail ]; then v=bothfail
    elif [ "$ca" = "$cb" ] && cmp -s "$OUT/a.out" "$OUT/b.out" \
         && { [ "$ca" != ok ] || cmp -s "$OUT/a.out.err" "$OUT/b.out.err"; }; then v=yes
    else v=no; fi
    ea=$(head -c 160 "$OUT/a.out.err" | head -1 | tr '\t' ' ')
    eb=$(grep -a -m1 . "$OUT/b.out.err" | head -c 160 | tr '\t' ' ')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$fl" "$ca" "$cb" "$f" "$ea" "$eb" >> "$OUT/summary.tsv"
    if [ $v = no ]; then
      bad=$((bad+1)); k=$(printf '%s%s' "$f" "$fl" | md5sum | cut -c1-10)
      for x in a.out b.out a.out.err b.out.err; do cp "$OUT/$x" "$OUT/$k.$x"; done
      printf '%s\t%s\t%s\n' "$k" "$fl" "$f" >> "$OUT/mismatches.tsv"
    fi
  done
done < "$LIST"
rm -f "$OUT"/a.out "$OUT"/b.out "$OUT"/a.out.err "$OUT"/b.out.err
bf=$(grep -c '^bothfail' "$OUT/summary.tsv" || true); bt=$(grep -c '^bothtimeout' "$OUT/summary.tsv" || true)
echo "diff_main_elf: $n cases, $bad mismatches, $bf both-failed, $bt both-timed-out (summary: $OUT/summary.tsv)"
[ $bad -eq 0 ]
