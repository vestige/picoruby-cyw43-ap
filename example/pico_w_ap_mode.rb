require "cyw43"
require "cyw43/ap"

CYW43.init("JP")
unless CYW43::AP.enable("PicoRuby-AP", "12345678")
  raise "failed to enable AP mode"
end

puts "AP started"
puts "AP active?: #{CYW43::AP.active?}"
puts "AP SSID: #{CYW43::AP.ssid || 'unknown'}"
puts "AP IP: #{CYW43::AP.ipv4_address || 'unassigned'}"
puts "AP netmask: #{CYW43::AP.ipv4_netmask || 'unassigned'}"

begin
  loop { sleep 1 }
ensure
  CYW43::AP.disable
end
