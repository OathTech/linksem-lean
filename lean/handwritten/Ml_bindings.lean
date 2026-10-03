import LemLib

/-
Lean mirror of `src/ml_bindings.ml`: the functions the Lem model reaches
through `declare lean target_rep`, same names as the OCaml. Strings are
Lean `String` (Unicode scalars) where OCaml has bytes: identical on ASCII,
which is all the model feeds these (LemLib limitation "strings are not yet
bytes").

The `hex_string_of_big_int_*` family follows this branch's `hex_of_big_int`
(repeated division: values >= 2^63 work; first-port finding F5, fixed
upstream).
-/

namespace Ml_bindings

/-! ## Hexadecimal rendering (ml_bindings.ml `hex_of_big_int` and its users) -/

private def hexDigits (n : Nat) : String := String.ofList (Nat.toDigits 16 n)

private def padZeros (w : Nat) (s : String) : String :=
  String.ofList (List.replicate (w - s.length) '0') ++ s

/-- `Printf.sprintf "%02i"`: DECIMAL despite the name (ml_bindings.ml:17). -/
def hex_string_of_nat_pad2 (i : Nat) : String := padZeros 2 (toString i)

def hex_string_of_big_int_pad2  (i : Nat) : String := padZeros 2 (hexDigits i)
def hex_string_of_big_int_pad4  (i : Nat) : String := padZeros 4 (hexDigits i)
def hex_string_of_big_int_pad5  (i : Nat) : String := padZeros 5 (hexDigits i)
def hex_string_of_big_int_pad6  (i : Nat) : String := padZeros 6 (hexDigits i)
def hex_string_of_big_int_pad7  (i : Nat) : String := padZeros 7 (hexDigits i)
def hex_string_of_big_int_pad8  (i : Nat) : String := padZeros 8 (hexDigits i)
def hex_string_of_big_int_pad16 (i : Nat) : String := padZeros 16 (hexDigits i)

/-- ml_bindings.ml:57: negative values print as `-` and the magnitude. -/
def hex_string_of_big_int_no_padding (i : Int) : String :=
  if i < 0 then "-" ++ hexDigits i.natAbs else hexDigits i.toNat

/-! ## Fixed-width signed words (ml_bindings.ml:67-95) -/

/-- ml_bindings.ml `bytes_of_int32` is `assert false` upstream (an upstream
    gap, findings F2): mirrored, it fails loudly [USER 2026-09-30: gaps are
    mirrored, not closed]. -/
def bytes_of_int32 (_ : Int32) : UInt8 × UInt8 × UInt8 × UInt8 :=
  failwithI "ml_bindings.ml bytes_of_int32: assert false (upstream gap, F2)"

/-- As `bytes_of_int32`: `assert false` upstream, mirrored. -/
def bytes_of_int64 (_ : Int64) :
    UInt8 × UInt8 × UInt8 × UInt8 × UInt8 × UInt8 × UInt8 × UInt8 :=
  failwithI "ml_bindings.ml bytes_of_int64: assert false (upstream gap, F2)"

/-- `Int32` arithmetic wraps, so this is the two's-complement reading of the
    four bytes, `c1` least significant. -/
def int32_of_quad (c1 c2 c3 c4 : UInt8) : Int32 :=
  (c1.toUInt32 ||| (c2.toUInt32 <<< 8) ||| (c3.toUInt32 <<< 16)
    ||| (c4.toUInt32 <<< 24)).toInt32

def int64_of_oct (c1 c2 c3 c4 c5 c6 c7 c8 : UInt8) : Int64 :=
  (c1.toUInt64 ||| (c2.toUInt64 <<< 8) ||| (c3.toUInt64 <<< 16)
    ||| (c4.toUInt64 <<< 24) ||| (c5.toUInt64 <<< 32) ||| (c6.toUInt64 <<< 40)
    ||| (c7.toUInt64 <<< 48) ||| (c8.toUInt64 <<< 56)).toInt64

/-! ## Strings (ml_bindings.ml:103-181) -/

/-- ml_bindings.ml:103: `None` iff `index > length str` (a natural is never
    negative). -/
def string_suffix (index : Nat) (str : String) : Option String :=
  if index > str.length then none else some (str.drop index).toString

def string_prefix (index : Nat) (str : String) : Option String :=
  if index > str.length then none else some (str.take index).toString

/-- Character index of the first `c` (`String.index` in OCaml). Native
    `String` operations, not `toList`: string tables are looked up once per
    symbol through `string_suffix`/`string_index_of`/`string_prefix`, and the
    list versions made `--symbols` on a 9k-symbol library take minutes. -/
def string_index_of (c : Char) (s : String) : Option Nat :=
  let p := s.find c
  if p == s.endPos then none else some (s.extract s.startPos p).length

/-- ml_bindings.ml `string_index_of_from`: the index of the first `c` at or
    after `i`; `None` if `i > length s` or there is none. -/
def string_index_of_from (c : Char) (i : Nat) (s : String) : Option Nat :=
  if i > s.length then none
  else (string_index_of c (s.drop i).toString).map (· + i)

/-- ml_bindings.ml `string_sub`: the `n` characters from `i`, or `None` if
    that range does not lie within `s`. -/
def string_sub (i n : Nat) (s : String) : Option String :=
  if i + n > s.length then none else some ((s.drop i).take n).toString

private def isPrefixOfList : List Char → List Char → Bool
  | [], _ => true
  | _, [] => false
  | a :: as, b :: bs => a == b && isPrefixOfList as bs

private def findSubList (sub : List Char) : List Char → Nat → Option Nat
  | [], i => if sub.isEmpty then some i else none
  | s@(_ :: rest), i => if isPrefixOfList sub s then some i else findSubList sub rest (i + 1)

/-- `Str.search_forward (Str.regexp_string sub) s 0`: first occurrence. -/
def find_substring (sub : String) (s : String) : Option Nat :=
  findSubList sub.toList s.toList 0

/-- The replacement TEMPLATE of `Str.global_replace`, expanded for one match
    (audit item 9; semantics probed on the OCaml side): `\\` is a
    backslash, `\0` the matched text, `\1`..`\9` raise (no groups in a
    `regexp_string`), a backslash before any other character is kept as
    is, a trailing backslash raises. OCaml only interprets the template when
    a match occurs; so does this. -/
private def expandReplTemplate (matched : List Char) : List Char → List Char
  | [] => []
  | ['\\'] => failwithI "Str.replace: illegal backslash sequence"
  | '\\' :: '\\' :: rest => '\\' :: expandReplTemplate matched rest
  | '\\' :: '0' :: rest => matched ++ expandReplTemplate matched rest
  | '\\' :: c :: rest =>
    if c.isDigit then failwithI "Str.replace: reference to unmatched group"
    else '\\' :: c :: expandReplTemplate matched rest
  | c :: rest => c :: expandReplTemplate matched rest

/-- `Str.global_replace (Str.regexp_string substr) repl s`: leftmost,
    non-overlapping, left to right. The empty pattern matches at every
    position (before each character and at the end), as Str does. The
    replacement is a template (`expandReplTemplate`). -/
def string_replace (s substr repl : String) : String :=
  let pat := substr.toList
  let r := fun () => expandReplTemplate pat repl.toList
  let rec go (fuel : Nat) (cs : List Char) (acc : List Char) : List Char :=
    match fuel with
    | 0 => acc.reverse ++ cs
    | fuel + 1 =>
      if pat.isEmpty then
        match cs with
        | [] => ((r ()).reverse ++ acc).reverse
        | c :: rest => go fuel rest (c :: (r ()).reverse ++ acc)
      else if isPrefixOfList pat cs then
        go fuel (cs.drop pat.length) ((r ()).reverse ++ acc)
      else
        match cs with
        | [] => acc.reverse
        | c :: rest => go fuel rest (c :: acc)
  -- Each step consumes at least one character, or ends (fuel is the bound).
  String.ofList (go (s.length + 1) s.toList [])

/-- ml_bindings.ml:163: `""` gives `[]`; otherwise every separator splits,
    empty tokens kept (`"\000s\000t"` gives `[""; "s"; "t"]`). -/
def split_string_on_char (str : String) (c : Char) : List String :=
  let rec go : List Char → List Char → List String
    | [], cur => [String.ofList cur.reverse]
    | x :: xs, cur => if x == c then String.ofList cur.reverse :: go xs [] else go xs (x :: cur)
  if str.isEmpty then [] else go str.toList []

example : split_string_on_char "\x00s\x00t" '\x00' = ["", "s", "t"] := by decide
example : split_string_on_char "a\x00" '\x00' = ["a", ""] := by decide
example : split_string_on_char "" '/' = [] := by decide

/-! ## Bytes and characters (OCaml `char` is a byte; Lem `byte` is `UInt8`) -/

/-- The `Char.chr` of the OCaml reps: raises `Invalid_argument` above 255,
    mirrored as a loud panic. -/
def char_chr (n : Nat) : UInt8 :=
  if n < 256 then n.toUInt8 else failwithI "Char.chr: Invalid_argument"

/-- `char_of_byte x = x` in OCaml: one character per byte value. -/
def char_of_byte (b : UInt8) : Char := Char.ofNat b.toNat

/-- `byte_of_char x = x` in OCaml. Every OCaml `char` is below 256; a Lean
    `Char` above 255 has no OCaml counterpart and panics loudly. -/
def byte_of_char (c : Char) : UInt8 := char_chr c.toNat

/-! ## Lists and numbers -/

/-- `Nat_big_num.to_string`: decimal, leading `-` when negative. -/
def string_of_integer (i : Int) : String := toString i

/-- `Int32.to_string` / `Int64.to_string`: signed decimal. -/
def int32_to_string (i : Int32) : String := toString i.toInt
def int64_to_string (i : Int64) : String := toString i.toInt

/-- `Nat_big_num.to_int64` raises outside the signed 64-bit range;
    mirrored as a loud panic. -/
def int64_of_integer (i : Int) : Int64 :=
  if -(2 ^ 63 : Int) ≤ i ∧ i < 2 ^ 63 then Int64.ofInt i
  else failwithI "Nat_big_num.to_int64: out of range"

def list_index_big_int {α : Type} : Nat → List α → Option α
  | _, [] => none
  | 0, x :: _ => some x
  | n + 1, _ :: xs => list_index_big_int n xs

def nat_big_num_of_uint64 (x : Nat) : Nat := x

/-- `Unix.gmtime` of a POSIX timestamp, printed `%i-%02i-%02iT%02i:%02i:%02i`
    (ml_bindings.ml:6). Civil-from-days after H. Hinnant; timestamps are
    naturals, so only the proleptic-Gregorian forward direction is needed. -/
def string_of_unix_time (tm : Nat) : String :=
  let days := tm / 86400
  let secs := tm % 86400
  let z : Int := days + 719468
  let era := z / 146097
  let doe := z - era * 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y := yoe + era * 400
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  let y := if m ≤ 2 then y + 1 else y
  let p2 (n : Nat) : String := padZeros 2 (toString n)
  s!"{y}-{p2 m.toNat}-{p2 d.toNat}T{p2 (secs / 3600)}:{p2 (secs % 3600 / 60)}:{p2 (secs % 60)}"

/-! ## Console output from pure code

The model calls these as `let _ = errln s in e`. OCaml performs the write;
Lean may erase an unused pure `let`, so these are best-effort DIAGNOSTICS
only: the differential compares stdout of the Lean driver (which does its
own output in `IO`) and never stderr. `never_extract` stops the compiler
from sharing or hoisting a call; it does not stop dead-code elimination. -/

/-- OCaml strings are bytes and its output functions write them raw. The
model's strings hold one character per byte (`Byte_sequence_wrapper.to_string`,
`char_of_byte`) and linksem has no non-ASCII string literals, so every
character is < 256 and is written as exactly that byte (`IO.print` would
UTF-8-encode bytes >= 0x80 into two). A character >= 256 has no OCaml
counterpart and fails loudly. -/
def bytesOfString (s : String) : ByteArray :=
  s.foldl (fun acc c =>
    if c.toNat < 256 then acc.push c.toNat.toUInt8
    else failwithI s!"output: character U+{c.toNat} has no byte (non-byte string)") .empty

/-- Write `s` (plus a newline if `nl`) byte-exactly and flush. -/
def writeString (h : IO.FS.Stream) (s : String) (nl : Bool) : IO Unit := do
  let b := bytesOfString s
  h.write (if nl then b.push 10 else b)
  h.flush

/-- A failed write fails loudly (OCaml raises `Sys_error`). -/
@[never_extract] private unsafe def writeImpl (err nl : Bool) (s : String) : Unit :=
  let act : IO Unit := do writeString (← if err then IO.getStderr else IO.getStdout) s nl
  match unsafeBaseIO act.toBaseIO with
  | Except.ok _ => ()
  | Except.error e => failwithI s!"console write: {e}"
@[never_extract] private unsafe def errlnImpl (s : String) : Unit := writeImpl true true s
@[never_extract] private unsafe def errsImpl (s : String) : Unit := writeImpl true false s
@[never_extract] private unsafe def outlnImpl (s : String) : Unit := writeImpl false true s
@[never_extract] private unsafe def outsImpl (s : String) : Unit := writeImpl false false s

@[implemented_by errlnImpl, never_extract] opaque errln (s : String) : Unit
@[implemented_by errsImpl, never_extract] opaque errs (s : String) : Unit
@[implemented_by outlnImpl, never_extract] opaque outln (s : String) : Unit
@[implemented_by outsImpl, never_extract] opaque outs (s : String) : Unit

end Ml_bindings
