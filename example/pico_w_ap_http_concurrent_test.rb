require "cyw43"
require "cyw43/ap"
require "socket"

HTTP_PORT = 80 unless Object.const_defined?(:HTTP_PORT)
HTTP_READ_CHUNK_SIZE = 512 unless Object.const_defined?(:HTTP_READ_CHUNK_SIZE)
HTTP_MAX_HEADER_SIZE = 4096 unless Object.const_defined?(:HTTP_MAX_HEADER_SIZE)
HTTP_REQUEST_TIMEOUT_MS = 5000 unless Object.const_defined?(:HTTP_REQUEST_TIMEOUT_MS)
HTTP_POLL_INTERVAL_MS = 10 unless Object.const_defined?(:HTTP_POLL_INTERVAL_MS)
HTTP_TOTAL_REQUEST_COUNT = 20 unless Object.const_defined?(:HTTP_TOTAL_REQUEST_COUNT)
HTTP_CONCURRENT_REQUEST_COUNT = 3 unless Object.const_defined?(:HTTP_CONCURRENT_REQUEST_COUNT)
HTTP_FETCH_TIMEOUT_MS = 10000 unless Object.const_defined?(:HTTP_FETCH_TIMEOUT_MS)

ssid = "PicoRuby-AP"
password = "12345678"

test_page = <<~HTML
  <!doctype html>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PicoRuby concurrent HTTP test</title>
  <button id="run">Run #{HTTP_TOTAL_REQUEST_COUNT} requests</button>
  <pre id="result">Ready</pre>
  <script>
    const totalCount = #{HTTP_TOTAL_REQUEST_COUNT};
    const concurrentCount = #{HTTP_CONCURRENT_REQUEST_COUNT};
    const fetchTimeoutMs = #{HTTP_FETCH_TIMEOUT_MS};
    const result = document.getElementById("result");
    async function request(index, stamp) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), fetchTimeoutMs);
      try {
        const response = await fetch(`/probe?id=${index}&stamp=${stamp}`, {
          cache: "no-store",
          signal: controller.signal
        });
        const body = await response.text();
        if (!response.ok || body !== `OK ${index}\\n`) {
          throw new Error(`${index}: ${response.status} ${JSON.stringify(body)}`);
        }
      } finally {
        clearTimeout(timeout);
      }
    }
    async function run() {
      document.getElementById("run").disabled = true;
      result.textContent = `Running 0/${totalCount} requests...`;
      const stamp = Date.now();
      const failures = [];
      let nextIndex = 0;
      let completedCount = 0;
      async function worker() {
        while (nextIndex < totalCount) {
          const index = nextIndex++;
          try {
            await request(index, stamp);
          } catch (error) {
            failures.push(`${index}: ${error}`);
          }
          completedCount += 1;
          result.textContent = `Running ${completedCount}/${totalCount} requests...`;
        }
      }
      await Promise.all(Array.from({length: concurrentCount}, worker));
      result.textContent = failures.length === 0
        ? `${totalCount}/${totalCount} passed`
        : `${totalCount - failures.length}/${totalCount} passed\\n` + failures.join("\\n");
      document.getElementById("run").disabled = false;
    }
    document.getElementById("run").addEventListener("click", run);
    run();
  </script>
HTML

def read_http_request(client)
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
  request
end

def http_response(content_type, body)
  [
    "HTTP/1.1 200 OK",
    "Content-Type: #{content_type}",
    "Content-Length: #{body.bytesize}",
    "Cache-Control: no-store",
    "Connection: close",
    "",
    body
  ].join("\r\n")
end

CYW43.init("JP")
raise "failed to enable AP mode" unless CYW43::AP.enable(ssid, password)

server = nil
probe_count = 0
probe_stamp = nil
connection_count = 0

begin
  address = CYW43::AP.ipv4_address
  raise "AP has no IPv4 address" unless address

  server = TCPServer.new("0.0.0.0", HTTP_PORT)
  puts "AP started: #{CYW43::AP.ssid}"
  puts "Open http://#{address}/"

  loop do
    puts "Waiting for connection"
    client = server.accept
    connection_count += 1
    puts "Connection #{connection_count}: accepted"
    begin
      puts "Connection #{connection_count}: request read start"
      request = read_http_request(client)
      puts "Connection #{connection_count}: request read complete"
      request_line = request.split("\r\n")[0]
      path = request_line.split(" ")[1]
      if path&.start_with?("/probe?")
        id = path.split("id=")[1]&.split("&")[0]
        stamp = path.split("stamp=")[1]&.split("&")[0]
        if stamp != probe_stamp
          probe_stamp = stamp
          probe_count = 0
        end
        body = "OK #{id}\n"
        response = http_response("text/plain; charset=utf-8", body)
        puts "Connection #{connection_count}: response write start"
        client.write(response)
        puts "Connection #{connection_count}: response write complete"
        probe_count += 1
        puts "Probe response: #{probe_count}/#{HTTP_TOTAL_REQUEST_COUNT} (run #{probe_stamp})"
      else
        response = http_response("text/html; charset=utf-8", test_page)
        puts "Connection #{connection_count}: response write start"
        client.write(response)
        puts "Connection #{connection_count}: response write complete"
        puts "Test page response: #{request_line.inspect}"
      end
    rescue => e
      puts "HTTP error: #{e.class}: #{e.message}"
    ensure
      puts "Connection #{connection_count}: close start"
      client.close
      puts "Connection #{connection_count}: close complete"
    end
  end
rescue Interrupt
  puts "Stopping HTTP server"
ensure
  begin
    server.close if server
  rescue
  ensure
    CYW43::AP.disable
    puts "AP active?: #{CYW43::AP.active?}"
  end
end
