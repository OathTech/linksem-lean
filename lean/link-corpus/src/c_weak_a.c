#include "exit.h"
__attribute__((weak)) int maybe_defined = 1;
void _start(void) { sys_exit(maybe_defined); }
