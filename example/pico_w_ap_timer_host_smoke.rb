module Machine
  @board_millis = 0
  @signal_checks = 0
  @signal_self_managed = false

  class << self
    attr_accessor :board_millis, :signal_checks, :signal_self_managed

    def advance(milliseconds)
      @board_millis += milliseconds
    end

    def check_signal
      @signal_checks += 1
    end

    def signal_self_manage
      @signal_self_managed = true
    end
  end
end

def sleep_ms(milliseconds)
  Machine.advance(milliseconds)
end

module CYW43
  class GPIO
    LED_PIN = 0

    attr_reader :writes

    def initialize(_pin)
      @writes = []
      @value = 0
    end

    def write(value)
      @value = value
      @writes << value
    end

    def read
      @value
    end
  end

  module AP
    class << self
      def ssid
        "PicoRuby-Timer"
      end

      def ipv4_address
        "192.168.4.1"
      end
    end
  end
end

class FakeClient
  attr_reader :written

  def initialize(target)
    @request = "GET #{target} HTTP/1.1\r\nHost: 192.168.4.1\r\n\r\n"
    @written = ""
    @closed = false
  end

  def read_nonblock(maximum_length)
    return nil if @request.empty?

    chunk = @request.byteslice(0, maximum_length)
    @request = @request.byteslice(chunk.bytesize, @request.bytesize - chunk.bytesize) || ""
    chunk
  end

  def write(data)
    @written << data.to_s
    data.to_s.bytesize
  end

  def close
    @closed = true
  end

  def closed?
    @closed
  end
end

class FakeSilentClient < FakeClient
  def read_nonblock(_maximum_length)
    nil
  end
end

class FakeServer
  def initialize(clients = [])
    @clients = clients
  end

  def accept_nonblock
    @clients.shift
  end
end

component_paths = %w[state.rb status_led.rb http.rb app.rb].map do |name|
  File.expand_path("example/pico_w_ap_timer/#{name}")
end
component_paths.each { |path| load path }

app = PicoTimerApp.new
status_gpio = app.setup_status_led
timer_state = app.timer_state
status_led = app.status_led
http = app.http
raise "status LED did not start off" unless status_gpio.read == 0

raise "initial duration mismatch" unless timer_state.duration_seconds == 10
raise "initial remaining mismatch" unless timer_state.remaining_seconds == 10
raise "timer started unexpectedly" if timer_state.running?

timer_state.configure(10)
status_led.start
raise "configure did not start timer" unless timer_state.running?
raise "running timer did not turn status LED on" unless status_gpio.read == 1
Machine.advance(PicoTimerApp::STATUS_LED_BLINK_INTERVAL_MS)
timer_state.update
status_led.update(timer_state.running?)
raise "running status LED did not blink off" unless status_gpio.read == 0
Machine.advance(PicoTimerApp::STATUS_LED_BLINK_INTERVAL_MS)
timer_state.update
status_led.update(timer_state.running?)
raise "running status LED did not blink on" unless status_gpio.read == 1
timer_state.configure(10)
status_led.start
Machine.advance(3_100)
raise "running timer stopped early" unless timer_state.running?
raise "remaining time mismatch" unless timer_state.remaining_seconds == 7

timer_state.stop
status_led.stop
raise "stopped timer left status LED on" unless status_gpio.read == 0
stopped_remaining = timer_state.remaining_seconds
Machine.advance(2_000)
raise "stopped timer changed" unless timer_state.remaining_seconds == stopped_remaining

timer_state.start
status_led.start
Machine.advance(7_000)
raise "restart resumed the old remainder" unless timer_state.running?
raise "restart did not use configured duration" unless timer_state.remaining_seconds == 3
Machine.advance(3_000)
raise "timer did not expire" unless timer_state.expired?
raise "expired timer still running" if timer_state.running?
raise "expired timer has remaining time" unless timer_state.remaining_seconds == 0
timer_state.update
status_led.update(timer_state.running?)
raise "expired timer left status LED on" unless status_gpio.read == 0

timer_state.configure(5)
raise "configured duration mismatch" unless timer_state.duration_seconds == 5
raise "configure did not restart timer" unless timer_state.remaining_seconds == 5
raise "configure did not leave timer running" unless timer_state.running?
raise "configure left timer expired" if timer_state.expired?

timer_state.configure(0)
raise "minimum duration was not clamped" unless timer_state.duration_seconds == 1
timer_state.configure(3_601)
raise "maximum duration was not clamped" unless timer_state.duration_seconds == 3_600

timer_state.configure(1)
status_led.start
idle_server = FakeServer.new
100.times do
  raise "idle service unexpectedly accepted a client" if app.service_once(idle_server)
end
raise "idle timer did not expire" unless timer_state.expired?
raise "idle timer still running" if timer_state.running?
raise "idle timer has remaining time" unless timer_state.remaining_seconds == 0
10.times { app.service_once(idle_server) }
raise "expired state changed during idle service" unless timer_state.expired?
raise "service loop did not check signals" unless 110 <= Machine.signal_checks

root_client = FakeClient.new("/")
root_server = FakeServer.new([root_client])
raise "service did not accept a queued client" unless app.service_once(root_server)
raise "root route failed" unless root_client.written.include?("200 OK")
raise "root page missing title" unless root_client.written.include?("PicoRuby Timer")
raise "service did not close the client" unless root_client.closed?

set_client = FakeClient.new("/set?seconds=12")
http.handle_client(set_client)
raise "set route failed to render" unless set_client.written.include?("200 OK")
raise "set route failed" unless timer_state.duration_seconds == 12
raise "set route did not start timer" unless timer_state.running?

start_client = FakeClient.new("/start")
http.handle_client(start_client)
raise "start route failed" unless timer_state.running?

stop_client = FakeClient.new("/stop")
http.handle_client(stop_client)
raise "stop route failed" if timer_state.running?

reset_client = FakeClient.new("/reset")
http.handle_client(reset_client)
raise "reset route failed" unless timer_state.remaining_seconds == 12
raise "reset route left status LED on" unless status_gpio.read == 0

missing_client = FakeClient.new("/missing")
http.handle_client(missing_client)
raise "missing route did not return 404" unless missing_client.written.include?("404 Not Found")

silent_client = FakeSilentClient.new("/")
started_at = Machine.board_millis
http.handle_client(silent_client)
elapsed = Machine.board_millis - started_at
raise "silent connection exceeded first-byte timeout" if elapsed > PicoTimerHTTP::FIRST_BYTE_TIMEOUT_MS + PicoTimerHTTP::POLL_INTERVAL_MS
raise "silent connection received a response" unless silent_client.written.empty?

timer_state.start
status_led.start
raise "status LED did not turn on before cleanup" unless status_gpio.read == 1
status_led.stop
raise "status LED cleanup failed" unless status_gpio.read == 0

puts "Pico Timer host smoke test passed"
