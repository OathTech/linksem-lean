/-
Lean mirror of `src/uint64_wrapper.ml` (unbounded natural kept reduced,
same function names). Reduction is modulo `max_int` = 2^64 - 1, exactly as
upstream (an upstream bug our port cannot exercise, mirrored; findings F1).
`logxor` has no upstream counterpart: `elf64_xword_lxor`'s OCaml rep names
`Uint64_wrapper.logxor`, which upstream does not define (findings F3, never
reached); the Lean rep needs a definition to compile.
-/

namespace Uint64_wrapper

abbrev uint64 := Nat

/-- uint64_wrapper.ml `max_int` = 2^64 - 1, the modulus of every operation
    below (mirrored, F1). -/
def modulus : Nat := 2 ^ 64 - 1

def add (l r : uint64) : uint64 := (l + r) % modulus

/-- `Nat_big_num.modulus (sub l r) m` is Euclidean: never negative. -/
def minus (l r : uint64) : uint64 := ((l : Int) - r).emod modulus |>.toNat

def of_int (i : Nat) : uint64 := i % modulus

def shift_left (i : uint64) (s : Nat) : uint64 := (i <<< s) % modulus

def shift_right (i : uint64) (s : Nat) : uint64 := (i >>> s) % modulus

def logand (l r : uint64) : uint64 := (l &&& r) % modulus

def logor (l r : uint64) : uint64 := (l ||| r) % modulus

def logxor (l r : uint64) : uint64 := (l ^^^ r) % modulus

def to_string (l : uint64) : String := toString l

def to_int (u : uint64) : Nat := u

def equal (l r : uint64) : Bool := l == r

def of_oct (c1 c2 c3 c4 c5 c6 c7 c8 : UInt8) : uint64 :=
  c1.toNat + (c2.toNat <<< 8) + (c3.toNat <<< 16) + (c4.toNat <<< 24)
    + (c5.toNat <<< 32) + (c6.toNat <<< 40) + (c7.toNat <<< 48) + (c8.toNat <<< 56)

def to_bigint (u : uint64) : Nat := u

def of_bigint (u : Nat) : uint64 := u % modulus

/-- uint64_wrapper.ml `to_bytes`: least significant byte first. -/
def to_bytes (u : uint64) :
    UInt8 × UInt8 × UInt8 × UInt8 × UInt8 × UInt8 × UInt8 × UInt8 :=
  let b (k : Nat) : UInt8 := ((u >>> (8 * k)) &&& 0xff).toUInt8
  (b 0, b 1, b 2, b 3, b 4, b 5, b 6, b 7)

end Uint64_wrapper
