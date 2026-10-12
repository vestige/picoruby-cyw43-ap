class PicoTimerHTTP
  READ_CHUNK_SIZE = 512
  MAX_HEADER_SIZE = 4096
  FIRST_BYTE_TIMEOUT_MS = 500
  REQUEST_TIMEOUT_MS = 5000
  POLL_INTERVAL_MS = 10
  RESPONSE_CHUNK_SIZE = 512

  def initialize(timer_state, status_led)
    @timer_state = timer_state
    @status_led = status_led
  end

  def handle_client(client)
    request = read_request(client)
    return unless request

    request_line = request.split("\r\n")[0]
    target = request_line.to_s.split(" ")[1] || "/"
    path = target.split("?")[0]

    case path
    when "/"
    when "/set"
      @timer_state.configure(target.split("seconds=")[1] || @timer_state.duration_seconds)
      @status_led.start
    when "/start"
      @timer_state.start
      @status_led.start
    when "/stop"
      @timer_state.stop
      @status_led.stop
    when "/reset"
      @timer_state.reset
      @status_led.stop
    else
      return write_response(client, "404 Not Found", "Not Found\n")
    end

    write_response(client, "200 OK", timer_page)
  end

  def timer_page
    state = @timer_state.running? ? "Running" : (@timer_state.expired? ? "Expired" : "Stopped")
    <<~HTML
      <!doctype html>
      <meta name="viewport" content="width=device-width,initial-scale=1">
      <title>PicoRuby Timer</title>
      <h1>PicoRuby Timer</h1>
      <p>Status: <strong>#{state}</strong></p>
      <p>Remaining: <strong>#{@timer_state.remaining_seconds} sec</strong></p>
      <form action="/set"><input name="seconds" type="number" min="1" max="#{@timer_state.max_seconds}" value="#{@timer_state.duration_seconds}"><button>Set</button></form>
      <p><a href="/start">Start</a> <a href="/stop">Stop</a> <a href="/reset">Reset</a></p>
      <p><a href="/">Refresh status</a></p>
      <p>AP: #{CYW43::AP.ssid} / #{CYW43::AP.ipv4_address}</p>
    HTML
  end

  def read_request(client)
    request = ""
    waited_ms = 0
    until request.include?("\r\n\r\n")
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

  def write_response(client, status, body)
    headers = [
      "HTTP/1.1 #{status}",
      "Content-Type: text/html; charset=utf-8",
      "Content-Length: #{body.bytesize}",
      "Cache-Control: no-store",
      "Connection: close",
      "",
      ""
    ].join("\r\n")
    client.write(headers)

    offset = 0
    while offset < body.bytesize
      chunk = body.byteslice(offset, RESPONSE_CHUNK_SIZE)
      client.write(chunk)
      offset += chunk.bytesize
    end
  end
end
