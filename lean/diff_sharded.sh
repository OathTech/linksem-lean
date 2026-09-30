#!/usr/bin/env bash
# Parallel wrapper for diff_main_elf.sh: splits CORPUS_LIST into SHARDS
# parts (by file) and runs one diff_main_elf.sh per part concurrently, from
# a snapshot of the runner and both binaries (a rebuild during the run does
# not change what is being run), then merges the summaries.
# Usage: diff_sharded.sh A_BIN B_BIN CORPUS_LIST OUTDIR [FLAGS...]
# Env: SHARDS (8), plus everything diff_main_elf.sh reads (CAPPED required,
# DIFF_MEM, DIFF_TIMEOUT). Exit 1 if any case is `no` or `panic`.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
A="$1"; B="$2"; LIST="$3"; OUT="$4"; shift 4
SHARDS="${SHARDS:-8}"
[ -x "$A" ] && [ -x "$B" ] || { echo "diff_sharded: A or B not executable" >&2; exit 2; }
[ -s "$LIST" ] || { echo "diff_sharded: empty corpus list $LIST" >&2; exit 2; }
[ -n "${CAPPED:-}" ] || [ "${DIFF_UNCAPPED:-}" = 1 ] || { echo "diff_sharded: set CAPPED=/path/to/lem-lean/scripts/capped" >&2; exit 2; }
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then echo "diff_sharded: $OUT not empty" >&2; exit 2; fi
mkdir -p "$OUT/snapshot"
cp "$HERE/diff_main_elf.sh" "$OUT/snapshot/" && cp "$A" "$OUT/snapshot/A" && cp "$B" "$OUT/snapshot/B" || exit 2
sha256sum "$OUT"/snapshot/* > "$OUT/snapshot.sha256"
# round-robin by file so the few slow files land in different shards
awk -v n="$SHARDS" -v o="$OUT" '{ print > (o "/list." sprintf("%02d", NR % n)) }' "$LIST"
pids=()
for l in "$OUT"/list.*; do
  k=${l##*.}
  bash "$OUT/snapshot/diff_main_elf.sh" "$OUT/snapshot/A" "$OUT/snapshot/B" "$l" "$OUT/shard.$k" "$@" > "$OUT/shard.$k.log" 2>&1 &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
for k in "$OUT"/shard.*.log; do
  grep -q "^diff_main_elf: [0-9]* cases" "$k" || { echo "diff_sharded: shard did not finish: $k" >&2; exit 2; }
done
cat "$OUT"/shard.*/summary.tsv > "$OUT/summary.tsv"
cat "$OUT"/shard.*/mismatches.tsv > "$OUT/mismatches.tsv" 2>/dev/null || true
n=$(wc -l < "$OUT/summary.tsv")
counts=$(cut -f1 "$OUT/summary.tsv" | sort | uniq -c | awk '{printf "%s %s, ", $1, $2}')
echo "diff_sharded: $n cases in $SHARDS shards: ${counts%, } (summary: $OUT/summary.tsv; per-shard mismatch outputs in $OUT/shard.*)"
grep -q -E '^(no|panic)\s' "$OUT/summary.tsv" && exit 1
exit 0
