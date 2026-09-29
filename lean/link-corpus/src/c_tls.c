#include "exit.h"
__thread int tls_counter = 3;
void _start(void) { sys_exit(tls_counter); }
