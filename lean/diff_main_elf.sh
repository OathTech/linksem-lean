#!/usr/bin/env bash
# Differential runner for main_elf: runs two main_elf builds (A, B) over a
# corpus of ELF files x flags and compares, per (file, flag):
#   - the exit class (ok | fail:<status> | timeout), and
#   - stdout, byte for byte.
# Usage: diff_main_elf.sh A_BIN B_BIN CORPUS_LIST OUTDIR [FLAGS...]
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
run() { # bin file flag outfile -> prints exit class
  local st
  LEAN_ABORT_ON_PANIC=1 timeout "$TIMEOUT" "$1" "$3" "$2" > "$4" 2> "$4.err"; st=$?
  if [ $st -eq 0 ]; then echo ok; elif [ $st -eq 124 ]; then echo timeout; else echo "fail:$st"; fi
}
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || { echo "diff_main_elf: corpus file missing: $f" >&2; exit 2; }
  for fl in "${FLAGS[@]}"; do
    n=$((n+1))
    ca=$(run "$A" "$f" "$fl" "$OUT/a.out")
    cb=$(run "$B" "$f" "$fl" "$OUT/b.out")
    # Both failed: agreement on the OUTCOME only (OCaml exits 2 on an
    # uncaught exception, Lean aborts with 134); reported as its own
    # category `bothfail` with each side's first stderr line, for review.
    ka=${ca%%:*}; kb=${cb%%:*}
    if [ "$ka" = fail ] && [ "$kb" = fail ]; then same=bothfail
    elif [ "$ca" = "$cb" ] && cmp -s "$OUT/a.out" "$OUT/b.out"; then same=yes
    else same=no; fi
    ea=$(head -c 160 "$OUT/a.out.err" | head -1 | tr '\t' ' ')
    eb=$(head -c 160 "$OUT/b.out.err" | head -1 | tr '\t' ' ')
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$same" "$fl" "$ca" "$cb" "$f" "$ea" "$eb" >> "$OUT/summary.tsv"
    if [ $same = no ]; then
      bad=$((bad+1))
      k=$(printf '%s%s' "$f" "$fl" | md5sum | cut -c1-10)
      cp "$OUT/a.out" "$OUT/$k.a.out"; cp "$OUT/b.out" "$OUT/$k.b.out"
      cp "$OUT/a.out.err" "$OUT/$k.a.err"; cp "$OUT/b.out.err" "$OUT/$k.b.err"
      printf '%s\t%s\t%s\n' "$k" "$fl" "$f" >> "$OUT/mismatches.tsv"
    fi
  done
done < "$LIST"
rm -f "$OUT/a.out" "$OUT/b.out" "$OUT/a.out.err" "$OUT/b.out.err"
bf=$(grep -c '^bothfail' "$OUT/summary.tsv" || true)
echo "diff_main_elf: $n cases, $bad mismatches, $bf both-failed (summary: $OUT/summary.tsv)"
[ $bad -eq 0 ]
