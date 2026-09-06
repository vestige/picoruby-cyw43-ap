#include <mruby.h>
#include <mruby/class.h>
#include <mruby/string.h>

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
