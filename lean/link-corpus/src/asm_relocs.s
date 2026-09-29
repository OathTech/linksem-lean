# One use of each common x86-64 static-link relocation; _start exits with
# a checksum of values read through them (ld's executable is the oracle).
.globl _start
.text
_start:
  xor %ebx, %ebx
  mov $v32, %eax            # R_X86_64_32
  add (%rax), %ebx
  mov v32s, %ecx            # R_X86_64_32S (absolute, sign-extended)
  add %ecx, %ebx
  movabs $v64, %rax         # R_X86_64_64
  add (%rax), %ebx
  mov vpc(%rip), %eax       # R_X86_64_PC32
  add %eax, %ebx
  mov gotv@GOTPCREL(%rip), %rax   # R_X86_64_GOTPCREL
  add (%rax), %ebx
  lea pc64tab(%rip), %rax   # PC64: tab holds (target - &entry)
  mov (%rax), %rdx
  add %rax, %rdx
  add (%rdx), %ebx
  call fn                   # R_X86_64_PLT32 (static: direct)
  add %eax, %ebx
  lea ptrs(%rip), %rax      # R_X86_64_64 in .data
  mov 8(%rax), %rax
  add (%rax), %ebx
  mov %ebx, %edi
  and $0x7f, %edi
  mov $60, %eax
  syscall
fn:
  mov $3, %eax
  ret
.data
.align 8
v32:  .long 1
v32s: .long 2
v64:  .long 4
vpc:  .long 8
gotv: .long 16
ptrs: .quad v32, gotv
pc64tab: .quad pcv - pc64tab    # R_X86_64_PC64 when pcv is in another section
.section .rodata
.align 8
pcv:  .long 32               # in another section: pc64tab needs R_X86_64_PC64
