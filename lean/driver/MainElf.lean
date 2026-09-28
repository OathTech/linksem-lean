import Main_elf

/-!
The Lean `main_elf`: the I/O shell around the generated `main_elf_run` /
`main_elf_render` (src/main_elf.lem), mirroring the OCaml driver there
(`let {ocaml} _ = ...`) line for line:

* `argv` is `progname :: flag :: fname :: _`, else `failwith "usage: ..."`
  (an uncaught exception: loud abort);
* `Byte_sequence.acquire fname` (an OCaml Sys_error on a missing file is an
  uncaught exception: loud abort, here via `acquire`'s panic);
* `Left err` goes to stderr with `errln`, `Right out` to stdout with
  `outln`; the exit status is 0 in both cases, as in OCaml.

Run with `LEAN_ABORT_ON_PANIC=1` so that a reached `failwithI` (the
model's `failwith`/`fail`-to-exception sites) stops the process as the
OCaml exception does.
-/

def main (args : List String) : IO UInt32 := do
  match args with
  | flag :: fname :: _ =>
    match Byte_sequence_wrapper.acquire fname with
    | .Fail e =>
      -- `acquire` returns `Fail` only if the file system call succeeded
      -- but the model rejected it; mirrors the OCaml `>>=` short-circuit.
      IO.eprintln s!"[!]: {e}"
      return 0
    | .Success bs0 =>
      match main_elf_render (main_elf_run flag fname bs0) with
      | .inl err => IO.eprintln err; return 0
      | .inr out => IO.println out; return 0
  | _ =>
    IO.eprintln "Fatal error: exception Failure(\"usage: main_elf <flag> <fname>\")"
    return 2
