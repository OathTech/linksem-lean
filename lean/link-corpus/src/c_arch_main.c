#include "exit.h"
extern int used_fn(int);
void _start(void) { sys_exit(used_fn(21)); }
