#ifndef PICORUBY_CYW43_AP_H
#define PICORUBY_CYW43_AP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

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
int picoruby_cyw43_ap_default_auth(void);

#ifdef __cplusplus
}
#endif

#endif /* PICORUBY_CYW43_AP_H */
