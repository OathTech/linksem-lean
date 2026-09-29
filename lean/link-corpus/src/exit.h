/* freestanding exit(2) for x86-64 Linux: no libc in the link */
static inline void sys_exit(long code) {
  __asm__ volatile ("mov $60, %%eax\n\tsyscall" : : "D"(code) : "rax", "rcx", "r11", "memory");
  __builtin_unreachable();
}
