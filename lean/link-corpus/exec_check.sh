#!/usr/bin/env bash
# Upstream-correctness oracle for the linker (independent of the Lean port):
# for every case built by build_cases.sh, link it with MAIN_LINK (linksem's
# OCaml main_link.opt, or the Lean one: the linker lane shows they write
# identical files) and RUN both executables, ld's reference `out` and
# linksem's `out.test-out`; each case program exits with a computed status.
# Verdicts: same (equal exit status), differs (a linksem linking bug, or a
# program that depends on layout), nolink (main_link wrote no output: see
# its stderr), noexec (linksem's output could not be executed at all),
# refcrash (ld's own executable died on a signal: a test-program defect,
# e.g. TLS without a runtime to set it up; not evidence about linksem).
# A linked output that readelf -a warns about (an ELF conformance defect,
# independent oracle) is reported as `readelf` whatever the exit status.
# Usage: exec_check.sh MAIN_LINK CASES_DIR OUTDIR. Exit 1 if any case is
# not `same` (the verdicts are findings to review, not port mismatches).
set -uo pipefail
ML=$(realpath "$1"); CASES="$2"; OUT="$3"
TIMEOUT="${EXEC_TIMEOUT:-10}"
[ -x "$ML" ] || { echo "exec_check: $1 not executable" >&2; exit 2; }
mkdir -p "$OUT"; : > "$OUT/exec.tsv"
n=0; bad=0
for c in "$CASES"/*/; do
  c=${c%/}; name=$(basename "$c"); n=$((n+1))
  w="$OUT/$name"; rm -rf "$w"; cp -r "$c" "$w"
  mapfile -t args < "$w/inputs"
  (cd "$w" && timeout 600 "$ML" -o out "${args[@]}" > ml.stdout 2> ml.stderr)
  (cd "$w" && timeout "$TIMEOUT" ./out > /dev/null 2>&1); ref=$?
  if [ "$ref" -ge 128 ]; then v=refcrash; got=-
  elif [ ! -f "$w/out.test-out" ]; then v=nolink; got=-
  else
    chmod +x "$w/out.test-out"
    (cd "$w" && timeout "$TIMEOUT" ./out.test-out > /dev/null 2> run.stderr); got=$?
    readelf -W -a "$w/out.test-out" > /dev/null 2> "$w/readelf.warnings"
    if [ -s "$w/readelf.warnings" ]; then v=readelf
    elif [ "$got" = "$ref" ]; then v=same
    elif [ "$got" -eq 126 ] || [ "$got" -eq 127 ]; then v=noexec
    else v=differs; fi
  fi
  [ $v = same ] || bad=$((bad+1))
  printf '%s\t%s\t%s\t%s\n' "$v" "$name" "$ref" "$got" >> "$OUT/exec.tsv"
done
[ $n -gt 0 ] || { echo "exec_check: no cases (vacuous)" >&2; exit 2; }
echo "exec_check: $n cases, $((n-bad)) same exit status as ld's executable, $bad to review (summary: $OUT/exec.tsv)"
[ $bad -eq 0 ]
