# Lem OCaml backend: `Assert_extra.fail` applied to an argument prints as invalid OCaml

**Affected:** Lem `library/assert_extra.lem:27-29` (rems-project/lem
`f5529b2`, 2026-03-04):

```lem
val fail : forall 'a. 'a
let fail = failwith "fail"
declare ocaml target_rep function fail = `assert` `false`
```

## Description

`fail` has type `forall 'a. 'a`, so a Lem program may apply it to an
argument (then `'a` is a function type), e.g. `fail "message"`, easily
confused with `failwith` or with a module's own `fail : string -> error
'a` when `Assert_extra` is opened. The OCaml target rep is the two tokens
`assert false`, and the application is printed as `(assert false "msg")`,
which OCaml rejects as a syntax error (`assert` takes one argument). Lem accepts the program; the failure appears only when compiling
the generated OCaml.

## Reproducer

```lem
open import Pervasives_extra
open import Assert_extra

val pick : nat -> nat
let pick n = if n = 0 then fail "pick: zero" else n
```

Upstream Lem `f5529b2`, `lem -wl ign -ocaml failarg.lem` succeeds (exit 0);
the output, verbatim:

```ocaml
let pick n:int=  (if n = 0 then (assert false "pick: zero") else n)
```

`ocamlfind ocamlopt -package lem_zarith -c failarg.ml` (OCaml 5.4.0),
verbatim:

```
File "failarg.ml", line 6, characters 46-58:
6 | let pick n:int=  (if n = 0 then (assert false "pick: zero") else n)
                                                  ^^^^^^^^^^^^
Error: Syntax error: ) expected
File "failarg.ml", line 6, characters 32-33:
6 | let pick n:int=  (if n = 0 then (assert false "pick: zero") else n)
                                    ^
  This ( might be unmatched
```

(Observed first in linksem: a test driver of ours wrote `fail "..."` in an
`error`-returning context where `Error.fail` was meant; Lem resolved the
unqualified `fail` to `Assert_extra.fail` and type-checked it.)

## Proposed remedy

Parenthesise the rep, e.g. `` declare ocaml target_rep function fail =
`(assert false)` `` (then an application prints as `((assert false) "msg")`,
valid OCaml that raises `Assert_failure`), or print a parenthesised form
whenever a multi-token rep is applied. Optionally warn when `fail` is
applied, since the user almost certainly meant `failwith`.

## Classification

**TRUE BUG** (Lem accepts a program and emits OCaml that does not compile).
Not checked against upstream Lem `master` beyond `f5529b2` (no network
access from the drafting environment).
