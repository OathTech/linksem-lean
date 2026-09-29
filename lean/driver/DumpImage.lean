import Dump_image

/-!
The Lean `dump_image`: the I/O shell around the generated `dump_image`
(src/dump_image.lem), mirroring its OCaml-only driver (`let {ocaml} _ = ...`):
`argv` is `progname :: fname :: _`, else `failwith "usage: ..."`; `Left`/`Fail`
goes to stderr as `[!]: err`, the dump to stdout; exit 0 in both cases.
Fail-stop and byte-exact output as in `MainElf.lean`.
-/

def main (args : List String) : IO UInt32 := do
  lemFailStop
  match args with
  | fname :: _ =>
    let res : error String := match Byte_sequence_wrapper.acquire fname with
      | .Fail e => .Fail e
      | .Success bs0 => dump_image bs0
    match res with
    | .Fail err => Ml_bindings.writeString (← IO.getStderr) s!"[!]: {err}" true; return 0
    | .Success s => Ml_bindings.writeString (← IO.getStdout) s true; return 0
  | _ =>
    IO.eprintln "Fatal error: exception Failure(\"usage: dump_image <fname>\")"
    return 2
