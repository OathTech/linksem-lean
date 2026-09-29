open Endianness
open Error

open Printf
open Unix

(* POSIX timestamp -> "%i-%i-%iT%02i:%02i:%02i" (UTC, proleptic Gregorian).
   Exact big-number calendar arithmetic (civil-from-days, H. Hinnant); the
   previous version went through Int64 -> float -> Unix.gmtime, which rounded
   above 2^53 and raised (Unix_error EINVAL / Failure int64_of_big_int) for
   large values. Identical output wherever gmtime was exact. Timestamps are
   naturals: all intermediate values are non-negative. *)
let string_of_unix_time (tm : Nat_big_num.num) =
  let open Nat_big_num in
  let n = of_int in
  let days = div tm (n 86400) and secs = to_int (modulus tm (n 86400)) in
  let z = add days (n 719468) in
  let era = div z (n 146097) in
  let doe = sub z (mul era (n 146097)) in
  let yoe = div (sub (add (sub doe (div doe (n 1460))) (div doe (n 36524))) (div doe (n 146096))) (n 365) in
  let y = add yoe (mul era (n 400)) in
  let doy = sub doe (sub (add (mul (n 365) yoe) (div yoe (n 4))) (div yoe (n 100))) in
  let mp = div (add (mul (n 5) doy) (n 2)) (n 153) in
  let d = add (sub doy (div (add (mul (n 153) mp) (n 2)) (n 5))) (n 1) in
  let m = if less mp (n 10) then add mp (n 3) else sub mp (n 9) in
  let y = if less_equal m (n 2) then add y (n 1) else y in
  Printf.sprintf "%s-%s-%sT%02i:%02i:%02i" (to_string y) (to_string m) (to_string d)
    (secs / 3600) (secs mod 3600 / 60) (secs mod 60)

let hex_string_of_nat_pad2 i : string =
  Printf.sprintf "%02i" i
;;

(* Hexadecimal rendering of a big number, lowercase, left-padded with zeros
   to [width] digits (a wider value is not truncated). Negative values
   print as their 64-bit two's complement, as the previous
   [Printf.sprintf "%0NLx" (Nat_big_num.to_int64 i)] did. That version
   raised [Failure "int64_of_big_int"] on any value >= 2^63 (e.g. every
   upper-half address); the output is unchanged wherever it used to
   succeed. *)
let hex_string_of_big_int_padded width i : string =
  let open Nat_big_num in
  let i = if less i zero then add i (pow_int_positive 2 64) else i in
  let sixteen = of_int 16 in
  let digit d = "0123456789abcdef".[to_int d] in
  let rec go n acc =
    if equal n zero then acc
    else go (div n sixteen) (digit (modulus n sixteen) :: acc) in
  let ds = if equal i zero then ['0'] else go i [] in
  let s = String.init (List.length ds) (List.nth ds) in
  if String.length s >= width then s
  else String.make (width - String.length s) '0' ^ s
;;

let hex_string_of_big_int_pad6 i : string = hex_string_of_big_int_padded 6 i
;;

let hex_string_of_big_int_pad7 i : string = hex_string_of_big_int_padded 7 i
;;

let hex_string_of_big_int_pad2 i : string = hex_string_of_big_int_padded 2 i
;;

let hex_string_of_big_int_pad4 i : string = hex_string_of_big_int_padded 4 i
;;

let hex_string_of_big_int_pad5 i : string = hex_string_of_big_int_padded 5 i
;;

let hex_string_of_big_int_pad8 i : string = hex_string_of_big_int_padded 8 i
;;

let hex_string_of_big_int_pad16 i : string = hex_string_of_big_int_padded 16 i
;;

let hex_string_of_big_int_no_padding i : string =
  if Nat_big_num.less i Nat_big_num.zero then
    "-" ^ hex_string_of_big_int_padded 0 (Nat_big_num.negate i)
  else
    hex_string_of_big_int_padded 0 i
;;

let bytes_of_int32 (i : Int32.t) = assert false
;;

let bytes_of_int64 (i : Int64.t) = assert false
;;

let int32_of_quad c1 c2 c3 c4 =
  let b1 = Int32.of_int (Char.code c1) in
  let b2 = Int32.shift_left (Int32.of_int (Char.code c2)) 8 in
  let b3 = Int32.shift_left (Int32.of_int (Char.code c3)) 16 in
  let b4 = Int32.shift_left (Int32.of_int (Char.code c4)) 24 in
    Int32.add b1 (Int32.add b2 (Int32.add b3 b4))
;;

let int64_of_oct c1 c2 c3 c4 c5 c6 c7 c8 =
  let b1 = Int64.of_int (Char.code c1) in
  let b2 = Int64.shift_left (Int64.of_int (Char.code c2)) 8 in
  let b3 = Int64.shift_left (Int64.of_int (Char.code c3)) 16 in
  let b4 = Int64.shift_left (Int64.of_int (Char.code c4)) 24 in
  let b5 = Int64.shift_left (Int64.of_int (Char.code c5)) 32 in
  let b6 = Int64.shift_left (Int64.of_int (Char.code c6)) 40 in
  let b7 = Int64.shift_left (Int64.of_int (Char.code c7)) 48 in
  let b8 = Int64.shift_left (Int64.of_int (Char.code c8)) 56 in
    Int64.add b1 (Int64.add b2 (Int64.add b3 (Int64.add b4
        (Int64.add b5 (Int64.add b6 (Int64.add b7 b8))))))
;;

let decimal_string_of_int64 e =
  let i = Int64.to_int e in
    string_of_int i
;;

let hex_string_of_int64 (e : Int64.t) : string =
  let i = Int64.to_int e in
    Printf.sprintf "0x%x" i
;;

let string_suffix index str =
  if (* index < 0 *) Nat_big_num.less index (Nat_big_num.of_int 0) ||
     (* index > length str *) (Nat_big_num.greater index (Nat_big_num.of_int (String.length str))) then
    None
  else
  	let idx = Nat_big_num.to_int index in
  		Some (String.sub str idx (String.length str - idx))
;;

let string_prefix index str =
  if (* index < 0 *) Nat_big_num.less index (Nat_big_num.of_int 0) ||
     (* index > length str *) (Nat_big_num.greater index (Nat_big_num.of_int (String.length str))) then
    None
  else
  	let idx = Nat_big_num.to_int index in
  		Some (String.sub str 0 idx)
;;

let string_index_of (c: char) (s : string) = try Some(Nat_big_num.of_int (String.index s c))
    with Not_found -> None
;;

let find_substring (sub: string) (s : string) =
    try Some(Nat_big_num.of_int (Str.search_forward (Str.regexp_string sub) s 0))
    with Not_found -> None
;;

let rec list_index_big_int index xs =
  match xs with
    | []    -> None
    | x::xs ->
      if Nat_big_num.equal index (Nat_big_num.of_int 0) then
        Some x
      else
        list_index_big_int (Nat_big_num.sub index (Nat_big_num.of_int 1)) xs
;;

let argv_list = Array.to_list Sys.argv
;;

let nat_big_num_of_uint64 x = x
(*
    (* Nat_big_num can only be made from signed integers at present.
     * Workaround: make an int64, and if negative, add the high bit
     * in the big-num domain. *)
    let via_int64 = Uint64.to_int64 x
    in
    if Int64.compare via_int64 Int64.zero >= 0 then Nat_big_num.of_int64 via_int64
    else
        let two_to_63 = Uint64.shift_left (Uint64.of_int 1) 63 in
        let lower_by_2_to_63 = Uint64.sub x two_to_63 in
        (Nat_big_num.add
            (Nat_big_num.of_int64 (Uint64.to_int64 lower_by_2_to_63))
            (Nat_big_num.shift_left (Nat_big_num.of_int 1) 63)
        )
*)

(* TODO: String.split_on_char is not available on old OCaml versions *)
(* let split_string_on_char s c = String.split_on_char c s *)
let split_string_on_char str c =
  if str = "" then []
  else
    let rec loop acc offset =
      try (
        let index = String.rindex_from str offset c in
        if index = offset then
          loop (""::acc) (index - 1)
        else
          let token = String.sub str (index + 1) (offset - index) in
          loop (token::acc) (index - 1)
      ) with Not_found -> (String.sub str 0 (offset + 1))::acc
    in
    loop [] (String.length str - 1)

let string_replace s substr repl =
  (* Why the hell do we need to use the whole regexp machinery for simple string
     replacements? *)
  let r = Str.regexp_string substr in
  Str.global_replace r repl s
