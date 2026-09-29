#include "exit.h"
static const char *names[] = { "alpha", "beta", "gamma", "delta" };
static unsigned long hash(const char *s) { unsigned long h = 5381; while (*s) h = h * 33 + (unsigned char)*s++; return h; }
char big[4096];
void _start(void) {
  unsigned long h = 0;
  for (int i = 0; i < 4; i++) h ^= hash(names[i]);
  big[100] = (char)h;
  sys_exit(big[100] & 0x7f);
}
