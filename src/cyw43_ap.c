#include <stdbool.h>
#include "../include/picoruby_cyw43_ap.h"

#if defined(PICORB_VM_MRUBY)

#include "mruby/cyw43_ap.c"

#elif defined(PICORB_VM_MRUBYC)

#include "mrubyc/cyw43_ap.c"

#endif
