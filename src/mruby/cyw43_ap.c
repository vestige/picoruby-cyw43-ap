#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/hash.h>
#include <mruby/string.h>

#include <stdio.h>

static mrb_sym s_original_init;

static void
require_initialized(mrb_state *mrb)
{
  if (!picoruby_cyw43_ap_driver_initialized()) {
    mrb_raise(mrb, E_RUNTIME_ERROR, "CYW43 not initialized");
  }
}

static mrb_value
mrb_cyw43_ap_enable(mrb_state *mrb, mrb_value klass)
{
  const char *ssid;
  const char *password;
  mrb_int auth = picoruby_cyw43_ap_default_auth();

  (void)klass;
  require_initialized(mrb);
  mrb_get_args(mrb, "zz|i", &ssid, &password, &auth);
  return mrb_bool_value(picoruby_cyw43_ap_enable(ssid, password, (uint32_t)auth));
}

static mrb_value
mrb_cyw43_ap_disable(mrb_state *mrb, mrb_value klass)
{
  (void)klass;
  require_initialized(mrb);
  return mrb_bool_value(picoruby_cyw43_ap_disable());
}

static mrb_value
mrb_cyw43_ap_active_p(mrb_state *mrb, mrb_value klass)
{
  (void)mrb;
  (void)klass;
  return mrb_bool_value(picoruby_cyw43_ap_active());
}

static mrb_value
mrb_cyw43_ap_ssid(mrb_state *mrb, mrb_value klass)
{
  char ssid[33] = {0};

  (void)klass;
  if (!picoruby_cyw43_ap_ssid(ssid, sizeof(ssid))) {
    return mrb_nil_value();
  }
  return mrb_str_new_cstr(mrb, ssid);
}

static mrb_value
mrb_cyw43_ap_ipv4_address(mrb_state *mrb, mrb_value klass)
{
  char address[16] = {0};

  (void)klass;
  if (!picoruby_cyw43_ap_ipv4_address(address, sizeof(address))) {
    return mrb_nil_value();
  }
  return mrb_str_new_cstr(mrb, address);
}

static mrb_value
mrb_cyw43_ap_ipv4_netmask(mrb_state *mrb, mrb_value klass)
{
  char netmask[16] = {0};

  (void)klass;
  if (!picoruby_cyw43_ap_ipv4_netmask(netmask, sizeof(netmask))) {
    return mrb_nil_value();
  }
  return mrb_str_new_cstr(mrb, netmask);
}

static void
format_mac_address(char *buf, size_t buflen, const uint8_t *mac)
{
  snprintf(
    buf, buflen, "%02x:%02x:%02x:%02x:%02x:%02x",
    mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
  );
}

static mrb_value
mrb_cyw43_ap_stations(mrb_state *mrb, mrb_value klass)
{
  size_t capacity = picoruby_cyw43_ap_max_stations();
  size_t count;
  mrb_value result = mrb_ary_new_capa(mrb, capacity);

  (void)klass;
  if (capacity == 0) {
    return result;
  }
  uint8_t macs[capacity][PICORUBY_CYW43_AP_MAC_LEN];
  count = picoruby_cyw43_ap_stations(macs, capacity);
  for (size_t i = 0; i < count; i++) {
    char mac_address[18];
    format_mac_address(mac_address, sizeof(mac_address), macs[i]);
    mrb_ary_push(mrb, result, mrb_str_new_cstr(mrb, mac_address));
  }
  return result;
}

static mrb_value
mrb_cyw43_ap_client_count(mrb_state *mrb, mrb_value klass)
{
  size_t capacity = picoruby_cyw43_ap_max_stations();

  (void)mrb;
  (void)klass;
  if (capacity == 0) {
    return mrb_fixnum_value(0);
  }
  uint8_t macs[capacity][PICORUBY_CYW43_AP_MAC_LEN];
  return mrb_fixnum_value(picoruby_cyw43_ap_stations(macs, capacity));
}

static mrb_value
mrb_cyw43_ap_leases(mrb_state *mrb, mrb_value klass)
{
  picoruby_cyw43_ap_lease_t leases[PICORUBY_CYW43_AP_MAX_LEASES];
  size_t count;
  mrb_value result = mrb_ary_new_capa(mrb, PICORUBY_CYW43_AP_MAX_LEASES);

  (void)klass;
  count = picoruby_cyw43_ap_leases(leases, PICORUBY_CYW43_AP_MAX_LEASES);
  for (size_t i = 0; i < count; i++) {
    char mac_address[18];
    char ipv4_address[16];
    mrb_value entry = mrb_hash_new_capa(mrb, 3);

    format_mac_address(mac_address, sizeof(mac_address), leases[i].mac);
    snprintf(
      ipv4_address, sizeof(ipv4_address), "%u.%u.%u.%u",
      leases[i].ipv4_address[0], leases[i].ipv4_address[1],
      leases[i].ipv4_address[2], leases[i].ipv4_address[3]
    );
    mrb_hash_set(mrb, entry, mrb_symbol_value(mrb_intern_lit(mrb, "mac_address")),
                 mrb_str_new_cstr(mrb, mac_address));
    mrb_hash_set(mrb, entry, mrb_symbol_value(mrb_intern_lit(mrb, "ipv4_address")),
                 mrb_str_new_cstr(mrb, ipv4_address));
    mrb_hash_set(mrb, entry, mrb_symbol_value(mrb_intern_lit(mrb, "remaining_seconds")),
                 mrb_fixnum_value(leases[i].remaining_seconds));
    mrb_ary_push(mrb, result, entry);
  }
  return result;
}

static mrb_value
mrb_cyw43_init_with_ap_cleanup(mrb_state *mrb, mrb_value klass)
{
  mrb_value country;
  mrb_bool force;
  mrb_value argv[2];

  mrb_get_args(mrb, "ob", &country, &force);
  if (force) {
    picoruby_cyw43_ap_prepare_deinit();
  }
  argv[0] = country;
  argv[1] = mrb_bool_value(force);
  return mrb_funcall_argv(mrb, klass, s_original_init, 2, argv);
}

void
mrb_picoruby_cyw43_ap_gem_init(mrb_state *mrb)
{
  struct RClass *class_cyw43 = mrb_class_get(mrb, "CYW43");
  struct RClass *class_ap = mrb_define_class_under(mrb, class_cyw43, "AP", mrb->object_class);
  struct RClass *cyw43_singleton = mrb_class_ptr(mrb_singleton_class(mrb, mrb_obj_value(class_cyw43)));
  mrb_sym init = mrb_intern_lit(mrb, "_init");

  s_original_init = mrb_intern_lit(mrb, "__cyw43_ap_original_init");
  mrb_alias_method(mrb, cyw43_singleton, s_original_init, init);
  mrb_define_class_method(mrb, class_cyw43, "_init", mrb_cyw43_init_with_ap_cleanup, MRB_ARGS_REQ(2));

  mrb_define_class_method(mrb, class_ap, "enable", mrb_cyw43_ap_enable, MRB_ARGS_ARG(2, 1));
  mrb_define_class_method(mrb, class_ap, "disable", mrb_cyw43_ap_disable, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "active?", mrb_cyw43_ap_active_p, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "ssid", mrb_cyw43_ap_ssid, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "ipv4_address", mrb_cyw43_ap_ipv4_address, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "ipv4_netmask", mrb_cyw43_ap_ipv4_netmask, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "client_count", mrb_cyw43_ap_client_count, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "stations", mrb_cyw43_ap_stations, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "leases", mrb_cyw43_ap_leases, MRB_ARGS_NONE());

  mrb_define_class_method(mrb, class_ap, "enable_ap_mode", mrb_cyw43_ap_enable, MRB_ARGS_ARG(2, 1));
  mrb_define_class_method(mrb, class_ap, "disable_ap_mode", mrb_cyw43_ap_disable, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "ap_active?", mrb_cyw43_ap_active_p, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "ap_ssid", mrb_cyw43_ap_ssid, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "ap_ipv4_address", mrb_cyw43_ap_ipv4_address, MRB_ARGS_NONE());
  mrb_define_class_method(mrb, class_ap, "ap_ipv4_netmask", mrb_cyw43_ap_ipv4_netmask, MRB_ARGS_NONE());
}

void
mrb_picoruby_cyw43_ap_gem_final(mrb_state *mrb)
{
  (void)mrb;
  picoruby_cyw43_ap_prepare_deinit();
}
