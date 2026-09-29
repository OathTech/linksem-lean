import Main_link

/-!
The Lean `main_link`: the I/O shell mirroring the OCaml-only driver at the
end of src/main_link.lem (`let {ocaml} _ = ...`), line for line:

* argv without the program name goes through `command_line_of_args` (the
  OCaml `command_line ()`, which applies it to `tail argv`);
* the diagnostics on stderr ("Got N input items: {...}", "Successfully opened
  output file", ...) and the final `[!]: err` / `true` / `false` line;
* the linked image is written to `<output>.test-out`, as in OCaml; a write
  error goes to stdout as `error writing output: ...`.

Exit status 0 unless a failure is reached: `lemFailStop` (lem-lean A2) makes
a reached failure print its message and exit 1, as the OCaml exception exits
2. Output is byte-exact (`Ml_bindings.writeString`). The model's own
`errln` diagnostics inside the linker are best-effort (see
`Ml_bindings`, "Console output from pure code"); the differential compares
the output file, stdout and the exit class.

Known difference (pure dead code): `correctly_linked` builds the memory image
of the OUTPUT file only to pass it to `images_consistent`, whose body is
`true`. OCaml evaluates it (and would raise if it failed); Lean's compiler
drops the unused pure value. Same family as lem-lean audit A3.
-/

open Ml_bindings in
def errln' (s : String) : IO Unit := do writeString (← IO.getStderr) s true

open Ml_bindings in
def outln' (s : String) : IO Unit := do writeString (← IO.getStdout) s true

/-- The `res` of the OCaml driver: `Fail err` or `Success (show v)`. The
diagnostics are written in the order the OCaml driver writes them. -/
def mainLinkRes (args : List String) : IO (error String) := do
  let (input_units, link_options) := command_line_of_args args
  let items_and_options := elaborate_input input_units
  let (input_items, _item_options) := items_and_options.unzip
  -- `show item` at input_item = string * input_blob * (origin pair): Lem
  -- resolves the TRIPLE instance (string_of_triple). Lean's `Show.show0`
  -- would pick the quad instance at this type (lem-lean B14), so call what
  -- Lem resolves to.
  errln' ("Got " ++ Show.show0 input_items.length ++ " input items: {"
    ++ (input_items.map (fun item => string_of_triple item ++ ",\n")).foldl (· ++ ·) "" ++ "}")
  let output_filename := match find_option_matching_tag (OutputFilename "") link_options with
    | none => "impossible: no output file specified, despite default value of `a.out'"
    | some (OutputFilename s) => s
    | some _ => "impossible: bad output filename option returned"
  match Byte_sequence_wrapper.acquire output_filename with
  | .Fail e => return .Fail e
  | .Success out =>
  errln' "Successfully opened output file"
  match read_elf64_file out with
  | .Fail e => return .Fail e
  | .Success eout =>
  errln' "Output file seems to be an ELF file"
  let a ← match all_abis.find? (fun a => a.is_valid_elf_header eout.elf64_file_header) with
    | some a => do
      errln' "Using GNU-extended ABI"
      pure (gnu_extend (tls_extend a))
    | none => pure (failwithI "output file does not conform to any known ABI")
  let linkable_items_and_options :=
    items_and_options.map (fun (it, opts) => linkable_item_of_input_item_and_options a it opts)
  let names := input_items.map string_of_triple
  let v ← match correctly_linked a linkable_items_and_options names link_options eout with
    | none => pure false
    | some img => do
      let our_output_filename := output_filename ++ ".test-out"
      let f := elf64_file_of_elf_memory_image a (fun x => x) our_output_filename img
      match bytes_of_elf64_file f with
      | .Fail s => outln' ("error writing output: " ++ s); pure true
      | .Success bytes =>
        match Byte_sequence_wrapper.serialise our_output_filename bytes with
        | .Success _ => pure true
        | .Fail s => outln' ("error writing output: " ++ s); pure true
  return .Success (Show.show0 v)

def main (args : List String) : IO UInt32 := do
  lemFailStop
  match ← mainLinkRes args with
  | .Fail err => errln' ("[!]: " ++ err)
  | .Success e => errln' e
  return 0
