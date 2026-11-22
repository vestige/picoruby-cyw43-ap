#include <mrubyc.h>

#include <stdio.h>

static mrbc_func_t s_original_init;

static bool
require_initialized(mrbc_vm *vm)
{
  if (!picoruby_cyw43_ap_driver_initialized()) {
    mrbc_raise(vm, MRBC_CLASS(RuntimeError), "CYW43 not initialized");
    return false;
  }
  return true;
}

static void
c_cyw43_ap_enable(mrbc_vm *vm, mrbc_value *v, int argc)
{
  if (!require_initialized(vm)) {
    return;
  }
  if (argc < 2 || 3 < argc) {
    mrbc_raise(vm, MRBC_CLASS(ArgumentError), "wrong number of arguments");
    return;
  }
  if (GET_TT_ARG(1) != MRBC_TT_STRING || GET_TT_ARG(2) != MRBC_TT_STRING ||
      (argc == 3 && GET_TT_ARG(3) != MRBC_TT_INTEGER)) {
    mrbc_raise(vm, MRBC_CLASS(TypeError), "ssid and password must be strings and auth must be an integer");
    return;
  }

  const char *ssid = (const char *)GET_STRING_ARG(1);
  const char *password = (const char *)GET_STRING_ARG(2);
  int auth = argc == 3 ? GET_INT_ARG(3) : picoruby_cyw43_ap_default_auth();
  SET_BOOL_RETURN(picoruby_cyw43_ap_enable(ssid, password, (uint32_t)auth));
}

static void
c_cyw43_ap_disable(mrbc_vm *vm, mrbc_value *v, int argc)
{
  (void)argc;
  if (!require_initialized(vm)) {
    return;
  }
  SET_BOOL_RETURN(picoruby_cyw43_ap_disable());
}

static void
c_cyw43_ap_active_q(mrbc_vm *vm, mrbc_value *v, int argc)
{
  (void)vm;
  (void)argc;
  SET_BOOL_RETURN(picoruby_cyw43_ap_active());
}

static void
c_cyw43_ap_ssid(mrbc_vm *vm, mrbc_value *v, int argc)
{
  char ssid[33] = {0};

  (void)argc;
  if (!picoruby_cyw43_ap_ssid(ssid, sizeof(ssid))) {
    SET_NIL_RETURN();
    return;
  }
  SET_RETURN(mrbc_string_new_cstr(vm, ssid));
}

static void
c_cyw43_ap_ipv4_address(mrbc_vm *vm, mrbc_value *v, int argc)
{
  char address[16] = {0};

  (void)argc;
  if (!picoruby_cyw43_ap_ipv4_address(address, sizeof(address))) {
    SET_NIL_RETURN();
    return;
  }
  SET_RETURN(mrbc_string_new_cstr(vm, address));
}

static void
c_cyw43_ap_ipv4_netmask(mrbc_vm *vm, mrbc_value *v, int argc)
{
  char netmask[16] = {0};

  (void)argc;
  if (!picoruby_cyw43_ap_ipv4_netmask(netmask, sizeof(netmask))) {
    SET_NIL_RETURN();
    return;
  }
  SET_RETURN(mrbc_string_new_cstr(vm, netmask));
}

static void
format_mac_address(char *buf, size_t buflen, const uint8_t *mac)
{
  snprintf(
    buf, buflen, "%02x:%02x:%02x:%02x:%02x:%02x",
    mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
  );
}

static void
c_cyw43_ap_stations(mrbc_vm *vm, mrbc_value *v, int argc)
{
  size_t capacity = picoruby_cyw43_ap_max_stations();
  mrbc_value result = mrbc_array_new(vm, capacity);
  size_t count;

  (void)argc;
  if (capacity == 0) {
    SET_RETURN(result);
    return;
  }
  uint8_t macs[capacity][PICORUBY_CYW43_AP_MAC_LEN];
  count = picoruby_cyw43_ap_stations(macs, capacity);
  for (size_t i = 0; i < count; i++) {
    char mac_address[18];
    mrbc_value value;
    format_mac_address(mac_address, sizeof(mac_address), macs[i]);
    value = mrbc_string_new_cstr(vm, mac_address);
    mrbc_array_push(&result, &value);
  }
  SET_RETURN(result);
}

static void
c_cyw43_ap_client_count(mrbc_vm *vm, mrbc_value *v, int argc)
{
  size_t capacity = picoruby_cyw43_ap_max_stations();

  (void)vm;
  (void)argc;
  if (capacity == 0) {
    SET_INT_RETURN(0);
    return;
  }
  uint8_t macs[capacity][PICORUBY_CYW43_AP_MAC_LEN];
  SET_INT_RETURN(picoruby_cyw43_ap_stations(macs, capacity));
}

static void
c_cyw43_ap_leases(mrbc_vm *vm, mrbc_value *v, int argc)
{
  picoruby_cyw43_ap_lease_t leases[PICORUBY_CYW43_AP_MAX_LEASES];
  mrbc_value result = mrbc_array_new(vm, PICORUBY_CYW43_AP_MAX_LEASES);
  size_t count;

  (void)argc;
  count = picoruby_cyw43_ap_leases(leases, PICORUBY_CYW43_AP_MAX_LEASES);
  for (size_t i = 0; i < count; i++) {
    char mac_address[18];
    char ipv4_address[16];
    mrbc_value entry = mrbc_hash_new(vm, 3);
    mrbc_value key;
    mrbc_value value;

    format_mac_address(mac_address, sizeof(mac_address), leases[i].mac);
    snprintf(
      ipv4_address, sizeof(ipv4_address), "%u.%u.%u.%u",
      leases[i].ipv4_address[0], leases[i].ipv4_address[1],
      leases[i].ipv4_address[2], leases[i].ipv4_address[3]
    );
    key = mrbc_symbol_value(mrbc_str_to_symid("mac_address"));
    value = mrbc_string_new_cstr(vm, mac_address);
    mrbc_hash_set(&entry, &key, &value);
    key = mrbc_symbol_value(mrbc_str_to_symid("ipv4_address"));
    value = mrbc_string_new_cstr(vm, ipv4_address);
    mrbc_hash_set(&entry, &key, &value);
    key = mrbc_symbol_value(mrbc_str_to_symid("remaining_seconds"));
    value = mrbc_integer_value(leases[i].remaining_seconds);
    mrbc_hash_set(&entry, &key, &value);
    mrbc_array_push(&result, &entry);
  }
  SET_RETURN(result);
}

static void
c_cyw43_init_with_ap_cleanup(mrbc_vm *vm, mrbc_value *v, int argc)
{
  if (1 < argc && GET_TT_ARG(2) == MRBC_TT_TRUE) {
    picoruby_cyw43_ap_prepare_deinit();
  }
  if (!s_original_init) {
    mrbc_raise(vm, MRBC_CLASS(RuntimeError), "CYW43._init is unavailable");
    return;
  }
  s_original_init(vm, (struct RObject *)v, argc);
}

void
mrbc_cyw43_ap_init(mrbc_vm *vm)
{
  mrbc_class *class_cyw43 = mrbc_get_class_by_name("CYW43");
  mrbc_method init_method;

  if (!class_cyw43 ||
      mrbc_find_method(&init_method, class_cyw43, mrbc_str_to_symid("_init")) == 0 ||
      !init_method.c_func) {
    return;
  }

  s_original_init = init_method.func;
  mrbc_define_method(vm, class_cyw43, "_init", c_cyw43_init_with_ap_cleanup);

  mrbc_class *class_ap = mrbc_define_class_under(vm, class_cyw43, "AP", mrbc_class_object);
  mrbc_define_method(vm, class_ap, "enable", c_cyw43_ap_enable);
  mrbc_define_method(vm, class_ap, "disable", c_cyw43_ap_disable);
  mrbc_define_method(vm, class_ap, "active?", c_cyw43_ap_active_q);
  mrbc_define_method(vm, class_ap, "ssid", c_cyw43_ap_ssid);
  mrbc_define_method(vm, class_ap, "ipv4_address", c_cyw43_ap_ipv4_address);
  mrbc_define_method(vm, class_ap, "ipv4_netmask", c_cyw43_ap_ipv4_netmask);
  mrbc_define_method(vm, class_ap, "client_count", c_cyw43_ap_client_count);
  mrbc_define_method(vm, class_ap, "stations", c_cyw43_ap_stations);
  mrbc_define_method(vm, class_ap, "leases", c_cyw43_ap_leases);

  mrbc_define_method(vm, class_ap, "enable_ap_mode", c_cyw43_ap_enable);
  mrbc_define_method(vm, class_ap, "disable_ap_mode", c_cyw43_ap_disable);
  mrbc_define_method(vm, class_ap, "ap_active?", c_cyw43_ap_active_q);
  mrbc_define_method(vm, class_ap, "ap_ssid", c_cyw43_ap_ssid);
  mrbc_define_method(vm, class_ap, "ap_ipv4_address", c_cyw43_ap_ipv4_address);
  mrbc_define_method(vm, class_ap, "ap_ipv4_netmask", c_cyw43_ap_ipv4_netmask);
}
