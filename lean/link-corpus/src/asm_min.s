.globl _start
.text
_start:
  lea msg(%rip), %rsi
  mov $60, %eax
  mov counter(%rip), %edi
  syscall
.data
counter: .long 42
.section .rodata
msg: .asciz "hi"
