.globl helper
.globl table
.text
helper:
  mov value(%rip), %eax
  ret
.data
.align 8
table: .quad 7, helper, table
value: .long 5
.bss
.lcomm scratch, 64
