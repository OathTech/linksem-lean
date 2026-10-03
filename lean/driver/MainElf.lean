import Main_elf

/-!
The Lean `main_elf`: the I/O shell around the generated `main_elf_run` /
`main_elf_render` (src/main_elf.lem), mirroring the OCaml driver there
(`let {ocaml} _ = ...`):

* `--help` prints `usage_text` to stdout; `flag :: fname :: _` runs;
  anything else prints `usage_text` to stderr; exit status 0 throughout;
* `Byte_sequence.acquire fname` (an OCaml Sys_error on a missing file is an
  uncaught exception: here `acquire` panics);
* `Left err` goes to stderr with `errln`, `Right out` to stdout with `outln`;
  exit status 0 in both cases, as in OCaml.

Fail-stop: `lemRequireAbortOnPanic` (LemLib) refuses to run (exit 2)
unless `LEAN_ABORT_ON_PANIC=1`, so every reached failure (a `failwithI`
panic: the model's `failwith`, or an OCaml-exception mirror in the
hand-written layer) aborts the program, as the OCaml exception stops the
OCaml program -- without it a Lean panic continues with a default value.

Byte output (audit item 5): output is written byte-exactly, as OCaml's
`print_string` does (`Ml_bindings.writeString`).

Known limitation: Lean's file APIs take a UTF-8 `String`, so a file name
that is not valid UTF-8 cannot be opened (OCaml can); it fails loudly.
-/

def main (args : List String) : IO UInt32 := do
  lemRequireAbortOnPanic
  match args with
  | "--help" :: _ =>
    Ml_bindings.writeString (← IO.getStdout) usage_text true
    return 0
  | flag :: fname :: _ =>
    match Byte_sequence_wrapper.acquire fname with
    | .Fail e =>
      Ml_bindings.writeString (← IO.getStderr) s!"[!]: {e}" true
      return 0
    | .Success bs0 =>
      match main_elf_render (main_elf_run flag fname bs0) with
      | .inl err => Ml_bindings.writeString (← IO.getStderr) err true; return 0
      | .inr out => Ml_bindings.writeString (← IO.getStdout) out true; return 0
  | _ =>
    Ml_bindings.writeString (← IO.getStderr) usage_text true
    return 0
