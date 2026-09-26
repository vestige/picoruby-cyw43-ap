import network
import socket
import time


SSID = "MicroPython-AP"
PASSWORD = "12345678"
HTTP_PORT = 80
HTTP_READ_CHUNK_SIZE = 512
HTTP_MAX_HEADER_SIZE = 4096
HTTP_REQUEST_TIMEOUT_SECONDS = 5
HTTP_TOTAL_REQUEST_COUNT = 20
HTTP_CONCURRENT_REQUEST_COUNT = 3
HTTP_FETCH_TIMEOUT_MS = 10000


TEST_PAGE = """<!doctype html>
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>MicroPython concurrent HTTP test</title>
<button id="run">Run %d requests</button>
<pre id="result">Ready</pre>
<script>
const totalCount = %d;
const concurrentCount = %d;
const fetchTimeoutMs = %d;
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
""" % (
    HTTP_TOTAL_REQUEST_COUNT,
    HTTP_TOTAL_REQUEST_COUNT,
    HTTP_CONCURRENT_REQUEST_COUNT,
    HTTP_FETCH_TIMEOUT_MS,
)


def read_http_request(client):
    request = b""
    client.settimeout(HTTP_REQUEST_TIMEOUT_SECONDS)
    while b"\r\n\r\n" not in request:
        chunk = client.recv(HTTP_READ_CHUNK_SIZE)
        if not chunk:
            raise OSError("connection closed before HTTP header completed")
        request += chunk
        if len(request) > HTTP_MAX_HEADER_SIZE:
            raise OSError("HTTP request header too large")
    return request


def http_response(content_type, body):
    body_bytes = body.encode()
    header = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %d\r\n"
        "Cache-Control: no-store\r\n"
        "Connection: close\r\n"
        "\r\n"
    ) % (content_type, len(body_bytes))
    return header.encode() + body_bytes


ap = network.WLAN(network.WLAN.IF_AP)
server = None
connection_count = 0
probe_count = 0
probe_stamp = None

try:
    ap.config(ssid=SSID, key=PASSWORD)
    ap.active(True)
    while not ap.active():
        time.sleep_ms(10)

    address = ap.ifconfig()[0]
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", HTTP_PORT))
    server.listen(5)

    print("AP started:", SSID)
    print("Open http://%s/" % address)

    while True:
        print("Waiting for connection")
        client, remote = server.accept()
        connection_count += 1
        print("Connection %d: accepted from %s" % (connection_count, remote))
        try:
            print("Connection %d: request read start" % connection_count)
            request = read_http_request(client)
            print("Connection %d: request read complete" % connection_count)
            request_line = request.split(b"\r\n", 1)[0]
            parts = request_line.split(b" ")
            path = parts[1].decode() if len(parts) > 1 else "/"

            if path.startswith("/probe?"):
                query = path.split("?", 1)[1]
                params = {}
                for item in query.split("&"):
                    key, _, value = item.partition("=")
                    params[key] = value
                request_id = params.get("id", "")
                stamp = params.get("stamp", "")
                if stamp != probe_stamp:
                    probe_stamp = stamp
                    probe_count = 0
                response = http_response("text/plain; charset=utf-8", "OK %s\n" % request_id)
            else:
                response = http_response("text/html; charset=utf-8", TEST_PAGE)

            print("Connection %d: response write start" % connection_count)
            client.sendall(response)
            print("Connection %d: response write complete" % connection_count)

            if path.startswith("/probe?"):
                probe_count += 1
                print(
                    "Probe response: %d/%d (run %s)"
                    % (probe_count, HTTP_TOTAL_REQUEST_COUNT, probe_stamp)
                )
            else:
                print("Test page response:", request_line)
        except Exception as error:
            print("HTTP error:", type(error).__name__, error)
        finally:
            print("Connection %d: close start" % connection_count)
            client.close()
            print("Connection %d: close complete" % connection_count)
except KeyboardInterrupt:
    print("Stopping HTTP server")
finally:
    if server is not None:
        server.close()
    ap.active(False)
    print("AP active?:", ap.active())
