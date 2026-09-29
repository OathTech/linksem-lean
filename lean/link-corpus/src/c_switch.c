#include "exit.h"
/* a dense switch: -O2 emits a jump table in .rodata */
__attribute__((noinline)) static int classify(int x) {
  switch (x) {
    case 0: return 11; case 1: return 7; case 2: return 5; case 3: return 3;
    case 4: return 2; case 5: return 13; case 6: return 17; case 7: return 19;
    default: return 1;
  }
}
static const char *const msgs[] = { "zero", "one", "two", "three" };   /* mergeable strings */
__attribute__((aligned(64))) int aligned_data[3] = { 1, 2, 3 };
char big_bss[1 << 20];
void _start(void) {
  int s = 0;
  for (int i = 0; i < 9; i++) s += classify(i);
  s += msgs[2][1] + aligned_data[2] + big_bss[12345];
  sys_exit(s & 0x7f);
}
