import Lake
open Lake DSL

package LinksemLean

-- LemLib, the Lean runtime of lem-lean's Lean backend, pinned to the SAME
-- commit as the `lem` that generates `generated/` (the two co-evolve: bump
-- both together). Offline/unpushed development: redirect this URL to a local
-- checkout with git's `url.<path>.insteadOf` (the linksem-lean container
-- does this in scripts/env.sh).
require LemLib from git "https://github.com/OathTech/lem-lean" @ "77ad4facfc60814a4a3f5d09dc88168ca208b285" / "lean-lib"

/-- The generated model modules. REWRITTEN by src/lem.mk `lean-extraction`
    between the markers; do not edit by hand. -/
def generatedModules : Array Lean.Name := #[
-- BEGIN generated module list
  `Abi_aarch64_dynamic,
  `Abi_aarch64_encodings_for_pkvm_alternatives,
  `Abi_aarch64_instruction_fields,
  `Abi_aarch64_le,
  `Abi_aarch64_le_elf_header,
  `Abi_aarch64_le_serialisation,
  `Abi_aarch64_program_header_table,
  `Abi_aarch64_relocation,
  `Abi_aarch64_section_header_table,
  `Abi_aarch64_symbol_table,
  `Abi_aarch64_symbolic_relocation,
  `Abi_amd64,
  `Abi_amd64_elf_header,
  `Abi_amd64_program_header_table,
  `Abi_amd64_relocation,
  `Abi_amd64_section_header_table,
  `Abi_amd64_serialisation,
  `Abi_amd64_symbol_table,
  `Abi_cheri_mips64,
  `Abi_cheri_mips64_capability,
  `Abi_cheri_mips64_dynamic,
  `Abi_cheri_mips64_elf_header,
  `Abi_cheri_mips64_relocation,
  `Abi_classes,
  `Abi_mips64,
  `Abi_mips64_dynamic,
  `Abi_mips64_elf_header,
  `Abi_mips64_program_header_table,
  `Abi_mips64_relocation,
  `Abi_mips64_section_header_table,
  `Abi_mips64_serialisation,
  `Abi_mips64_symbol_table,
  `Abi_power64,
  `Abi_power64_dynamic,
  `Abi_power64_elf_header,
  `Abi_power64_relocation,
  `Abi_power64_section_header_table,
  `Abi_riscv,
  `Abi_riscv_elf_header,
  `Abi_riscv_program_header_table,
  `Abi_riscv_relocation,
  `Abi_riscv_section_header_table,
  `Abi_riscv_serialisation,
  `Abi_riscv_symbol_table,
  `Abi_symbolic_relocation,
  `Abi_utilities,
  `Abi_x86_relocation,
  `Abis,
  `Abstract_linker_script,
  `Archive,
  `Auxv,
  `Byte_pattern,
  `Byte_pattern_extra,
  `Byte_sequence,
  `Byte_sequence_impl,
  `Command_line,
  `Default_printing,
  `Dump_image,
  `Dwarf,
  `Dwarf_byte_sequence,
  `Dwarf_ctypes,
  `Dwarf_expr_encode,
  `Elf64_file_of_elf_memory_image,
  `Elf_dynamic,
  `Elf_file,
  `Elf_header,
  `Elf_interpreted_section,
  `Elf_interpreted_segment,
  `Elf_memory_image,
  `Elf_memory_image_of_elf64_file,
  `Elf_note,
  `Elf_program_header_table,
  `Elf_relocation,
  `Elf_section_header_table,
  `Elf_symbol_table,
  `Elf_symbolic,
  `Elf_types_native_uint,
  `Endianness,
  `Error,
  `Filesystem,
  `Generated_arm64_cpucaps,
  `Gnu_ext_abi,
  `Gnu_ext_dynamic,
  `Gnu_ext_note,
  `Gnu_ext_program_header_table,
  `Gnu_ext_section_header_table,
  `Gnu_ext_section_to_segment_mapping,
  `Gnu_ext_symbol_versioning,
  `Gnu_ext_types_native_uint,
  `Harness_interface,
  `Hex_printing,
  `Input_list,
  `Ldconfig,
  `Link,
  `Linkable_list,
  `Linker_script,
  `Load,
  `Main_elf,
  `Main_link,
  `Memory_image,
  `Memory_image_orderings,
  `Missing_pervasives,
  `Multimap,
  `Pkvm_alternatives,
  `Pkvm_jump_table,
  `Pkvm_relocations,
  `Report_format,
  `Sail_interface,
  `Show,
  `String_table,
  `Sym,
  `Symbolic_resolution,
  `Test_image,
-- END generated module list
]

/-- Hand-written Lean twins of linksem's OCaml helpers (src/*.ml). -/
lean_lib Handwritten where
  srcDir := "handwritten"
  roots := #[`Ml_bindings, `Uint32_wrapper, `Uint64_wrapper,
             `Byte_sequence_wrapper, `Filesystem_wrapper, `Sym_ocaml]

/-- Build-time checks of the hand-written twins (building runs them). -/
@[default_target]
lean_lib HandwrittenTest where
  srcDir := "handwritten"
  roots := #[`HandwrittenTest]

/-- Every model module `lem -lean` produced (src/lem.mk `lean-extraction`),
    listed in `generatedModules` above. -/
@[default_target]
lean_lib Linksem where
  srcDir := "generated"
  roots := generatedModules

/-- The executable assertions of the model (`*_auxiliary.lean`); building
    them runs them. -/
lean_lib LinksemAux where
  srcDir := "generated"
  roots := generatedModules.map (·.appendAfter "_auxiliary")

/-- The Lean `main_elf`: I/O around the generated `Main_elf.main_elf_run`. -/
@[default_target]
lean_exe main_elf where
  srcDir := "driver"
  root := `MainElf

/-- The Lean `main_link`: I/O mirroring the OCaml-only driver of
    src/main_link.lem. -/
@[default_target]
lean_exe main_link where
  srcDir := "driver"
  root := `MainLink
