(* OCaml side of the twin differential: evaluates each case of cases.txt
   (gen_cases.py) with the ORIGINAL helpers in src/*.ml and prints one
   canonical line per case: "ok <value>" or "exc <exception>". The Lean
   side (TwinProbe.lean) prints the same rendering for the Lean twins. *)
module N = Nat_big_num
let hex s = String.concat "" (List.map (fun c -> Printf.sprintf "%02x" (Char.code c)) (List.init (String.length s) (String.get s)))
let unhex h = String.init (String.length h / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2*i) 2)))
let arg pre a = let n = String.length pre in
  if String.length a >= n && String.sub a 0 n = pre then String.sub a n (String.length a - n)
  else failwith ("twin_probe: expected " ^ pre ^ " in " ^ a)
let nat a = N.of_string (arg "n:" a)
let int a = int_of_string (arg "n:" a)
let chr a = Char.chr (int_of_string (arg "c:" a))
let str a = unhex (arg "s:" a)
let bseq a =
  let v = arg "b:" a in
  let at = String.index v '@' in
  let bs = Byte_sequence_wrapper.from_char_list (List.of_seq (String.to_seq (unhex (String.sub v 0 at)))) in
  let k = int_of_string (String.sub v (at+1) (String.length v - at - 1)) in
  match Byte_sequence_wrapper.dropbytes k bs with
  | Error.Success b -> b | Error.Fail m -> failwith ("twin_probe: bad sequence " ^ m)
let rn = N.to_string
let rc c = string_of_int (Char.code c)
let rb b = if b then "true" else "false"
let rs s = hex s
let rbs b = hex (Byte_sequence_wrapper.to_string b)
let ropt f = function None -> "none" | Some x -> "some " ^ f x
let rerr f = function Error.Success x -> "ok:" ^ f x | Error.Fail m -> "fail:" ^ m
let tup l = "(" ^ String.concat "," l ^ ")"
let lst f l = "[" ^ String.concat ";" (List.map f l) ^ "]"
let sign i = string_of_int (compare i 0)

let eval f a = match f, a with
  | "u32.add", [x; y] -> rn (Uint32_wrapper.add (nat x) (nat y))
  | "u32.of_bigint", [x] -> rn (Uint32_wrapper.of_bigint (nat x))
  | "u32.shift_left", [x; s] -> rn (Uint32_wrapper.shift_left (nat x) (int s))
  | "u32.shift_right", [x; s] -> rn (Uint32_wrapper.shift_right (nat x) (int s))
  | "u32.logand", [x; y] -> rn (Uint32_wrapper.logand (nat x) (nat y))
  | "u32.logor", [x; y] -> rn (Uint32_wrapper.logor (nat x) (nat y))
  | "u32.to_bytes", [x] -> let (a,b,c,d) = Uint32_wrapper.to_bytes (nat x) in tup [rc a; rc b; rc c; rc d]
  | "u32.to_dual_bytes", [x] -> let (a,b) = Uint32_wrapper.to_dual_bytes (nat x) in tup [rc a; rc b]
  | "u32.of_quad", [a;b;c;d] -> rn (Uint32_wrapper.of_quad (chr a) (chr b) (chr c) (chr d))
  | "u32.uchar_of_bigint", [x] -> rn (Uint32_wrapper.uchar_of_bigint (nat x))
  | "u32.uchar_add", [x; y] -> rn (Uint32_wrapper.uchar_add (nat x) (nat y))
  | "u32.uchar_shift_left", [x; s] -> rn (Uint32_wrapper.uchar_shift_left (nat x) (int s))
  | "u64.add", [x; y] -> rn (Uint64_wrapper.add (nat x) (nat y))
  | "u64.minus", [x; y] -> rn (Uint64_wrapper.minus (nat x) (nat y))
  | "u64.shift_left", [x; s] -> rn (Uint64_wrapper.shift_left (nat x) (int s))
  | "u64.shift_right", [x; s] -> rn (Uint64_wrapper.shift_right (nat x) (int s))
  | "u64.logand", [x; y] -> rn (Uint64_wrapper.logand (nat x) (nat y))
  | "u64.logor", [x; y] -> rn (Uint64_wrapper.logor (nat x) (nat y))
  | "u64.logxor", [x; y] -> rn (Uint64_wrapper.logxor (nat x) (nat y))
  | "u64.of_bigint", [x] -> rn (Uint64_wrapper.of_bigint (nat x))
  | "u64.to_bytes", [x] -> let (a,b,c,d,e,f,g,h) = Uint64_wrapper.to_bytes (nat x) in tup (List.map rc [a;b;c;d;e;f;g;h])
  | "u64.of_oct", [a;b;c;d;e;f;g;h] -> rn (Uint64_wrapper.of_oct (chr a) (chr b) (chr c) (chr d) (chr e) (chr f) (chr g) (chr h))
  | "bs.length", [b] -> rn (Byte_sequence_wrapper.big_num_length (bseq b))
  | "bs.read_char", [b] -> rerr (fun (c, r) -> tup [rc c; rbs r]) (Byte_sequence_wrapper.read_char (bseq b))
  | "bs.find_byte", [b; c] -> ropt rn (Byte_sequence_wrapper.big_num_find_byte (bseq b) (chr c))
  | "bs.make", [n; c] -> rbs (Byte_sequence_wrapper.big_num_make (nat n) (chr c))
  | "bs.concat", bs -> rbs (Byte_sequence_wrapper.concat (List.map bseq bs))
  | "bs.zero_pad", [n; b] -> rbs (Byte_sequence_wrapper.big_num_zero_pad_to_length (nat n) (bseq b))
  | "bs.to_string", [b] -> rs (Byte_sequence_wrapper.to_string (bseq b))
  | "bs.compare", [x; y] -> sign (Byte_sequence_wrapper.compare (bseq x) (bseq y))
  | "bs.equal", [x; y] -> rb (Byte_sequence_wrapper.equal (bseq x) (bseq y))
  | "bs.dropbytes", [n; b] -> rerr rbs (Byte_sequence_wrapper.big_num_dropbytes (nat n) (bseq b))
  | "bs.takebytes", [n; b] -> rerr rbs (Byte_sequence_wrapper.big_num_takebytes (nat n) (bseq b))
  | "ml.string_of_unix_time", [t] -> Ml_bindings.string_of_unix_time (nat t)
  | "ml.hex_pad2", [x] -> Ml_bindings.hex_string_of_big_int_pad2 (nat x)
  | "ml.hex_pad4", [x] -> Ml_bindings.hex_string_of_big_int_pad4 (nat x)
  | "ml.hex_pad5", [x] -> Ml_bindings.hex_string_of_big_int_pad5 (nat x)
  | "ml.hex_pad6", [x] -> Ml_bindings.hex_string_of_big_int_pad6 (nat x)
  | "ml.hex_pad7", [x] -> Ml_bindings.hex_string_of_big_int_pad7 (nat x)
  | "ml.hex_pad8", [x] -> Ml_bindings.hex_string_of_big_int_pad8 (nat x)
  | "ml.hex_pad16", [x] -> Ml_bindings.hex_string_of_big_int_pad16 (nat x)
  | "ml.hex_no_padding", [x] -> Ml_bindings.hex_string_of_big_int_no_padding (nat x)
  | "ml.hex_nat_pad2", [x] -> Ml_bindings.hex_string_of_nat_pad2 (int x)
  | "ml.bytes_of_int32", [i] -> let (a,b,c,d) = Ml_bindings.bytes_of_int32 (Int32.of_string (arg "i:" i)) in tup (List.map rc [a;b;c;d])
  | "ml.bytes_of_int64", [i] -> let (a,b,c,d,e,f,g,h) = Ml_bindings.bytes_of_int64 (Int64.of_string (arg "i:" i)) in tup (List.map rc [a;b;c;d;e;f;g;h])
  | "ml.int32_of_quad", [a;b;c;d] -> Int32.to_string (Ml_bindings.int32_of_quad (chr a) (chr b) (chr c) (chr d))
  | "ml.int64_of_oct", [a;b;c;d;e;f;g;h] -> Int64.to_string (Ml_bindings.int64_of_oct (chr a) (chr b) (chr c) (chr d) (chr e) (chr f) (chr g) (chr h))
  | "ml.string_suffix", [n; s] -> ropt rs (Ml_bindings.string_suffix (nat n) (str s))
  | "ml.string_prefix", [n; s] -> ropt rs (Ml_bindings.string_prefix (nat n) (str s))
  | "ml.string_index_of", [c; s] -> ropt rn (Ml_bindings.string_index_of (chr c) (str s))
  | "ml.find_substring", [sub; s] -> ropt rn (Ml_bindings.find_substring (str sub) (str s))
  | "ml.split_string_on_char", [s; c] -> lst rs (Ml_bindings.split_string_on_char (str s) (chr c))
  | "ml.string_replace", [s; sub; r] -> rs (Ml_bindings.string_replace (str s) (str sub) (str r))
  | "ml.list_index_big_int", [n; l] ->
    let v = arg "l:" l in
    let xs = if v = "" then [] else List.map int_of_string (String.split_on_char ',' v) in
    ropt string_of_int (Ml_bindings.list_index_big_int (nat n) xs)
  | "fs.dirname", [p] -> rs (Filesystem_wrapper.dirname (str p))
  | "fs.normalize", [p] -> rs (Filesystem_wrapper.normalize (str p))
  | "fs.is_abs_path", [p] -> rb (Filesystem_wrapper.is_abs_path (str p))
  | "fs.to_absolute", [wd; p] -> rs (Filesystem_wrapper.to_absolute (str wd) (str p))
  | _ -> failwith ("twin_probe: unknown case " ^ f)

let () =
  try while true do
    let line = input_line stdin in
    match String.split_on_char '\t' line with
    | f :: a ->
      let r = try "ok " ^ eval f a with
        | Failure m when String.length m > 11 && String.sub m 0 11 = "twin_probe:" -> failwith m
        | e -> "exc " ^ Printexc.to_string e in
      print_endline r
    | [] -> ()
  done with End_of_file -> ()
