int shared_counter;
int maybe_defined = 40;        /* strong definition overrides the weak one */
void bump(void) { shared_counter++; }
