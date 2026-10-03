#!/usr/bin/env bash
# Rewrite lakefile.lean's generated-module list from generated/*.lean.
# Called by src/lem.mk `lean-extraction`. Fail-closed: no module, no markers,
# or a malformed name is an error.
set -euo pipefail
cd "$(dirname "$0")"
# Byte order (LC_ALL=C), not the caller's locale: the list is committed, so
# its order must not depend on who regenerates it.
mods=$(cd generated && ls *.lean | grep -v -e '_auxiliary\.lean$' -e '_lemMeasureProofs\.lean$' | sed 's/\.lean$//' | LC_ALL=C sort)
[ -n "$mods" ] || { echo "gen-roots: no generated modules" >&2; exit 1; }
grep -q -- '-- BEGIN generated module list' lakefile.lean && grep -q -- '-- END generated module list' lakefile.lean \
  || { echo "gen-roots: markers missing from lakefile.lean" >&2; exit 1; }
for m in $mods; do [[ "$m" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || { echo "gen-roots: bad module name '$m'" >&2; exit 1; }; done
body=$(for m in $mods; do echo "  \`$m,"; done)
awk -v body="$body" '
  /-- BEGIN generated module list/ { print; print body; skip=1; next }
  /-- END generated module list/   { skip=0 }
  !skip' lakefile.lean > lakefile.lean.tmp
mv lakefile.lean.tmp lakefile.lean
echo "gen-roots: $(echo "$mods" | wc -l) modules" >&2
