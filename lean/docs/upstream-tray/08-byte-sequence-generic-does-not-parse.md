# `byte_sequence_generic.lem` does not parse; its `find_byte` is also wrong

**Affected:** `src/byte_sequence_generic.lem:32-41` (`find_byte`), `master`
@ `4464128`.

## Description

`find_byte` has two unterminated `match`es (a `(`...`)` where Lem needs
`match ... end`), so the file is a syntax error for Lem, and with it the
prover extractions (`make isa-extraction` etc., which use this generic
byte-sequence implementation) fail at once. Beyond the syntax, the function
never compares a byte with the one searched for (it can only return
`Nothing`), is recursive without `let rec`, writes `Just n + 1` for
`Just (n + 1)`, and the file uses `maybe` without `open import Maybe`.

## Reproducer

With upstream Lem (rems-project/lem `f5529b2`) and with lem-lean's lem,
identically (verbatim):

```
$ lem -wl ign -isa byte_sequence_generic.lem
File "byte_sequence_generic.lem", line 40, character 6:
  Syntax error
```

Running the Isabelle extraction's file list (`LEM_MODEL_TP_THY` of
`src/lem.mk`) on `master`:

```
linksem-upstream: lem -isa exit=1; 0 .thy files; last log lines:
File "byte_sequence_generic.lem", line 40, character 6:
  Syntax error
```

With the proposed fix applied (checked 2026-09-29) the extraction gets past this
file and stops later, in `dwarf.lem`, on OCaml-only helpers
(`print_endline` without an Isabelle target rep: a separate matter, not
addressed here):

```
with the proposed fix: lem -isa exit=1; 0 .thy files; last log lines:
File "dwarf.lem", line 131, character 19 to line 131, character 31
  Type error: unbound variable for targets {isabelle}: print_endline
```

The fixed generic `find_byte`, extracted to OCaml and run (verbatim):

```
find_byte abc 'c' -> Just 2
find_byte abc 'a' -> Just 0
find_byte abc 'z' -> Nothing
find_byte  'a' -> Nothing
```

(the first-occurrence index, as the OCaml implementation
`Byte_sequence_wrapper.find_byte` and the spec in `byte_sequence.lem:29`
give.)

## Impact

The prover extractions of linksem cannot currently be regenerated from
`master` (they stop here; after this fix, at `dwarf.lem`).

## Proposed remedy

Branch the proposed fix (two commits: close the matches;
then compare bytes, `let rec`, parenthesise, import `Maybe`).

## Classification

**TRUE BUG.**
