import LemLib

/-!
Lean twin of `src/sym_ocaml.ml` (`Sym_ocaml.Num`): a symbolic number is an
absolute value or an offset relative to a named section. The OCaml module
uses one type over `Nat_big_num.num` for both `sym_natural` and
`sym_integer`; here the type is parameterised by the number type (`Nat`
for `sym_natural`, `Int` for `sym_integer`), with the same operations, the
same failures ("Symbolic operation failed: ...") and the same messages.
Division and remainder are Lem's (`lemNatDiv`/`lemNatMod`,
`lemIntegerDiv`/`lemIntegerMod`: `Nat_big_num.div`/`modulus`).
`section` is a Lean keyword, so `Num.section` is `section_` here.
Where OCaml evaluates two operands right to left (`map2`, `modulus`), the
second is converted first, so a failure names the same operand.
-/

namespace Sym_ocaml.Num

/-- Constructor order as in OCaml, so the derived `BEq`/`Ord` are OCaml's
    polymorphic `=`/`compare` on `t` (which Lem's generated code uses for
    datatypes containing a symbolic number): `Offset` before `Absolute`,
    then the fields left to right. -/
inductive T (α : Type) where
  | Offset (s : String) (x : α)
  | Absolute (x : α)
  deriving BEq, Ord

instance {α : Type} [Inhabited α] : Inhabited (T α) := ⟨.Absolute default⟩

/-- The Lem types `sym_natural` and `sym_integer`. -/
abbrev natural := T Nat
abbrev integer := T Int

/-- Division and remainder as Lem's `Nat_big_num.div` / `modulus`. -/
class DivMod (α : Type) where
  div : α → α → α
  modulus : α → α → α
instance : DivMod Nat := ⟨lemNatDiv, lemNatMod⟩
instance : DivMod Int := ⟨lemIntegerDiv, lemIntegerMod⟩

def fail {β : Type} [Inhabited β] (s : String) : β :=
  failwithI ("Symbolic operation failed: " ++ s)

def ppf {α : Type} (p : α → String) : T α → String
  | .Absolute x => p x
  | .Offset s x => s ++ "+" ++ p x

def to_string {α : Type} [ToString α] (v : T α) : String := ppf toString v

def section_ {α : Type} [OfNat α 0] (s : String) : T α :=
  if s.startsWith ".debug" then .Absolute 0 else .Offset s 0

def of_num {α : Type} (x : α) : T α := .Absolute x

def offset_part {α : Type} : T α → α
  | .Absolute x => x
  | .Offset _ x => x

def to_num {α : Type} [Inhabited α] [ToString α] : T α → α
  | .Absolute x => x
  | v => fail ("to_num " ++ to_string v)

def add {α : Type} [Inhabited α] [ToString α] [Add α] (x y : T α) : T α :=
  match x, y with
  | .Absolute a, .Absolute b => .Absolute (a + b)
  | .Offset s a, .Absolute b => .Offset s (a + b)
  | .Absolute a, .Offset s b => .Offset s (a + b)
  | _, _ => fail ("add " ++ to_string x ++ " " ++ to_string y)

/-- `sub` (on `sym_integer`). -/
def sub {α : Type} [Inhabited α] [ToString α] [Sub α] (x y : T α) : T α :=
  match x, y with
  | .Absolute a, .Absolute b => .Absolute (a - b)
  | .Offset s a, .Absolute b => .Offset s (a - b)
  | .Offset s a, .Offset t b =>
    if s == t then .Absolute (a - b) else fail ("sub " ++ to_string x ++ " " ++ to_string y)
  | _, _ => fail ("sub " ++ to_string x ++ " " ++ to_string y)

/-- `sub_nat` (on `sym_natural`): `Nat_big_num.sub_nat` is truncated at 0, like `Nat` subtraction. -/
def sub_nat (x y : T Nat) : T Nat :=
  match x, y with
  | .Absolute a, .Absolute b => .Absolute (a - b)
  | .Offset s a, .Absolute b =>
    if a ≥ b then .Offset s (a - b) else fail ("sub_nat " ++ to_string x ++ " " ++ to_string y)
  | .Offset s a, .Offset t b =>
    if s == t then .Absolute (a - b) else fail ("sub_nat " ++ to_string x ++ " " ++ to_string y)
  | _, _ => fail ("sub_nat " ++ to_string x ++ " " ++ to_string y)

def map {α : Type} [Inhabited α] [ToString α] (f : α → α) (x : T α) : T α :=
  of_num (f (to_num x))

def map2 {α : Type} [Inhabited α] [ToString α] (f : α → α → α) (x y : T α) : T α :=
  let b := to_num y   -- OCaml evaluates the arguments of `f` right to left
  let a := to_num x
  of_num (f a b)

def mul {α : Type} [Inhabited α] [ToString α] [Mul α] (x y : T α) : T α := map2 (· * ·) x y
def div {α : Type} [Inhabited α] [ToString α] [DivMod α] (x y : T α) : T α := map2 DivMod.div x y

def modulus {α : Type} [Inhabited α] [ToString α] [DivMod α] (x y : T α) : T α :=
  let m := to_num y
  match x with
  | .Absolute a => .Absolute (DivMod.modulus a m)
  | .Offset s a => .Offset s (DivMod.modulus a m)

def comp {α β : Type} [Inhabited β] [ToString α] (f : α → α → β) (a b : T α) : β :=
  match a, b with
  | .Absolute x, .Absolute y => f x y
  | .Offset s x, .Offset t y =>
    if s == t then f x y else fail ("comp " ++ to_string a ++ " " ++ to_string b)
  | _, _ => fail ("comp " ++ to_string a ++ " " ++ to_string b)

def ordOf {α : Type} [Ord α] (x y : α) : LemOrdering :=
  match compare x y with
  | .lt => .LT
  | .eq => .EQ
  | .gt => .GT

def compare {α : Type} [ToString α] [Ord α] (a b : T α) : LemOrdering := comp ordOf a b
def less {α : Type} [ToString α] [Ord α] (a b : T α) : Bool := comp (fun x y => ordOf x y == .LT) a b
def greater {α : Type} [ToString α] [Ord α] (a b : T α) : Bool := comp (fun x y => ordOf x y == .GT) a b
def less_equal {α : Type} [ToString α] [Ord α] (a b : T α) : Bool := comp (fun x y => ordOf x y != .GT) a b
def greater_equal {α : Type} [ToString α] [Ord α] (a b : T α) : Bool := comp (fun x y => ordOf x y != .LT) a b
def equal {α : Type} [ToString α] [Ord α] (a b : T α) : Bool := comp (fun x y => ordOf x y == .EQ) a b

/-- Section name, then offset; absolute values sort first (OCaml `String.compare` is bytewise; these
    strings hold one character per byte, so character order is byte order). -/
def compare_lexicographic {α : Type} [Ord α] (a b : T α) : LemOrdering :=
  match a, b with
  | .Absolute x, .Absolute y => ordOf x y
  | .Absolute _, .Offset _ _ => .LT
  | .Offset _ _, .Absolute _ => .GT
  | .Offset s x, .Offset t y =>
    match ordOf s t with
    | .EQ => ordOf x y
    | c => c

def less_lexicographic {α : Type} [Ord α] (a b : T α) : Bool := compare_lexicographic a b == .LT
def greater_lexicographic {α : Type} [Ord α] (a b : T α) : Bool := compare_lexicographic a b == .GT

/-- `symIntegerFromNatural` (the identity on OCaml's shared representation). -/
def toInteger : T Nat → T Int
  | .Absolute x => .Absolute (Int.ofNat x)
  | .Offset s x => .Offset s (Int.ofNat x)

/-- `expect_nonneg`, as `partialSymNaturalFromInteger`: fails on a negative value, else the same value. -/
def expect_nonneg (x : T Int) : T Nat :=
  match x with
  | .Absolute a => if a ≥ 0 then .Absolute a.toNat else fail (to_string x ++ " can be negative")
  | .Offset s a => if a ≥ 0 then .Offset s a.toNat else fail (to_string x ++ " can be negative")

end Sym_ocaml.Num
