#include "exit.h"
extern int add(int, int);
extern int counter;
extern const char greeting[];
static int (*fp)(int, int) = add;
int zeroed[16];
void _start(void) {
  int s = fp(counter, 3) + greeting[0] + zeroed[3];
  sys_exit(s & 0x7f);
}
