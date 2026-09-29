#include "exit.h"
extern int counter;            /* the GLOBAL counter, defined in c_static_c.c */
extern int get_local(void);
void _start(void) { sys_exit(counter * 10 + get_local()); }
