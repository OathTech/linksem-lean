import LemLib
import Error
import Ml_bindings

/-
Lean mirror of the parts of `src/filesystem_wrapper.ml` the Lem model
reaches (ldconfig.lem): `dirname`, `normalize`, `to_absolute`, `readdir`,
`file_exists`. `readlink`/`realpath_in`/`realpath` are used only by the
`main_load` driver; they get no Lean rep, so any Lean use is a generation-
time "unbound variable" error (fail-closed), not a silent stub.
-/

namespace Filesystem_wrapper

/-- filesystem_wrapper.ml:15: `pop_last` returns the list minus its last element. -/
private def dropLast' : List String → List String
  | [] => []
  | [_] => []
  | h :: t => h :: dropLast' t

def dirname (p : String) : String :=
  "/".intercalate (dropLast' (Ml_bindings.split_string_on_char p '/'))

/-- filesystem_wrapper.ml:37 `normalize'`: `s :: ".." :: t` drops both, and
    a leading empty component (absolute path) is kept only in first position. -/
private def normalize' : Bool → List String → List String
  | _, _ :: ".." :: t => normalize' false t
  | first, "" :: t =>
    let t := normalize' false t
    if first then "" :: t else t
  | _, s :: t => s :: normalize' false t
  | _, [] => []

def normalize (p : String) : String :=
  "/".intercalate (normalize' true (Ml_bindings.split_string_on_char p '/'))

/-- filesystem_wrapper.ml:34: `String.get p 0` raises on the empty string;
    mirrored as a loud panic. -/
def is_abs_path (p : String) : Bool :=
  match p.toList with
  | [] => failwithI "is_abs_path: index out of bounds"
  | c :: _ => c == '/'

def to_absolute (working_dir p : String) : String :=
  if is_abs_path p then normalize p else normalize (working_dir ++ "/" ++ p)

@[never_extract] private unsafe def readdirImpl (d : String) : error (List String) :=
  match unsafeBaseIO (System.FilePath.readDir d |>.toBaseIO) with
  | .ok entries => Success (entries.toList.map (·.fileName))
  | .error e => Fail ("readdir: " ++ toString e)

@[never_extract] private unsafe def fileExistsImpl (p : String) : Bool :=
  unsafeBaseIO (System.FilePath.pathExists p)

@[implemented_by readdirImpl, never_extract]
opaque readdir (d : String) : error (List String)

@[implemented_by fileExistsImpl, never_extract]
opaque file_exists (p : String) : Bool

end Filesystem_wrapper
