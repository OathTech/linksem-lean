.globl _start
.text
_start:
  call helper
  movabs $table, %rbx
  mov (%rbx), %rdi
  add %rax, %rdi
  mov $60, %eax
  syscall
