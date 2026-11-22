#ifndef PICORUBY_CYW43_AP_DHCP_SERVER_H
#define PICORUBY_CYW43_AP_DHCP_SERVER_H

#include <stdbool.h>
#include <stddef.h>

#include "../../include/picoruby_cyw43_ap.h"

bool picoruby_cyw43_ap_dhcp_server_start(void);
void picoruby_cyw43_ap_dhcp_server_stop(void);
size_t picoruby_cyw43_ap_dhcp_server_leases(
  picoruby_cyw43_ap_lease_t *leases,
  size_t capacity
);

#endif /* PICORUBY_CYW43_AP_DHCP_SERVER_H */
