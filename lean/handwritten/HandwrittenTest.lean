import Ml_bindings
import Uint32_wrapper
import Uint64_wrapper
import Byte_sequence_wrapper
import Filesystem_wrapper
import Sym_ocaml

/-!
Build-time checks of the hand-written Lean twins of linksem's OCaml helpers
(`#guard` evaluates at build: building `HandwrittenTest` runs them). The
expected values are the OCaml helpers' outputs on the `reloc-new-ps` base
(including where it is wrong and the port mirrors it: F6).
-/

section bytes
open Byte_sequence_wrapper
-- concat copies each window's bytes, in order (regression: the first
-- version copied from the accumulator)
#guard to_byte_list (concat [from_char_list [1, 2], empty, from_char_list [3]]) == [1, 2, 3]
#guard to_byte_list (concat [{ from_char_list [9, 1, 2, 9] with start := 1, len := 2 }, from_char_list [3]]) == [1, 2, 3]
-- F6 (upstream bug, mirrored): pads by bs.len - len with ASCII '0'
#guard to_byte_list (zero_pad_to_length 8 (from_char_list [1, 2, 3, 4])) == [1, 2, 3, 4]
#guard to_byte_list (zero_pad_to_length 2 (from_char_list [1, 2, 3, 4])) == [1, 2, 3, 4, 0x30, 0x30]
-- N1: the OCaml sign convention (bs2 - bs1): the shorter sequence is GREATER
#guard Byte_sequence_wrapper.compare (from_char_list [1]) (from_char_list [1, 2]) == LemOrdering.GT
#guard Byte_sequence_wrapper.compare (from_char_list [1, 3]) (from_char_list [1, 2]) == LemOrdering.LT
#guard Byte_sequence_wrapper.compare (from_char_list [1, 2]) (from_char_list [1, 2]) == LemOrdering.EQ
-- windows
#guard (match dropbytes 2 (from_char_list [1, 2, 3]) with
        | .Success r => to_byte_list r == [3] | .Fail _ => false)
#guard (match dropbytes 4 (from_char_list [1, 2, 3]) with
        | .Success _ => false | .Fail _ => true)
#guard find_byte (from_char_list [5, 6, 7]) 7 == some 2
end bytes

-- arithmetic modulo 2^N (F1, fixed on this branch)
#guard Uint32_wrapper.of_bigint 0xFFFFFFFF == 0xFFFFFFFF
#guard Uint32_wrapper.of_bigint 0x100000000 == 0
#guard Uint64_wrapper.minus 0 1 == 18446744073709551615
#guard Uint64_wrapper.shift_left (Uint64_wrapper.shift_left 1 63) 1 == 0
#guard Uint32_wrapper.of_quad 0x78 0x56 0x34 0x12 == 0x12345678
#guard Uint32_wrapper.to_bytes 0x12345678 == (0x78, 0x56, 0x34, 0x12)

-- hex rendering (F5, fixed on this branch), including values >= 2^63
#guard Ml_bindings.hex_string_of_big_int_pad16 0x7fffffffffffffff == "7fffffffffffffff"
#guard Ml_bindings.hex_string_of_big_int_pad16 18446744071562067968 == "ffffffff80000000"
#guard Ml_bindings.hex_string_of_big_int_pad2 0xabc == "abc"
#guard Ml_bindings.hex_string_of_big_int_no_padding (-26) == "-1a"
#guard Ml_bindings.hex_string_of_nat_pad2 7 == "07"

-- F2: the signed serialisers are an upstream gap (assert false), mirrored
#guard Ml_bindings.int32_of_quad 0xfe 0xff 0xff 0xff == -2

-- strings (OCaml Str / String semantics)
#guard Ml_bindings.split_string_on_char "\x00s\x00t" '\x00' == ["", "s", "t"]
#guard Ml_bindings.string_replace "a-b-c" "-" "+" == "a+b+c"
#guard Ml_bindings.string_replace "ab" "" "X" == "XaXbX"
#guard Ml_bindings.find_substring "lo" "hello" == some 3
#guard Ml_bindings.string_suffix 2 "hello" == some "llo"
#guard Ml_bindings.string_suffix 6 "hello" == none
#guard Ml_bindings.string_sub 1 3 "hello" == some "ell"
#guard Ml_bindings.string_sub 3 3 "hello" == none
#guard Ml_bindings.string_sub 5 0 "hello" == some ""
#guard Ml_bindings.string_index_of_from 'l' 3 "hello" == some 3
#guard Ml_bindings.string_index_of_from 'h' 1 "hello" == none
#guard Ml_bindings.string_index_of_from 'h' 6 "hello" == none
#guard Ml_bindings.string_of_unix_time 0 == "1970-01-01T00:00:00"
#guard Ml_bindings.string_of_unix_time 1700000000 == "2023-11-14T22:13:20"

-- filesystem path helpers (filesystem_wrapper.ml)
#guard Filesystem_wrapper.dirname "/usr/lib/libc.so" == "/usr/lib"
#guard Filesystem_wrapper.normalize "/usr/lib/../bin" == "/usr/bin"


-- audit item 9: Str.global_replace template semantics (OCaml outputs, probed)
#guard Ml_bindings.string_replace "aORbORc" "OR" "p\\\\q" == "ap\\qbp\\qc"
#guard Ml_bindings.string_replace "aORbORc" "OR" "p\\0q" == "apORqbpORqc"
#guard Ml_bindings.string_replace "aORbORc" "OR" "p\\qx" == "ap\\qxbp\\qxc"
#guard Ml_bindings.string_replace "aORbORc" "OR" "\\\\0" == "a\\0b\\0c"
#guard Ml_bindings.string_replace "nomatch" "OR" "p\\" == "nomatch"

-- symbolic numbers (sym_ocaml.ml)
section sym
open Sym_ocaml.Num
#guard to_string (add (section_ ".text" : natural) (of_num 4)) == ".text+4"
#guard to_string (section_ ".debug_info" : natural) == "0"
#guard to_string (sub (add (section_ ".text") (of_num 8) : integer) (section_ ".text")) == "8"
#guard to_string (modulus (add (section_ ".text") (of_num 7) : natural) (of_num 4)) == ".text+3"
#guard to_string (modulus (of_num (-7) : integer) (of_num 4)) == "1"
#guard compare_lexicographic (of_num 9 : natural) (section_ ".a") == LemOrdering.LT
#guard compare_lexicographic (add (section_ ".a") (of_num 9) : natural) (section_ ".b") == LemOrdering.LT
#guard Sym_ocaml.Num.compare (of_num 2 : natural) (of_num 3) == LemOrdering.LT
end sym
