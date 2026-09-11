require "cyw43"
require "cyw43/ap"
require "socket"

ssid = "PicoRuby-AP"
password = "12345678"

CYW43.init("JP")
unless CYW43::AP.enable(ssid, password)
  raise "failed to enable AP mode"
end

server = nil

begin
  address = CYW43::AP.ipv4_address
  raise "AP has no IPv4 address" unless address

  server = TCPServer.new("0.0.0.0", 80)
  puts "AP started: #{CYW43::AP.ssid}"
  puts "Open http://#{address}/"

  body = "Hello from PicoRuby AP mode\n"
  response = [
    "HTTP/1.1 200 OK",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Length: #{body.bytesize}",
    "Connection: close",
    "",
    body
  ].join("\r\n")

  loop do
    client = server.accept
    begin
      request_line = client.gets
      puts "Request: #{request_line.inspect}" if request_line
      client.write(response)
    rescue => e
      puts "HTTP error: #{e.class}: #{e.message}"
    ensure
      client.close
    end
  end
rescue RuntimeError => e
  # TCPServer#accept closes its server when Ctrl-C is received, then reports
  # the closed server on its next nonblocking accept attempt.
  raise unless e.message == "server is not initialized"
ensure
  begin
    server.close if server
  rescue
    # TCPServer#accept closes the server when it handles Ctrl-C.
  ensure
    CYW43::AP.disable
  end
end
