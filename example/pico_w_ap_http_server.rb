require "cyw43"
require "cyw43/ap"
require "socket"

HTTP_PORT = 80
HTTP_READ_CHUNK_SIZE = 512
HTTP_MAX_HEADER_SIZE = 4096
HTTP_REQUEST_TIMEOUT_MS = 5000
HTTP_POLL_INTERVAL_MS = 10

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

  server = TCPServer.new("0.0.0.0", HTTP_PORT)
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
      request = ""
      waited_ms = 0
      until request.include?("\r\n\r\n")
        chunk = client.read_nonblock(HTTP_READ_CHUNK_SIZE)
        if chunk
          request << chunk
          if HTTP_MAX_HEADER_SIZE < request.bytesize
            raise "HTTP request header too large"
          end
          waited_ms = 0
        else
          if HTTP_REQUEST_TIMEOUT_MS <= waited_ms
            raise "HTTP request timeout"
          end
          sleep_ms(HTTP_POLL_INTERVAL_MS)
          waited_ms += HTTP_POLL_INTERVAL_MS
        end
      end
      request_line = request.split("\r\n")[0]
      puts "Request: #{request_line.inspect}"
      client.write(response)
    rescue => e
      puts "HTTP error: #{e.class}: #{e.message}"
    ensure
      client.close
    end
  end
rescue Interrupt
  puts "Stopping HTTP server"
rescue RuntimeError => e
  # Compatibility with PicoRuby Core before picoruby/picoruby#509.
  raise unless e.message == "server is not initialized"
ensure
  begin
    server.close if server
  rescue
    # TCPServer#accept closes the server when it handles Ctrl-C.
  ensure
    CYW43::AP.disable
    puts "AP active?: #{CYW43::AP.active?}"
  end
end
