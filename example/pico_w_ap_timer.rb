require "cyw43"
require "cyw43/ap"
require "machine"
require "socket"

class PicoTimerState
  def initialize(default_seconds, max_seconds)
    @max_seconds = max_seconds
    @duration_seconds = default_seconds
    reset
  end

  def configure(value)
    seconds = value.to_i
    seconds = 1 if seconds < 1
    seconds = @max_seconds if @max_seconds < seconds
    @duration_seconds = seconds
    reset
  end

  def start
    update
    @remaining_ms = @duration_seconds * 1000 if @remaining_ms <= 0
    @deadline_ms = Machine.board_millis + @remaining_ms
    @running = true
    @expired = false
  end

  def stop
    update
    @remaining_ms = current_remaining_ms if @running
    @deadline_ms = nil
    @running = false
  end

  def reset
    @remaining_ms = @duration_seconds * 1000
    @deadline_ms = nil
    @running = false
    @expired = false
  end

  def update
    return unless @running
    return if 0 < current_remaining_ms

    @remaining_ms = 0
    @deadline_ms = nil
    @running = false
    @expired = true
  end

  def current_remaining_ms
    return @remaining_ms unless @running && @deadline_ms

    remaining = @deadline_ms - Machine.board_millis
    0 < remaining ? remaining : 0
  end

  def running?
    update
    @running
  end

  def expired?
    update
    @expired
  end

  def duration_seconds
    @duration_seconds
  end

  def remaining_seconds
    update
    milliseconds = @running ? current_remaining_ms : @remaining_ms
    (milliseconds + 999) / 1000
  end
end

module PicoTimerApp
  AP_SSID = "PicoRuby-Timer"
  AP_PASSWORD = "12345678"
  HTTP_PORT = 80
  HTTP_READ_CHUNK_SIZE = 512
  HTTP_MAX_HEADER_SIZE = 4096
  HTTP_FIRST_BYTE_TIMEOUT_MS = 500
  HTTP_REQUEST_TIMEOUT_MS = 5000
  HTTP_POLL_INTERVAL_MS = 10
  HTTP_RESPONSE_CHUNK_SIZE = 512
  SERVICE_LOOP_INTERVAL_MS = 10
  DEFAULT_SECONDS = 10
  MAX_SECONDS = 60 * 60

  TIMER_STATE = PicoTimerState.new(DEFAULT_SECONDS, MAX_SECONDS)

  class << self
    def configure_timer(value)
      TIMER_STATE.configure(value)
    end

    def start_timer
      TIMER_STATE.start
    end

    def stop_timer
      TIMER_STATE.stop
    end

    def reset_timer
      TIMER_STATE.reset
    end

    def update_timer
      TIMER_STATE.update
    end

    def current_remaining_ms
      TIMER_STATE.current_remaining_ms
    end

    def timer_running?
      TIMER_STATE.running?
    end

    def timer_expired?
      TIMER_STATE.expired?
    end

    def timer_duration_seconds
      TIMER_STATE.duration_seconds
    end

    def timer_remaining_seconds
      TIMER_STATE.remaining_seconds
    end

    def run
      puts "Pico Timer starting"
      Machine.signal_self_manage
      CYW43.init("JP")
      raise "failed to enable AP mode" unless CYW43::AP.enable(AP_SSID, AP_PASSWORD)

      server = nil
      begin
        address = CYW43::AP.ipv4_address
        raise "AP has no IPv4 address" unless address
        server = TCPServer.new("0.0.0.0", HTTP_PORT)
        puts "AP started: #{CYW43::AP.ssid}"
        puts "Open http://#{address}/"

        loop { service_once(server) }
      rescue Interrupt
        puts "Stopping Pico Timer"
      ensure
        begin
          server.close if server
        rescue
        ensure
          CYW43::AP.disable
          puts "AP active?: #{CYW43::AP.active?}"
        end
      end
    end

    def service_once(server)
      Machine.check_signal
      update_timer
      client = server.accept_nonblock
      unless client
        sleep_ms(SERVICE_LOOP_INTERVAL_MS)
        return false
      end

      begin
        handle_client(client)
      rescue => e
        puts "HTTP error: #{e.class}: #{e.message}"
      ensure
        client.close
      end
      true
    end

    def handle_client(client)
      request = read_http_request(client)
      return unless request

      request_line = request.split("\r\n")[0]
      target = request_line.to_s.split(" ")[1] || "/"
      path = target.split("?")[0]

      case path
      when "/"
      when "/set"
        configure_timer(target.split("seconds=")[1] || DEFAULT_SECONDS)
      when "/start"
        start_timer
      when "/stop"
        stop_timer
      when "/reset"
        reset_timer
      else
        return write_response(client, "404 Not Found", "Not Found\n")
      end

      write_response(client, "200 OK", timer_page)
    end

    def timer_page
      state = timer_running? ? "Running" : (timer_expired? ? "Expired" : "Stopped")
      <<~HTML
        <!doctype html>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>PicoRuby Timer</title>
        <h1>PicoRuby Timer</h1>
        <p>Status: <strong>#{state}</strong></p>
        <p>Remaining: <strong>#{timer_remaining_seconds} sec</strong></p>
        <form action="/set"><input name="seconds" type="number" min="1" max="#{MAX_SECONDS}" value="#{timer_duration_seconds}"><button>Set</button></form>
        <p><a href="/start">Start</a> <a href="/stop">Stop</a> <a href="/reset">Reset</a></p>
        <p><a href="/">Refresh status</a></p>
        <p>AP: #{CYW43::AP.ssid} / #{CYW43::AP.ipv4_address}</p>
      HTML
    end

    def read_http_request(client)
      request = ""
      waited_ms = 0
      until request.include?("\r\n\r\n")
        chunk = client.read_nonblock(HTTP_READ_CHUNK_SIZE)
        if chunk
          request << chunk
          raise "HTTP request header too large" if HTTP_MAX_HEADER_SIZE < request.bytesize
          waited_ms = 0
        else
          timeout_ms = request.empty? ? HTTP_FIRST_BYTE_TIMEOUT_MS : HTTP_REQUEST_TIMEOUT_MS
          if timeout_ms <= waited_ms
            return nil if request.empty?
            raise "HTTP request timeout"
          end
          sleep_ms(HTTP_POLL_INTERVAL_MS)
          waited_ms += HTTP_POLL_INTERVAL_MS
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
        chunk = body.byteslice(offset, HTTP_RESPONSE_CHUNK_SIZE)
        client.write(chunk)
        offset += chunk.bytesize
      end
    end
  end
end

PicoTimerApp.run
