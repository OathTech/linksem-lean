#!/usr/bin/env bash
# Twin differential: the hand-written Lean twins (lean/handwritten) against
# the OCaml helpers they mirror (src/*.ml), on seeded cases (gen_cases.py).
# Usage: run.sh OUTDIR [SEED [N]]   (N = rounds of gen_cases.py; ~58 cases each)
# Env: CAPPED (required: lem-lean scripts/capped), OCAML_SRC (the src dir
# whose helpers are the reference; default ../../src -- point it at an
# upstream checkout to compare against upstream).
# A case the OCaml side raises on must also make the Lean side fail: those
# are re-run one per process. Exit 1 on any difference.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); L=$(cd "$HERE/.." && pwd)
OUT="$1"; SEED="${2:-1}"; N="${3:-500}"
SRC=$(cd "${OCAML_SRC:-$L/../src}" && pwd)
[ -n "${CAPPED:-}" ] && [ -x "$CAPPED" ] || { echo "twins/run.sh: set CAPPED=/path/to/lem-lean/scripts/capped" >&2; exit 2; }
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then echo "twins/run.sh: $OUT not empty" >&2; exit 2; fi
LEAN="$L/.lake/build/bin/twin_probe"
[ -x "$LEAN" ] || { echo "twins/run.sh: build the Lean side first (lake build twin_probe)" >&2; exit 2; }
mkdir -p "$OUT/build"
# the OCaml probe: the same helper modules (and packages) as src/lem.mk's ALL_UTIL_ML
MODS="uint64_wrapper.ml uint32_wrapper.ml show.ml endianness.ml error.ml ml_bindings.ml missing_pervasives.ml multimap.ml default_printing.ml byte_sequence_wrapper.ml byte_sequence_impl.ml filesystem.ml filesystem_wrapper.ml"
(cd "$SRC" && cp $MODS "$OUT/build/") || { echo "twins/run.sh: helper modules missing in $SRC (build it first)" >&2; exit 2; }
cp "$HERE/twin_probe.ml" "$OUT/build/"
(cd "$OUT/build" && ocamlfind ocamlopt -package num -package lem -package unix -package str -linkpkg $MODS twin_probe.ml -o twin_probe.opt > build.log 2>&1) \
  || { echo "twins/run.sh: OCaml probe build failed: $OUT/build/build.log" >&2; exit 2; }
python3 "$HERE/gen_cases.py" "$SEED" "$N" > "$OUT/cases.txt" || exit 2
CERB_MEM_MAX=4G "$CAPPED" "$OUT/build/twin_probe.opt" < "$OUT/cases.txt" > "$OUT/ocaml.txt" 2> "$OUT/ocaml.err" \
  || { echo "twins/run.sh: OCaml probe failed" >&2; exit 2; }
# the Lean batch gets the cases OCaml evaluates without raising
paste -d'\t' "$OUT/ocaml.txt" "$OUT/cases.txt" | awk -F'\t' '$1 !~ /^exc /' | cut -f2- > "$OUT/cases.ok.txt"
paste -d'\t' "$OUT/ocaml.txt" "$OUT/cases.txt" | awk -F'\t' '$1 !~ /^exc /' | cut -f1 > "$OUT/ocaml.ok.txt"
CERB_MEM_MAX=4G "$CAPPED" "$LEAN" < "$OUT/cases.ok.txt" > "$OUT/lean.ok.txt" 2> "$OUT/lean.err"; lst=$?
python3 - "$OUT" "$lst" <<'PY'
import sys
out, lst = sys.argv[1], int(sys.argv[2])
c = open(out + '/cases.ok.txt').read().splitlines()
o = open(out + '/ocaml.ok.txt').read().splitlines()
l = open(out + '/lean.ok.txt').read().splitlines()
bad = [i for i in range(len(c)) if i >= len(l) or o[i] != l[i]]
with open(out + '/diffs.txt', 'w') as f:
    for i in bad:
        f.write('CASE  %s\nOCAML %s\nLEAN  %s\n\n' % (c[i], o[i], l[i] if i < len(l) else '<no output: Lean stopped (exit %d), see lean.err>' % lst))
print('batch: %d cases, %d differ' % (len(c), len(bad)))
sys.exit(1 if bad else 0)
PY
st=$?
# cases OCaml raises on: each must also fail on the Lean side
paste -d'\t' "$OUT/ocaml.txt" "$OUT/cases.txt" | awk -F'\t' '$1 ~ /^exc /' > "$OUT/raising.txt"
nr=0; nbad=0
while IFS= read -r line; do
  nr=$((nr+1)); case_=$(printf '%s' "$line" | cut -f2-)
  printf '%s\n' "$case_" | CERB_MEM_MAX=4G "$CAPPED" "$LEAN" > /dev/null 2>&1 && {
    nbad=$((nbad+1)); printf 'CASE  %s\nOCAML %s\nLEAN  <succeeded>\n\n' "$case_" "$(printf '%s' "$line" | cut -f1)" >> "$OUT/diffs.txt"; }
done < "$OUT/raising.txt"
echo "raising: $nr cases OCaml raises on, $nbad where Lean did not fail"
[ $nbad -eq 0 ] || st=1
echo "twins/run.sh: seed $SEED, $(wc -l < "$OUT/cases.txt") cases; $( [ $st -eq 0 ] && echo 'no difference' || echo "DIFFERENCES: $OUT/diffs.txt")"
exit $st
