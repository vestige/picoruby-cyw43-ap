# picoruby-cyw43-ap

A third-party PicoRuby mrbgem providing a DHCP-backed Wi-Fi access point for
Raspberry Pi Pico W and Pico 2 W. It depends on `picoruby-cyw43` and uses public
Pico SDK interfaces; no PicoRuby core patch is required. The gem provides AP
and DHCP functionality, not an HTTP server.

[日本語版 README](README_ja.md)

## Install in R2P2

Place this repository beside the PicoRuby repository. In the PicoRuby checkout,
make it visible to R2P2's current CMake source discovery with an untracked
symlink:

```sh
cd /path/to/picoruby
ln -s ../../picoruby-cyw43-ap mrbgems/picoruby-cyw43-ap
```

Add the gem to the chosen R2P2 build configuration:

```ruby
conf.gem gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-cyw43-ap"
```

The mrbgem dependency loads `picoruby-cyw43` at build time. At runtime, require
both components in this order:

```ruby
require "cyw43"
require "cyw43/ap"
```

Example build commands:

```sh
R2P2_NO_SHARED_ALLOC=1 rake r2p2:femtoruby:pico_w:prod
rake r2p2:femtoruby:pico2_w:prod
rake r2p2:picoruby:pico2_w:prod
```

The Pico W full configuration may exceed RP2040 RAM with the default shared
allocator. The first command uses the low-memory configuration verified at
link time.

## Basic usage

```ruby
require "cyw43"
require "cyw43/ap"

CYW43.init("JP")
raise "AP start failed" unless CYW43::AP.enable("PicoRuby-AP", "12345678")

puts CYW43::AP.active?
puts CYW43::AP.ssid
puts CYW43::AP.ipv4_address
puts CYW43::AP.ipv4_netmask

CYW43::AP.disable
```

Use your own SSID and password. The password must be 8–63 bytes; the SSID must
be 1–32 bytes. WPA2/AES PSK is the default authentication mode; a Pico SDK
authentication value can be passed as the third argument. The DHCP server
offers four client addresses (host numbers 2–5). With the Pico SDK default
network, the AP is `192.168.4.1` and leases are `192.168.4.2`–`192.168.4.5`.

## Examples

- [Minimal HTTP server](example/pico_w_ap_http_server.rb): plain-text response
  to a browser connected to the AP.
- [AP Pico Timer](example/pico_w_ap_timer.rb): feasibility example with Set,
  Start, Stop, Reset, expiry, and manual status refresh.
- [Concurrent HTTP diagnostic](example/pico_w_ap_http_concurrent_test.rb):
  browser-driven request test, not a production server.

The HTTP examples also require `picoruby-socket` in the build configuration and
`require "socket"` at runtime. Their SSIDs and passwords are public sample
values; do not commit real credentials. Each example closes its sockets and
disables the AP when it exits. The Timer example's behavior and cleanup were
verified on Pico 2 W with mruby/c using a precompiled `.mrb`; Pico W and mruby
hardware behavior are not yet verified. The example's [host smoke test](example/pico_w_ap_timer_host_smoke.rb)
runs under CRuby and PicoRuby host.

## API

- `CYW43::AP.enable(ssid, password, auth = WPA2_AES_PSK) -> bool`
- `CYW43::AP.disable -> bool`
- `CYW43::AP.active? -> bool`
- `CYW43::AP.ssid -> String | nil`
- `CYW43::AP.ipv4_address -> String | nil`
- `CYW43::AP.ipv4_netmask -> String | nil`

For migration from PicoRuby PR #489, aliases under `CYW43::AP` are available:
`enable_ap_mode`, `disable_ap_mode`, `ap_active?`, `ap_ssid`,
`ap_ipv4_address`, and `ap_ipv4_netmask`. This gem adds no methods to the
top-level `CYW43` class.

## Validation and limitations

Compilation and linking were verified for Pico 2 W with mruby/c and mruby, and
Pico W with mruby/c. AP, DHCP, shutdown, re-enable, forced-init cleanup, and
STA-only regression were verified on Pico 2 W with mruby/c. Other board/VM
combinations have not been verified on hardware. Detailed test history and
follow-up socket/Core issues are in [TODO.md](TODO.md) and the linked Issues;
the HTTP examples are not part of the gem's AP/DHCP implementation.

The gem supports one AP interface and four DHCP leases. It does not provide a
custom AP network, DNS, NAT, captive portal, built-in HTTP server, or
station-count API. STA remains owned by `picoruby-cyw43`.

`CYW43::AP.disable` releases the DHCP UDP PCB and leases before disabling the
AP. The mruby finalizer and `CYW43.init(force: true)` cleanup path also stop
AP/DHCP. Native applications that deinitialize Pico SDK directly must call
`picoruby_cyw43_ap_prepare_deinit()` first.

## License and attribution

MIT License; see [LICENSE](LICENSE).
`ports/rp2040/ap_dhcp_server.c` is adapted from TinyUSB networking helpers
and retains Sergey Fetisov's copyright and MIT notice from PicoRuby PR #489.
