#include "../../include/picoruby_cyw43_ap.h"
#include "ap_dhcp_server.h"

#include <string.h>

#include "pico/cyw43_arch.h"
#include "lwip/netif.h"

#define PICORUBY_CYW43_AP_MAX_SSID_LEN 32
#define PICORUBY_CYW43_AP_MIN_PASSWORD_LEN 8
#define PICORUBY_CYW43_AP_MAX_PASSWORD_LEN 63

bool
picoruby_cyw43_ap_driver_initialized(void)
{
  return cyw43_is_initialized(&cyw43_state);
}

bool
picoruby_cyw43_ap_active(void)
{
  return picoruby_cyw43_ap_driver_initialized() &&
         (cyw43_state.itf_state & (1u << CYW43_ITF_AP)) != 0;
}

int
picoruby_cyw43_ap_default_auth(void)
{
  return CYW43_AUTH_WPA2_AES_PSK;
}

bool
picoruby_cyw43_ap_enable(const char *ssid, const char *password, uint32_t auth)
{
  size_t ssid_len = ssid ? strlen(ssid) : 0;
  size_t password_len = password ? strlen(password) : 0;

  if (!picoruby_cyw43_ap_driver_initialized() || picoruby_cyw43_ap_active()) {
    return false;
  }
  if (ssid_len == 0 || PICORUBY_CYW43_AP_MAX_SSID_LEN < ssid_len ||
      password_len < PICORUBY_CYW43_AP_MIN_PASSWORD_LEN ||
      PICORUBY_CYW43_AP_MAX_PASSWORD_LEN < password_len) {
    return false;
  }

  cyw43_arch_enable_ap_mode(ssid, password, auth);
  if (!picoruby_cyw43_ap_active() || !picoruby_cyw43_ap_dhcp_server_start()) {
    picoruby_cyw43_ap_dhcp_server_stop();
    if (picoruby_cyw43_ap_active()) {
      cyw43_arch_disable_ap_mode();
    }
    return false;
  }
  return true;
}

bool
picoruby_cyw43_ap_disable(void)
{
  bool was_active;

  if (!picoruby_cyw43_ap_driver_initialized()) {
    return false;
  }
  was_active = picoruby_cyw43_ap_active();
  picoruby_cyw43_ap_dhcp_server_stop();
  if (was_active) {
    cyw43_arch_disable_ap_mode();
  }
  return was_active;
}

void
picoruby_cyw43_ap_prepare_deinit(void)
{
  if (picoruby_cyw43_ap_driver_initialized()) {
    picoruby_cyw43_ap_disable();
  }
}

const char *
picoruby_cyw43_ap_ssid(char *buf, size_t buflen)
{
  size_t ssid_len = 0;
  const uint8_t *ssid = NULL;

  if (!picoruby_cyw43_ap_active() || buflen == 0) {
    return NULL;
  }
  cyw43_wifi_ap_get_ssid(&cyw43_state, &ssid_len, &ssid);
  if (!ssid || ssid_len == 0) {
    return NULL;
  }

  size_t copy_len = ssid_len < (buflen - 1) ? ssid_len : (buflen - 1);
  memcpy(buf, ssid, copy_len);
  buf[copy_len] = '\0';
  return buf;
}

static const char *
picoruby_cyw43_ap_ipv4_value(bool netmask, char *buf, size_t buflen)
{
  const char *result = NULL;

  if (!picoruby_cyw43_ap_active()) {
    return NULL;
  }

  cyw43_arch_lwip_begin();
  const ip4_addr_t *value = netmask
    ? netif_ip4_netmask(&cyw43_state.netif[CYW43_ITF_AP])
    : netif_ip4_addr(&cyw43_state.netif[CYW43_ITF_AP]);
  if (value && value->addr != 0) {
    result = ipaddr_ntoa_r(value, buf, buflen);
  }
  cyw43_arch_lwip_end();
  return result;
}

const char *
picoruby_cyw43_ap_ipv4_address(char *buf, size_t buflen)
{
  return picoruby_cyw43_ap_ipv4_value(false, buf, buflen);
}

const char *
picoruby_cyw43_ap_ipv4_netmask(char *buf, size_t buflen)
{
  return picoruby_cyw43_ap_ipv4_value(true, buf, buflen);
}
