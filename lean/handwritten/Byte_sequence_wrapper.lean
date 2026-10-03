import LemLib
import Error

/-
Lean mirror of `src/byte_sequence_wrapper.ml`: a byte sequence is a window
(`start`, `len`) onto a shared immutable buffer, so `dropbytes`/`takebytes`
are O(1) exactly as in the OCaml. Lem `byte` is `UInt8` (OCaml `char`).

`zero_pad_to_length` mirrors upstream, including its bug (findings F6: it
never pads a short sequence and appends ASCII '0' bytes to a long one;
nothing in the model calls it).
-/

namespace Byte_sequence_wrapper

structure byte_sequence where
  bytes : ByteArray
  start : Nat
  len : Nat

instance : Inhabited byte_sequence := ⟨⟨ByteArray.empty, 0, 0⟩⟩

/-! Lean `BEq`/`Ord` on the REPRESENTATION. Generated records holding a
    byte sequence derive `BEq, Ord` field-wise; in the OCaml they are
    compared by polymorphic `=`/`compare` on the record `{bytes; start; len}`,
    i.e. on the whole underlying buffer, then `start`, then `len`, not on the
    logical window (`compare`/`equal` below are the logical, model-visible
    ones). Mirrored: two windows with equal contents over different buffers
    are unequal here exactly as they are in OCaml (findings record, N2). -/

/-- OCaml's `compare` on `Bytes.t`: lexicographic by unsigned byte, a proper
    prefix first (caml_string_compare). -/
def compareBuffers (a b : ByteArray) : Ordering :=
  let n := min a.size b.size
  let rec go (i : Nat) (fuel : Nat) : Ordering :=
    match fuel with
    | 0 => compare a.size b.size
    | fuel + 1 =>
      match compare (a.get! i) (b.get! i) with
      | .eq => go (i + 1) fuel
      | o => o
  go 0 n

instance : Ord byte_sequence where
  compare x y := (compareBuffers x.bytes y.bytes).then
    ((compare x.start y.start).then (compare x.len y.len))

instance : BEq byte_sequence where
  beq x y := compareBuffers x.bytes y.bytes == .eq && x.start == y.start && x.len == y.len

def of_bytes (b : ByteArray) : byte_sequence := ⟨b, 0, b.size⟩

def length (bs : byte_sequence) : Nat := bs.len

def empty : byte_sequence := ⟨ByteArray.empty, 0, 0⟩

/-- In-bounds by the window invariant (`start + len ≤ bytes.size`); `get!`
    panics loudly if that were ever violated. -/
@[inline] def get (bs : byte_sequence) (i : Nat) : UInt8 := bs.bytes.get! (bs.start + i)

def read_char (bs : byte_sequence) : error (UInt8 × byte_sequence) :=
  if bs.len = 0 then Fail "read_char: sequence is empty"
  else Success (get bs 0, { bs with start := bs.start + 1, len := bs.len - 1 })

/-- byte_sequence_wrapper.ml `find_byte`: first index of `b` within the window. -/
def find_byte (bs : byte_sequence) (b : UInt8) : Option Nat :=
  let rec go (i : Nat) (fuel : Nat) : Option Nat :=
    match fuel with
    | 0 => none
    | fuel + 1 => if get bs i == b then some i else go (i + 1) fuel
  go 0 bs.len

/-- Written byte by byte into a buffer of the final size: building an
    `Array UInt8` first (boxed, 8 bytes per element) and converting it took
    about 10x the sequence's size at peak. -/
def make (len : Nat) (c : UInt8) : byte_sequence := Id.run do
  let mut b := ByteArray.emptyWithCapacity len
  for _ in [0:len] do b := b.push c
  return of_bytes b

/-- One buffer of the total size, each window copied into it in place
    (`exact := false`: no reallocation within the capacity). Appending with
    the default `exact := true` reallocated and copied the growing result
    for every piece; `bytes_of_elf64_file` on a 4 GiB file peaked at 46 GB. -/
def concat : List byte_sequence → byte_sequence
  | [] => empty
  | [bs] => bs
  | l =>
    let total := l.foldl (fun n bs => n + bs.len) 0
    of_bytes (l.foldl (fun acc bs => bs.bytes.copySlice bs.start acc acc.size bs.len false)
      (ByteArray.emptyWithCapacity total))

/-- byte_sequence_wrapper.ml `zero_pad_to_length`, mirrored as upstream
    has it (findings F6): `pad = bs.len - len`; when positive, `pad` ASCII
    '0' bytes are appended, otherwise the sequence is returned unchanged. -/
def zero_pad_to_length (len : Nat) (bs : byte_sequence) : byte_sequence :=
  if bs.len ≤ len then bs else concat [bs, make (bs.len - len) 0x30]

/-- Bytes as characters, one `Char` per byte (OCaml `Bytes.sub_string`). -/
def to_string (bs : byte_sequence) : String :=
  String.ofList ((List.range bs.len).map fun i => Char.ofNat (get bs i).toNat)

def to_char_list (bs : byte_sequence) : List Char :=
  (List.range bs.len).map fun i => Char.ofNat (get bs i).toNat

def to_byte_list (bs : byte_sequence) : List UInt8 :=
  (List.range bs.len).map fun i => get bs i

/-- Pushed into a buffer of the final size (no intermediate boxed array). -/
def from_char_list (l : List UInt8) : byte_sequence :=
  of_bytes (l.foldl (fun b c => b.push c) (ByteArray.emptyWithCapacity l.length))

/-- byte_sequence_wrapper.ml `compare`, sign convention included: the result
    is `bs2 - bs1` (by length, then by the first differing byte), so the
    order is the REVERSE of the obvious one. Mirrored deliberately; it is a
    consistent total order and only fixes iteration order of sets/maps
    keyed by byte sequences (findings record, N1). -/
def compare (bs1 bs2 : byte_sequence) : LemOrdering :=
  let sign (d : Int) : LemOrdering := if d < 0 then .LT else if d = 0 then .EQ else .GT
  if bs2.len ≠ bs1.len then sign ((bs2.len : Int) - bs1.len)
  else
    let rec go (i : Nat) (fuel : Nat) : LemOrdering :=
      match fuel with
      | 0 => .EQ
      | fuel + 1 =>
        let d : Int := (get bs2 i).toNat - (get bs1 i).toNat
        if d ≠ 0 then sign d else go (i + 1) fuel
    go 0 bs1.len

def equal (bs1 bs2 : byte_sequence) : Bool := compare bs1 bs2 == .EQ

def dropbytes (len : Nat) (bs : byte_sequence) : error byte_sequence :=
  if len > bs.len then
    Fail "dropbytes: cannot drop more bytes than are contained in sequence"
  else Success { bs with start := bs.start + len, len := bs.len - len }

def takebytes (len : Nat) (bs : byte_sequence) : error byte_sequence :=
  if len > bs.len then
    Fail "takebytes: cannot take more bytes than are contained in sequence"
  else Success { bs with len := len }

/-! Lem bindings (byte_sequence_wrapper.ml:143-162): the OCaml `big_num_*`
    variants convert between `Nat_big_num` and `int`; Lean has one `Nat`. -/

abbrev big_num_length := @length
abbrev big_num_find_byte := @find_byte
abbrev big_num_make := @make
abbrev big_num_zero_pad_to_length := @zero_pad_to_length
abbrev big_num_dropbytes := @dropbytes
abbrev big_num_takebytes := @takebytes

/-! File I/O from pure code (`acquire`/`serialise`), as the OCaml does.
    `acquire`'s result is always consumed, so it cannot be erased; an unused
    `serialise` result could be (the Lean driver checks it). -/

@[never_extract] private unsafe def acquireImpl (filename : String) : error byte_sequence :=
  match unsafeBaseIO (IO.FS.readBinFile filename |>.toBaseIO) with
  | .ok b => Success (of_bytes b)
  -- OCaml `open_in_bin` raises an uncaught Sys_error (program abort), it
  -- does not return `Fail`: mirrored as a loud panic.
  | .error e => failwithI s!"acquire: {e}"

@[never_extract] private unsafe def serialiseImpl (filename : String) (bs : byte_sequence) :
    error Unit :=
  let slice := bs.bytes.extract bs.start (bs.start + bs.len)
  match unsafeBaseIO (IO.FS.writeBinFile filename slice |>.toBaseIO) with
  | .ok () => Success ()
  | .error e => failwithI s!"serialise: {e}"

@[implemented_by acquireImpl, never_extract]
opaque acquire (filename : String) : error byte_sequence

@[implemented_by serialiseImpl, never_extract]
opaque serialise (filename : String) (bs : byte_sequence) : error Unit

end Byte_sequence_wrapper
