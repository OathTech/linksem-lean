#include "exit.h"
int shared_counter;            /* tentative definition: COMMON with -fcommon */
extern void bump(void);
__attribute__((weak)) int maybe_defined = 1;
void _start(void) { bump(); bump(); sys_exit(shared_counter + maybe_defined); }
