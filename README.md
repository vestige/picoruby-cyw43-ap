# picoruby-cyw43-ap

`picoruby-cyw43-ap` is a third-party PicoRuby mrbgem that adds a minimal,
DHCP-backed Wi-Fi access point to Raspberry Pi Pico W and Pico 2 W. It depends
on `picoruby-cyw43` and uses the public Pico SDK `cyw43_arch_enable_ap_mode()`
API and the public `cyw43_state` object. PicoRuby core does not need to be
patched.

This first milestone intentionally contains no HTTP server or socket lifecycle
code. It only owns AP start/stop, AP state and IPv4 inspection, and DHCP.

Compilation and linking have been verified for Pico 2 W with mruby/c, Pico 2 W
with mruby, and Pico W with mruby/c. Hardware validation of AP startup, DHCP
address assignment, shutdown, and re-enabling is still pending.

## Install in R2P2

Place this repository beside the PicoRuby repository and expose it to R2P2's
current CMake source discovery with an untracked symlink:

```sh
cd /path/to/picoruby
ln -s ../../picoruby-cyw43-ap mrbgems/picoruby-cyw43-ap
```

Add the gem to the desired R2P2 build configuration:

```ruby
conf.gem gemdir: "#{MRUBY_ROOT}/mrbgems/picoruby-cyw43-ap"
```

The mrbgem dependency loads `picoruby-cyw43` before this gem at build time.
FemtoRuby applications should still require both runtime components in order:

```ruby
require "cyw43"
require "cyw43/ap"
```

Example build commands supported by current PicoRuby build configurations are:

```sh
R2P2_NO_SHARED_ALLOC=1 rake r2p2:femtoruby:pico_w:prod
rake r2p2:femtoruby:pico2_w:prod
rake r2p2:picoruby:pico2_w:prod
```

The current full Pico W configuration can exceed RP2040 RAM at link time with
the default shared allocator size. `R2P2_NO_SHARED_ALLOC=1` selects the
supported low-memory configuration used for the verified Pico W build.

## Usage

```ruby
require "cyw43"
require "cyw43/ap"

CYW43.init("JP")
raise "AP start failed" unless CYW43::AP.enable("PicoRuby-AP", "12345678")

puts CYW43::AP.active?       # true
puts CYW43::AP.ssid          # PicoRuby-AP
puts CYW43::AP.ipv4_address  # 192.168.4.1 with the Pico SDK default setup
puts CYW43::AP.ipv4_netmask  # 255.255.255.0

CYW43::AP.disable
```

The password must contain 8 through 63 bytes and the SSID must contain 1
through 32 bytes. WPA2/AES PSK is the default authentication mode. An explicit
Pico SDK authentication value may be supplied as the third argument.

The DHCP server derives its network from the AP netif created by Pico SDK and
offers four addresses, host numbers 2 through 5. With the SDK default network,
these are `192.168.4.2` through `192.168.4.5`.

## API

- `CYW43::AP.enable(ssid, password, auth = WPA2_AES_PSK) -> bool`
- `CYW43::AP.disable -> bool`
- `CYW43::AP.active? -> bool`
- `CYW43::AP.ssid -> String | nil`
- `CYW43::AP.ipv4_address -> String | nil`
- `CYW43::AP.ipv4_netmask -> String | nil`

For migration from PicoRuby PR #489, the same methods are also available below
the isolated namespace as `enable_ap_mode`, `disable_ap_mode`, `ap_active?`,
`ap_ssid`, `ap_ipv4_address`, and `ap_ipv4_netmask`. Change `CYW43.` to
`CYW43::AP.` at the call site. The gem deliberately does not add methods to the
top-level `CYW43` class, preventing a future PicoRuby core API collision.

## Resource lifecycle

`CYW43::AP.disable` removes the DHCP UDP PCB and leases before disabling the AP
interface. The mruby gem finalizer performs the same cleanup. Both mruby and
mruby/c bindings wrap the existing private Ruby entry point used by
`CYW43.init(force: true)` and stop AP/DHCP before delegating to the original
core implementation.

Native applications that call Pico SDK deinitialization directly must call the
public gem C function `picoruby_cyw43_ap_prepare_deinit()` first. The gem does
not replace SDK symbols or depend on PicoRuby core's C wrapper internals.

## Scope and limitations

- Raspberry Pi Pico W and Pico 2 W only.
- One AP interface and one four-lease DHCP pool.
- No custom AP network, DNS, NAT, captive portal, HTTP server, or station-count API.
- STA behavior remains owned by `picoruby-cyw43` and is not modified.

## License and attribution

The gem is distributed under the MIT License; see [LICENSE](LICENSE).
`ports/rp2040/ap_dhcp_server.c` is adapted from TinyUSB networking helpers and
retains the MIT notice and copyright of Sergey Fetisov from PicoRuby PR #489.
