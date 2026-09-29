#!/usr/bin/env bash
# OCaml-vs-Lean fuzz lane: deterministic mutants (mutate.py) of the corpus
# files at most MAX_BYTES in size, run through diff_main_elf.sh (same
# verdicts: a mismatch or a Lean panic fails the lane) for main_elf flags
# and dump_image, in SHARDS parallel shards.
# Usage: run_fuzz.sh CORPUS_LIST OUTDIR [SEED [PER_FILE]]
# Env: CAPPED (required), DIFF_MEM (4G per run), MAX_BYTES (200000),
#      SHARDS (8), FUZZ_TIMEOUT (20 s per run),
#      FLAGS (main_elf flags, space-separated).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); L=$(cd "$HERE/.." && pwd)
LIST="$1"; OUT="$2"; SEED="${3:-1}"; PER="${4:-20}"
MAX_BYTES="${MAX_BYTES:-200000}"; SHARDS="${SHARDS:-8}"
FLAGS="${FLAGS:---file-header --program-headers --section-headers --relocs --dynamic --symbols}"
# Mutants are built to exhaust resources: every run is memory-capped by
# diff_main_elf.sh through CAPPED (lem-lean scripts/capped; DIFF_MEM per run).
[ -n "${CAPPED:-}" ] || [ "${DIFF_UNCAPPED:-}" = 1 ] || {
  echo "run_fuzz: set CAPPED=/path/to/lem-lean/scripts/capped (per-run memory cap)" >&2; exit 2; }
[ -s "$LIST" ] || { echo "run_fuzz: empty corpus list $LIST" >&2; exit 2; }
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then echo "run_fuzz: $OUT not empty" >&2; exit 2; fi
mkdir -p "$OUT/mutants" "$OUT/snapshot"
# Run from a snapshot of the runner and the four tools: a rebuild or an edit
# of diff_main_elf.sh during a long run must not change what is being run
# (bash reads scripts incrementally), and the results name exact binaries.
cp "$L/diff_main_elf.sh" "$L/../src/main_elf.opt" "$L/../src/dump_image.opt" \
   "$L/.lake/build/bin/main_elf" "$OUT/snapshot/" || exit 2
cp "$L/.lake/build/bin/dump_image" "$OUT/snapshot/dump_image.lean" || exit 2
mv "$OUT/snapshot/main_elf" "$OUT/snapshot/main_elf.lean"
sha256sum "$OUT"/snapshot/* > "$OUT/snapshot.sha256"
S="$OUT/snapshot"
mapfile -t files < <(while IFS= read -r f; do
  [ -f "$f" ] || { echo "run_fuzz: corpus file missing: $f" >&2; exit 2; }
  [ "$(stat -c %s "$f")" -le "$MAX_BYTES" ] && echo "$f"; done < "$LIST")
[ ${#files[@]} -gt 0 ] || { echo "run_fuzz: no corpus file <= $MAX_BYTES bytes" >&2; exit 2; }
python3 "$HERE/mutate.py" "$SEED" "$PER" "$OUT/mutants" "${files[@]}" > "$OUT/mutants.txt" || exit 2
split -n "l/$SHARDS" -d "$OUT/mutants.txt" "$OUT/shard."
st=0; pids=()
for s in "$OUT"/shard.*; do
  k=${s##*.}
  ( DIFF_TIMEOUT="${FUZZ_TIMEOUT:-20}" bash "$S/diff_main_elf.sh" "$S/main_elf.opt" "$S/main_elf.lean" "$s" "$OUT/elf.$k" $FLAGS > "$OUT/elf.$k.log" 2>&1
    DIFF_TIMEOUT="${FUZZ_TIMEOUT:-20}" bash "$S/diff_main_elf.sh" "$S/dump_image.opt" "$S/dump_image.lean" "$s" "$OUT/img.$k" @ > "$OUT/img.$k.log" 2>&1 ) &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
cat "$OUT"/elf.*/summary.tsv > "$OUT/elf.summary.tsv"; cat "$OUT"/img.*/summary.tsv > "$OUT/img.summary.tsv"
for lane in elf img; do
  printf '%s: ' "$lane"; cut -f1 "$OUT/$lane.summary.tsv" | sort | uniq -c | tr '\n' ' '; echo
  if grep -q -E '^(no|panic)\s' "$OUT/$lane.summary.tsv"; then st=1; fi
done
echo "run_fuzz: seed $SEED, ${#files[@]} files x $PER mutants ($(wc -l < "$OUT/mutants.txt")); $( [ $st -eq 0 ] && echo 'no mismatch, no panic' || echo 'MISMATCHES or PANICS: see */mismatches.tsv')"
exit $st
