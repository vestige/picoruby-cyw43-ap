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
    start
  end

  def start
    @remaining_ms = @duration_seconds * 1000
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

class PicoTimerStatusLED
  def initialize(gpio, blink_interval_ms)
    @gpio = gpio
    @blink_interval_ms = blink_interval_ms
    @on = false
    @last_toggle_ms = Machine.board_millis
    @gpio.write(0)
  end

  def start
    @on = true
    @last_toggle_ms = Machine.board_millis
    @gpio.write(1)
  end

  def stop
    return unless @on

    @on = false
    @gpio.write(0)
  end

  def update(running)
    return stop unless running
    return if Machine.board_millis - @last_toggle_ms < @blink_interval_ms

    @on = !@on
    @last_toggle_ms = Machine.board_millis
    @gpio.write(@on ? 1 : 0)
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
  STATUS_LED_BLINK_INTERVAL_MS = 500
  DEFAULT_SECONDS = 10
  MAX_SECONDS = 60 * 60

  TIMER_STATE = PicoTimerState.new(DEFAULT_SECONDS, MAX_SECONDS)

  class << self
    def setup_status_led
      @status_led = CYW43::GPIO.new(CYW43::GPIO::LED_PIN)
      @status_led_controller = PicoTimerStatusLED.new(@status_led, STATUS_LED_BLINK_INTERVAL_MS)
    end

    def configure_timer(value)
      TIMER_STATE.configure(value)
      @status_led_controller.start if @status_led_controller
    end

    def start_timer
      TIMER_STATE.start
      @status_led_controller.start if @status_led_controller
    end

    def stop_timer
      TIMER_STATE.stop
      @status_led_controller.stop if @status_led_controller
    end

    def reset_timer
      TIMER_STATE.reset
      @status_led_controller.stop if @status_led_controller
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
        PicoTimerApp.setup_status_led
        address = CYW43::AP.ipv4_address
        raise "AP has no IPv4 address" unless address
        server = TCPServer.new("0.0.0.0", HTTP_PORT)
        puts "AP started: #{CYW43::AP.ssid}"
        puts "Open http://#{address}/"

        loop { PicoTimerApp.service_once(server) }
      rescue Interrupt
        puts "Stopping Pico Timer"
      ensure
        begin
          server.close if server
        rescue
        ensure
          @status_led_controller.stop if @status_led_controller
          CYW43::AP.disable
          puts "AP active?: #{CYW43::AP.active?}"
        end
      end
    end

    def service_once(server)
      Machine.check_signal
      TIMER_STATE.update
      @status_led_controller.update(TIMER_STATE.running?) if @status_led_controller
      client = server.accept_nonblock
      unless client
        sleep_ms(SERVICE_LOOP_INTERVAL_MS)
        return false
      end

      begin
        PicoTimerApp.handle_client(client)
      rescue => e
        puts "HTTP error: #{e.class}: #{e.message}"
      ensure
        client.close
      end
      true
    end

    def handle_client(client)
      request = PicoTimerApp.read_http_request(client)
      return unless request

      request_line = request.split("\r\n")[0]
      target = request_line.to_s.split(" ")[1] || "/"
      path = target.split("?")[0]

      case path
      when "/"
      when "/set"
        TIMER_STATE.configure(target.split("seconds=")[1] || DEFAULT_SECONDS)
        @status_led_controller.start if @status_led_controller
      when "/start"
        TIMER_STATE.start
        @status_led_controller.start if @status_led_controller
      when "/stop"
        TIMER_STATE.stop
        @status_led_controller.stop if @status_led_controller
      when "/reset"
        TIMER_STATE.reset
        @status_led_controller.stop if @status_led_controller
      else
        return PicoTimerApp.write_response(client, "404 Not Found", "Not Found\n")
      end

      PicoTimerApp.write_response(client, "200 OK", PicoTimerApp.timer_page)
    end

    def timer_page
      state = TIMER_STATE.running? ? "Running" : (TIMER_STATE.expired? ? "Expired" : "Stopped")
      <<~HTML
        <!doctype html>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>PicoRuby Timer</title>
        <h1>PicoRuby Timer</h1>
        <p>Status: <strong>#{state}</strong></p>
        <p>Remaining: <strong>#{TIMER_STATE.remaining_seconds} sec</strong></p>
        <form action="/set"><input name="seconds" type="number" min="1" max="#{MAX_SECONDS}" value="#{TIMER_STATE.duration_seconds}"><button>Set</button></form>
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
