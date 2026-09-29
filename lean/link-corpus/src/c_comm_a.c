#include "exit.h"
int shared_counter;            /* tentative definition: COMMON with -fcommon */
extern void bump(void);
void _start(void) { bump(); bump(); sys_exit(shared_counter + 7); }
