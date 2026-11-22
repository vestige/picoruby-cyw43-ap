#ifndef PICORUBY_CYW43_AP_H
#define PICORUBY_CYW43_AP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PICORUBY_CYW43_AP_MAC_LEN 6
#define PICORUBY_CYW43_AP_MAX_LEASES 4

typedef struct {
  uint8_t mac[PICORUBY_CYW43_AP_MAC_LEN];
  uint8_t ipv4_address[4];
  uint32_t remaining_seconds;
} picoruby_cyw43_ap_lease_t;

#ifdef __cplusplus
extern "C" {
#endif

bool picoruby_cyw43_ap_driver_initialized(void);
bool picoruby_cyw43_ap_enable(const char *ssid, const char *password, uint32_t auth);
bool picoruby_cyw43_ap_disable(void);
void picoruby_cyw43_ap_prepare_deinit(void);
bool picoruby_cyw43_ap_active(void);
const char *picoruby_cyw43_ap_ssid(char *buf, size_t buflen);
const char *picoruby_cyw43_ap_ipv4_address(char *buf, size_t buflen);
const char *picoruby_cyw43_ap_ipv4_netmask(char *buf, size_t buflen);
size_t picoruby_cyw43_ap_stations(
  uint8_t macs[][PICORUBY_CYW43_AP_MAC_LEN],
  size_t capacity
);
size_t picoruby_cyw43_ap_max_stations(void);
size_t picoruby_cyw43_ap_leases(picoruby_cyw43_ap_lease_t *leases, size_t capacity);
int picoruby_cyw43_ap_default_auth(void);

#ifdef __cplusplus
}
#endif

#endif /* PICORUBY_CYW43_AP_H */
