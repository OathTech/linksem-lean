#!/usr/bin/env bash
# Build the main_link differential corpus (cases.txt) into OUTDIR/<case>/:
# the input objects/archives, `inputs` (the link-order argument list) and
# `out`, the reference executable from `ld -static` (main_link reads it to
# choose the ABI and writes its own result next to it as out.test-out).
# Fail-closed: any compile or reference-link failure stops the build.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build_cases.sh OUTDIR}
BASE="-c -ffreestanding -fno-stack-protector -fno-builtin -nostdlib -fno-asynchronous-unwind-tables"
# a fresh directory: stale cases from an older cases.txt must not linger
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then
  echo "build_cases: $OUT is not empty (remove it first)" >&2; exit 1; fi
mkdir -p "$OUT"
n=0
while IFS='|' read -r name flags inputs; do
  name=$(echo "$name" | xargs); [ -z "$name" ] && continue
  case "$name" in \#*) continue;; esac
  flags=$(echo "$flags" | xargs); inputs=$(echo "$inputs" | xargs)
  d="$OUT/$name"; rm -rf "$d"; mkdir -p "$d"
  compile() { # src -> object name
    local s=$1 o=${1%.*}.o
    case "$s" in
      *.s) as --64 -o "$d/$o" "$HERE/src/$s" ;;
      *.c) gcc $BASE -fno-pie $flags -I "$HERE/src" -o "$d/$o" "$HERE/src/$s" ;;
      *) echo "build_cases: unknown source kind $s" >&2; exit 1 ;;
    esac
    echo "$o"
  }
  args=()
  # split inputs at spaces outside parentheses
  for tok in $(echo "$inputs" | sed 's/ \([^()]*\))/:\1)/g; s/(\([^:)]*\):/(\1:/g'); do
    if [[ "$tok" == *.a\(* ]]; then
      lib=${tok%%(*}; members=${tok#*(}; members=${members%)}
      objs=(); for m in ${members//:/ }; do objs+=("$(compile "$m")"); done
      (cd "$d" && ar rcs "$lib" "${objs[@]}")
      args+=("$lib")
    else
      args+=("$(compile "$tok")")
    fi
  done
  (cd "$d" && ld -static -e _start -o out "${args[@]}")
  printf '%s\n' "${args[@]}" > "$d/inputs"
  n=$((n+1))
done < "$HERE/cases.txt"
[ "$n" -gt 0 ] || { echo "build_cases: no cases (vacuous)" >&2; exit 1; }
echo "build_cases: $n cases in $OUT"
