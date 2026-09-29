import Uint32_wrapper
import Uint64_wrapper
import Byte_sequence_wrapper
import Ml_bindings
import Filesystem_wrapper

/-!
Lean side of the twin differential (twins/twin_probe.ml is the OCaml side):
reads cases.txt (gen_cases.py) on stdin, evaluates each with the Lean twin
in lean/handwritten, prints the same canonical rendering as the OCaml probe
("ok <value>"). A failure inside the domain is not caught here: run.sh
evaluates the cases the OCaml side raises on one per process.
-/

open Byte_sequence_wrapper in
section
def hexOf (b : List UInt8) : String :=
  String.join (b.map fun x => let s := (Nat.toDigits 16 x.toNat).asString; if s.length < 2 then "0" ++ s else s)
def unhex (h : String) : List UInt8 :=
  let cs := h.toList
  let dig (c : Char) : Nat := if c.isDigit then c.toNat - 48 else c.toNat - 87
  (List.range (cs.length / 2)).map fun i => (dig cs[2*i]! * 16 + dig cs[2*i+1]!).toUInt8
def strip (pre a : String) : String :=
  if a.startsWith pre then (a.drop pre.length).toString else panic! s!"twin_probe: expected {pre} in {a}"
def nat (a : String) : Nat := (strip "n:" a).toNat!
def chr (a : String) : UInt8 := (strip "c:" a).toNat!.toUInt8
def strOf (bs : List UInt8) : String := String.mk (bs.map fun b => Char.ofNat b.toNat)
def str (a : String) : String := strOf (unhex (strip "s:" a))
def bseq (a : String) : byte_sequence :=
  let v := strip "b:" a
  match v.splitOn "@" with
  | [h, k] => match dropbytes k.toNat! (from_char_list (unhex h)) with
    | .Success b => b
    | .Fail m => panic! s!"twin_probe: bad sequence {m}"
  | _ => panic! "twin_probe: bad sequence"
def bytesOfStr (s : String) : List UInt8 := s.toList.map fun c => c.toNat.toUInt8
def rn (n : Nat) : String := toString n
def rc (c : UInt8) : String := toString c.toNat
def rb (b : Bool) : String := if b then "true" else "false"
def rs (s : String) : String := hexOf (bytesOfStr s)
def rbs (b : byte_sequence) : String := hexOf (to_byte_list b)
def ropt {α} (f : α → String) : Option α → String | none => "none" | some x => "some " ++ f x
def rerr {α} (f : α → String) : error α → String | .Success x => "ok:" ++ f x | .Fail m => "fail:" ++ m
def tup (l : List String) : String := "(" ++ ",".intercalate l ++ ")"
def lst {α} (f : α → String) (l : List α) : String := "[" ++ ";".intercalate (l.map f) ++ "]"
def ord : LemOrdering → String | .LT => "-1" | .EQ => "0" | .GT => "1"

def eval (f : String) (a : List String) : String :=
  match f, a with
  | "u32.add", [x, y] => rn (Uint32_wrapper.add (nat x) (nat y))
  | "u32.of_bigint", [x] => rn (Uint32_wrapper.of_bigint (nat x))
  | "u32.shift_left", [x, s] => rn (Uint32_wrapper.shift_left (nat x) (nat s))
  | "u32.shift_right", [x, s] => rn (Uint32_wrapper.shift_right (nat x) (nat s))
  | "u32.logand", [x, y] => rn (Uint32_wrapper.logand (nat x) (nat y))
  | "u32.logor", [x, y] => rn (Uint32_wrapper.logor (nat x) (nat y))
  | "u32.to_bytes", [x] => let (a, b, c, d) := Uint32_wrapper.to_bytes (nat x); tup [rc a, rc b, rc c, rc d]
  | "u32.to_dual_bytes", [x] => let (a, b) := Uint32_wrapper.to_dual_bytes (nat x); tup [rc a, rc b]
  | "u32.of_quad", [a, b, c, d] => rn (Uint32_wrapper.of_quad (chr a) (chr b) (chr c) (chr d))
  | "u32.uchar_of_bigint", [x] => rn (Uint32_wrapper.uchar_of_bigint (nat x))
  | "u32.uchar_add", [x, y] => rn (Uint32_wrapper.uchar_add (nat x) (nat y))
  | "u32.uchar_shift_left", [x, s] => rn (Uint32_wrapper.uchar_shift_left (nat x) (nat s))
  | "u64.add", [x, y] => rn (Uint64_wrapper.add (nat x) (nat y))
  | "u64.minus", [x, y] => rn (Uint64_wrapper.minus (nat x) (nat y))
  | "u64.shift_left", [x, s] => rn (Uint64_wrapper.shift_left (nat x) (nat s))
  | "u64.shift_right", [x, s] => rn (Uint64_wrapper.shift_right (nat x) (nat s))
  | "u64.logand", [x, y] => rn (Uint64_wrapper.logand (nat x) (nat y))
  | "u64.logor", [x, y] => rn (Uint64_wrapper.logor (nat x) (nat y))
  | "u64.logxor", [x, y] => rn (Uint64_wrapper.logxor (nat x) (nat y))
  | "u64.of_bigint", [x] => rn (Uint64_wrapper.of_bigint (nat x))
  | "u64.to_bytes", [x] => let (a, b, c, d, e, g, h, i) := Uint64_wrapper.to_bytes (nat x); tup ([a, b, c, d, e, g, h, i].map rc)
  | "u64.of_oct", [a, b, c, d, e, g, h, i] => rn (Uint64_wrapper.of_oct (chr a) (chr b) (chr c) (chr d) (chr e) (chr g) (chr h) (chr i))
  | "bs.length", [b] => rn (length (bseq b))
  | "bs.read_char", [b] => rerr (fun (c, r) => tup [rc c, rbs r]) (read_char (bseq b))
  | "bs.find_byte", [b, c] => ropt rn (find_byte (bseq b) (chr c))
  | "bs.make", [n, c] => rbs (make (nat n) (chr c))
  | "bs.concat", bs => rbs (concat (bs.map bseq))
  | "bs.zero_pad", [n, b] => rbs (zero_pad_to_length (nat n) (bseq b))
  | "bs.to_string", [b] => rs (to_string (bseq b))
  | "bs.compare", [x, y] => ord (compare (bseq x) (bseq y))
  | "bs.equal", [x, y] => rb (equal (bseq x) (bseq y))
  | "bs.dropbytes", [n, b] => rerr rbs (dropbytes (nat n) (bseq b))
  | "bs.takebytes", [n, b] => rerr rbs (takebytes (nat n) (bseq b))
  | "ml.string_of_unix_time", [t] => Ml_bindings.string_of_unix_time (nat t)
  | "ml.hex_pad2", [x] => Ml_bindings.hex_string_of_big_int_pad2 (nat x)
  | "ml.hex_pad4", [x] => Ml_bindings.hex_string_of_big_int_pad4 (nat x)
  | "ml.hex_pad5", [x] => Ml_bindings.hex_string_of_big_int_pad5 (nat x)
  | "ml.hex_pad6", [x] => Ml_bindings.hex_string_of_big_int_pad6 (nat x)
  | "ml.hex_pad7", [x] => Ml_bindings.hex_string_of_big_int_pad7 (nat x)
  | "ml.hex_pad8", [x] => Ml_bindings.hex_string_of_big_int_pad8 (nat x)
  | "ml.hex_pad16", [x] => Ml_bindings.hex_string_of_big_int_pad16 (nat x)
  | "ml.hex_no_padding", [x] => Ml_bindings.hex_string_of_big_int_no_padding (nat x)
  | "ml.hex_nat_pad2", [x] => Ml_bindings.hex_string_of_nat_pad2 (nat x)
  | "ml.bytes_of_int32", [i] => let (a, b, c, d) := Ml_bindings.bytes_of_int32 (Int32.ofInt (strip "i:" i).toInt!); tup ([a, b, c, d].map rc)
  | "ml.bytes_of_int64", [i] => let (a, b, c, d, e, g, h, j) := Ml_bindings.bytes_of_int64 (Int64.ofInt (strip "i:" i).toInt!); tup ([a, b, c, d, e, g, h, j].map rc)
  | "ml.int32_of_quad", [a, b, c, d] => toString (Ml_bindings.int32_of_quad (chr a) (chr b) (chr c) (chr d)).toInt
  | "ml.int64_of_oct", [a, b, c, d, e, g, h, i] => toString (Ml_bindings.int64_of_oct (chr a) (chr b) (chr c) (chr d) (chr e) (chr g) (chr h) (chr i)).toInt
  | "ml.string_suffix", [n, s] => ropt rs (Ml_bindings.string_suffix (nat n) (str s))
  | "ml.string_prefix", [n, s] => ropt rs (Ml_bindings.string_prefix (nat n) (str s))
  | "ml.string_index_of", [c, s] => ropt rn (Ml_bindings.string_index_of (Char.ofNat (chr c).toNat) (str s))
  | "ml.find_substring", [sub, s] => ropt rn (Ml_bindings.find_substring (str sub) (str s))
  | "ml.split_string_on_char", [s, c] => lst rs (Ml_bindings.split_string_on_char (str s) (Char.ofNat (chr c).toNat))
  | "ml.string_replace", [s, sub, r] => rs (Ml_bindings.string_replace (str s) (str sub) (str r))
  | "ml.list_index_big_int", [n, l] =>
    let v := strip "l:" l
    let xs : List Nat := if v.isEmpty then [] else (v.splitOn ",").map String.toNat!
    ropt rn (Ml_bindings.list_index_big_int (nat n) xs)
  | "fs.dirname", [p] => rs (Filesystem_wrapper.dirname (str p))
  | "fs.normalize", [p] => rs (Filesystem_wrapper.normalize (str p))
  | "fs.is_abs_path", [p] => rb (Filesystem_wrapper.is_abs_path (str p))
  | "fs.to_absolute", [wd, p] => rs (Filesystem_wrapper.to_absolute (str wd) (str p))
  | _, _ => panic! s!"twin_probe: unknown case {f}"
end

partial def loop (h : IO.FS.Stream) : IO Unit := do
  let line ← h.getLine
  if line.isEmpty then return
  let line := line.trimRight
  match line.splitOn "\t" with
  | f :: a => IO.println ("ok " ++ eval f a)
  | [] => pure ()
  loop h

def main : IO Unit := do
  lemFailStop
  loop (← IO.getStdin)
