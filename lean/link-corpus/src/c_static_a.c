static int counter = 5;        /* file-local: must never satisfy another file's reference */
int get_local(void) { return counter; }
