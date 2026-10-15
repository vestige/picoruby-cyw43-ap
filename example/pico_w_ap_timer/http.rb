class PicoTimerHTTP
  READ_CHUNK_SIZE = 512
  MAX_HEADER_SIZE = 4096
  FIRST_BYTE_TIMEOUT_MS = 500
  REQUEST_TIMEOUT_MS = 5000
  POLL_INTERVAL_MS = 10
  RESPONSE_CHUNK_SIZE = 512

  def initialize(timer_state, expiry_led, control, button_control = nil)
    @timer_state = timer_state
    @expiry_led = expiry_led
    @control = control
    @button_control = button_control
  end

  def handle_client(client)
    request = read_request(client)
    return unless request

    request_line = request.split("\r\n")[0]
    target = request_line.to_s.split(" ")[1] || "/"
    path = target.split("?")[0]

    case path
    when "/"
      return write_response(client, "200 OK", timer_page)
    when "/status"
      return write_response(client, "200 OK", status_json, "application/json; charset=utf-8")
    when "/set"
      @control.configure(target.split("seconds=")[1] || @timer_state.duration_seconds)
    when "/start"
      @control.start
    when "/stop"
      @control.stop
    when "/reset"
      @control.reset
    when "/ledoff"
      @control.led_off
    else
      return write_response(client, "404 Not Found", "Not Found\n")
    end

    write_response(client, "200 OK", timer_page)
  end

  def timer_page
    state = if @timer_state.running?
      "Running"
    elsif @timer_state.expired?
      "Expired"
    elsif @timer_state.paused?
      "Paused"
    else
      "Stopped"
    end
    start_label = if @timer_state.running?
      "Restart"
    elsif @timer_state.paused?
      "Resume"
    else
      "Start"
    end
    <<~HTML
      <!doctype html>
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>PicoRuby Timer</title>
      <h1>PicoRuby Timer</h1>
      <p id="connection">Connected</p>
      <p>Status: <strong id="status">#{state}</strong></p>
      <p>Remaining: <strong><span id="remaining">#{@timer_state.remaining_seconds}</span> sec</strong></p>
      <p>Expiry LED: <strong id="expiry-led">#{@expiry_led.on? ? "On" : "Off"}</strong></p>
      <form action="/set"><input name="seconds" type="number" min="1" max="#{@timer_state.max_seconds}" value="#{@timer_state.duration_seconds}"><button>Set</button></form>
      <p><a id="start" data-action href="/start">#{start_label}</a> <a data-action href="/stop">Stop</a> <a data-action href="/reset">Reset</a> <a data-action href="/ledoff">LED Off</a></p>
      <p>AP: #{CYW43::AP.ssid} / #{CYW43::AP.ipv4_address}</p>
      <script>
        (() => {
          const connection = document.getElementById("connection");
          const status = document.getElementById("status");
          const remaining = document.getElementById("remaining");
          const expiryLed = document.getElementById("expiry-led");
          const start = document.getElementById("start");
          const seconds = document.querySelector('[name="seconds"]');
          let syncing = false;
          let commanding = false;

          async function sync() {
            if (syncing || commanding) return;
            syncing = true;
            try {
              const response = await fetch("/status", { cache: "no-store" });
              if (!response.ok) throw new Error("HTTP " + response.status);
              const timer = await response.json();
              status.textContent = timer.status;
              remaining.textContent = timer.remaining_seconds;
              expiryLed.textContent = timer.expiry_led ? "On" : "Off";
              start.textContent = timer.start_label;
              if (document.activeElement !== seconds) seconds.value = timer.duration_seconds;
              connection.textContent = "Connected";
            } catch (_) {
              connection.textContent = "Disconnected - retrying";
            } finally {
              syncing = false;
            }
          }

          async function command(path) {
            if (commanding) return;
            commanding = true;
            try {
              await fetch(path, { cache: "no-store" });
            } finally {
              commanding = false;
              await sync();
            }
          }

          document.querySelectorAll("[data-action]").forEach(link => {
            link.addEventListener("click", event => {
              event.preventDefault();
              command(link.getAttribute("href"));
            });
          });
          document.querySelector("form").addEventListener("submit", event => {
            event.preventDefault();
            command("/set?seconds=" + encodeURIComponent(seconds.value));
          });
          setInterval(sync, 500);
          sync();
        })();
      </script>
    HTML
  end

  def status_json
    state = if @timer_state.running?
      "Running"
    elsif @timer_state.expired?
      "Expired"
    elsif @timer_state.paused?
      "Paused"
    else
      "Stopped"
    end
    start_label = if @timer_state.running?
      "Restart"
    elsif @timer_state.paused?
      "Resume"
    else
      "Start"
    end
    expiry_led = @expiry_led.on? ? "true" : "false"
    "{\"status\":\"#{state}\",\"remaining_seconds\":#{@timer_state.remaining_seconds}," \
      "\"duration_seconds\":#{@timer_state.duration_seconds},\"max_seconds\":#{@timer_state.max_seconds}," \
      "\"expiry_led\":#{expiry_led},\"start_label\":\"#{start_label}\"}"
  end

  def read_request(client)
    request = ""
    waited_ms = 0
    until request.include?("\r\n\r\n")
      @button_control.update if @button_control
      chunk = client.read_nonblock(READ_CHUNK_SIZE)
      if chunk
        request << chunk
        raise "HTTP request header too large" if MAX_HEADER_SIZE < request.bytesize
        waited_ms = 0
      else
        timeout_ms = request.empty? ? FIRST_BYTE_TIMEOUT_MS : REQUEST_TIMEOUT_MS
        if timeout_ms <= waited_ms
          return nil if request.empty?
          raise "HTTP request timeout"
        end
        sleep_ms(POLL_INTERVAL_MS)
        waited_ms += POLL_INTERVAL_MS
      end
    end
    request
  end

  def write_response(client, status, body, content_type = "text/html; charset=utf-8")
    headers = [
      "HTTP/1.1 #{status}",
      "Content-Type: #{content_type}",
      "Content-Length: #{body.bytesize}",
      "Cache-Control: no-store",
      "Connection: close",
      "",
      ""
    ].join("\r\n")
    @button_control.update if @button_control
    client.write(headers)

    offset = 0
    while offset < body.bytesize
      chunk = body.byteslice(offset, RESPONSE_CHUNK_SIZE)
      @button_control.update if @button_control
      client.write(chunk)
      offset += chunk.bytesize
    end
  end
end
