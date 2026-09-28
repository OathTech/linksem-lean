/-
Lean mirror of `src/uint32_wrapper.ml`. Same representation as the OCaml
(an unbounded natural, kept reduced), same function names, so the Lem
`declare lean target_rep` lines read like their `ocaml` twins.

Reduction is modulo 2^32. The OCaml original reduced modulo 2^32 - 1
(`max_int`), which made 0xFFFFFFFF equal to 0; that is fixed on both sides
(record: lean/docs/2026-09-28_upstream-findings.md, F1).
-/

namespace Uint32_wrapper

abbrev uint32 := Nat

/-- 2^32: the modulus (uint32_wrapper.ml:4, fixed from 2^32 - 1). -/
def modulus : Nat := 2 ^ 32

def add (l r : uint32) : uint32 := (l + r) % modulus

/-- `of_int (Char.code c)` at the OCaml call sites; byte-sized input. -/
def of_int (i : Nat) : uint32 := i % modulus

def of_bigint (i : Nat) : uint32 := i % modulus

def to_bigint (u : uint32) : Nat := u

def shift_left (i : uint32) (s : Nat) : uint32 := (i <<< s) % modulus

def shift_right (i : uint32) (s : Nat) : uint32 := (i >>> s) % modulus

def logand (l r : uint32) : uint32 := (l &&& r) % modulus

def logor (l r : uint32) : uint32 := (l ||| r) % modulus

def to_string (l : uint32) : String := toString l

def to_int (u : uint32) : Nat := u

def equal (l r : uint32) : Bool := l == r

def of_quad (c1 c2 c3 c4 : UInt8) : uint32 :=
  c1.toNat + (c2.toNat <<< 8) + (c3.toNat <<< 16) + (c4.toNat <<< 24)

def of_dual (c1 c2 : UInt8) : uint32 := of_quad c1 c2 0 0

/-- uint32_wrapper.ml `to_bytes`: least significant byte first. -/
def to_bytes (u : uint32) : UInt8 × UInt8 × UInt8 × UInt8 :=
  ( (u &&& 0xff).toUInt8
  , ((u &&& 0xff00) >>> 8).toUInt8
  , ((u &&& 0xff0000) >>> 16).toUInt8
  , ((u &&& 0xff000000) >>> 24).toUInt8 )

/-- uint32_wrapper.ml `to_dual_bytes`: the two low bytes, LSB first. -/
def to_dual_bytes (u : uint32) : UInt8 × UInt8 :=
  let (b0, b1, _, _) := to_bytes u
  (b0, b1)

end Uint32_wrapper
