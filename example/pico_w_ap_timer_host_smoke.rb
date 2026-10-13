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
  class << self
    def init(_country_code)
      true
    end
  end

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
    @active = false

    class << self
      def enable(_ssid, _password)
        @active = true
      end

      def disable
        @active = false
      end

      def active?
        @active
      end

      def ssid
        "PicoRuby-Timer"
      end

      def ipv4_address
        "192.168.4.1"
      end
    end
  end
end

class GPIO
  IN = 1
  OUT = 2
  PULL_UP = 8

  attr_reader :pin, :flags, :writes

  def initialize(pin, flags)
    @pin = pin
    @flags = flags
    @writes = []
    @value = flags & PULL_UP == PULL_UP ? 1 : 0
  end

  def write(value)
    @value = value
    @writes << value
  end

  def read
    @value
  end

  def simulate_input(value)
    @value = value
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

class FakeButtonDuringRequestClient < FakeClient
  def initialize(target, gpio)
    super(target)
    @gpio = gpio
    @read_count = 0
  end

  def read_nonblock(maximum_length)
    @read_count += 1
    @gpio.simulate_input(0) if @read_count == 1
    @gpio.simulate_input(1) if @read_count == 6
    return nil if @read_count < 10

    super(maximum_length)
  end
end

class FakeServer
  attr_reader :closed

  def initialize(clients = [])
    @clients = clients
    @closed = false
  end

  def accept_nonblock
    @clients.shift
  end

  def close
    @closed = true
  end
end

class FailingServer < FakeServer
  def accept_nonblock
    raise "simulated server failure"
  end
end

component_paths = %w[state.rb status_led.rb expiry_led.rb button.rb http.rb app.rb].map do |name|
  File.expand_path("example/pico_w_ap_timer/#{name}")
end
component_paths.each { |path| load path }

app = PicoTimerApp.new
status_gpio = app.setup_leds
timer_state = app.timer_state
status_led = app.status_led
expiry_led = app.expiry_led
button = app.button
http = app.http
raise "status LED did not start off" unless status_gpio.read == 0
expiry_gpio = expiry_led.instance_variable_get(:@gpio)
raise "expiry LED is not on GP15" unless expiry_gpio.pin == PicoTimerApp::EXPIRY_LED_PIN
raise "expiry LED did not start off" unless expiry_gpio.read == 0
button_gpio = button.instance_variable_get(:@gpio)
raise "button is not on GP16" unless button_gpio.pin == PicoTimerApp::BUTTON_PIN
expected_button_flags = GPIO::IN | GPIO::PULL_UP
raise "button is not a pull-up input" unless button_gpio.flags == expected_button_flags

button_server = FakeServer.new
button_gpio.simulate_input(0)
2.times { app.service_once(button_server) }
button_gpio.simulate_input(1)
app.service_once(button_server)
button_gpio.simulate_input(0)
3.times { app.service_once(button_server) }
raise "button bounce triggered before debounce" if timer_state.running?
app.service_once(button_server)
raise "debounced button did not start timer" unless timer_state.running?
10.times { app.service_once(button_server) }
raise "held button repeated its action" unless timer_state.running?
button_gpio.simulate_input(1)
4.times { app.service_once(button_server) }
button_gpio.simulate_input(0)
4.times { app.service_once(button_server) }
raise "button did not stop running timer" if timer_state.running?
raise "button stop did not pause timer" unless timer_state.paused?
button_gpio.simulate_input(1)
4.times { app.service_once(button_server) }
button_gpio.simulate_input(0)
4.times { app.service_once(button_server) }
raise "button did not resume paused timer" unless timer_state.running?
button_gpio.simulate_input(1)
4.times { app.service_once(button_server) }
timer_state.reset
status_led.stop
expiry_led.off

raise "initial duration mismatch" unless timer_state.duration_seconds == 10
raise "initial remaining mismatch" unless timer_state.remaining_seconds == 10
raise "timer started unexpectedly" if timer_state.running?

timer_state.configure(10)
status_led.start
expiry_led.timer_started
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
expiry_led.timer_started
Machine.advance(3_100)
raise "running timer stopped early" unless timer_state.running?
raise "remaining time mismatch" unless timer_state.remaining_seconds == 7

timer_state.stop
status_led.stop
raise "stopped timer left status LED on" unless status_gpio.read == 0
raise "stopped timer is not paused" unless timer_state.paused?
stopped_remaining = timer_state.remaining_seconds
Machine.advance(2_000)
raise "stopped timer changed" unless timer_state.remaining_seconds == stopped_remaining

timer_state.start
status_led.start
raise "resume left timer paused" if timer_state.paused?
Machine.advance(6_000)
raise "resume did not use the old remainder" unless timer_state.running?
raise "resumed timer remaining time mismatch" unless timer_state.remaining_seconds == 1
Machine.advance(1_000)
raise "timer did not expire" unless timer_state.expired?
raise "expired timer still running" if timer_state.running?
raise "expired timer has remaining time" unless timer_state.remaining_seconds == 0
timer_state.update
status_led.update(timer_state.running?)
raise "expired timer left status LED on" unless status_gpio.read == 0
expiry_led.update(timer_state.expired?)
raise "expiry LED did not turn on" unless expiry_gpio.read == 1

button_gpio.simulate_input(0)
4.times { app.service_once(button_server) }
raise "button did not turn expiry LED off" unless expiry_gpio.read == 0
raise "expiry LED button changed expired state" unless timer_state.expired?
10.times { app.service_once(button_server) }
raise "held button started timer after LED Off" if timer_state.running?
button_gpio.simulate_input(1)
4.times { app.service_once(button_server) }
expiry_led.update(timer_state.expired?)
raise "expiry LED relit after LED Off" unless expiry_gpio.read == 0

timer_state.start
status_led.start
expiry_led.timer_started
raise "start after expiry did not use configured duration" unless timer_state.remaining_seconds == 10
raise "start did not leave expiry LED off" unless expiry_gpio.read == 0
Machine.advance(10_000)
timer_state.update
expiry_led.update(timer_state.expired?)
raise "expiry LED did not turn on after rearming" unless expiry_gpio.read == 1
timer_state.reset
status_led.stop
expiry_led.off
raise "reset did not turn expiry LED off" unless expiry_gpio.read == 0

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
expiry_led.timer_started
idle_server = FakeServer.new
101.times do
  raise "idle service unexpectedly accepted a client" if app.service_once(idle_server)
end
raise "idle timer did not expire" unless timer_state.expired?
raise "idle timer still running" if timer_state.running?
raise "idle timer has remaining time" unless timer_state.remaining_seconds == 0
raise "idle expiry did not light expiry LED" unless expiry_gpio.read == 1
10.times { app.service_once(idle_server) }
raise "expired state changed during idle service" unless timer_state.expired?
raise "service loop did not check signals" unless 111 <= Machine.signal_checks

root_client = FakeClient.new("/")
root_server = FakeServer.new([root_client])
raise "service did not accept a queued client" unless app.service_once(root_server)
raise "root route failed" unless root_client.written.include?("200 OK")
raise "root page missing title" unless root_client.written.include?("PicoRuby Timer")
raise "root page missing expiry LED state" unless root_client.written.include?("Expiry LED:")
raise "service did not close the client" unless root_client.closed?

set_client = FakeClient.new("/set?seconds=12")
http.handle_client(set_client)
raise "set route failed to render" unless set_client.written.include?("200 OK")
raise "set route failed" unless timer_state.duration_seconds == 12
raise "set route did not start timer" unless timer_state.running?
raise "set route did not turn expiry LED off" unless expiry_gpio.read == 0
raise "running page missing Restart action" unless set_client.written.include?(">Restart</a>")

start_client = FakeClient.new("/start")
http.handle_client(start_client)
raise "start route failed" unless timer_state.running?

stop_client = FakeClient.new("/stop")
http.handle_client(stop_client)
raise "stop route failed" if timer_state.running?

timer_state.start
status_led.start
expiry_led.timer_started
Machine.advance(12_000)
app.service_once(FakeServer.new)
raise "route test expiry did not light LED" unless expiry_gpio.read == 1

reset_client = FakeClient.new("/reset")
http.handle_client(reset_client)
raise "reset route failed" unless timer_state.remaining_seconds == 12
raise "reset route left timer paused" if timer_state.paused?
raise "reset route left status LED on" unless status_gpio.read == 0
raise "reset route left expiry LED on" unless expiry_gpio.read == 0
raise "stopped page missing Start action" unless reset_client.written.include?(">Start</a>")

http.handle_client(FakeClient.new("/start"))
Machine.advance(4_100)
http.handle_client(FakeClient.new("/stop"))
paused_remaining = timer_state.remaining_seconds
raise "stop route did not pause timer" unless timer_state.paused?
paused_page = FakeClient.new("/")
http.handle_client(paused_page)
raise "paused page missing Paused state" unless paused_page.written.include?("Status: <strong>Paused</strong>")
raise "paused page missing Resume action" unless paused_page.written.include?(">Resume</a>")
Machine.advance(2_000)
http.handle_client(FakeClient.new("/start"))
raise "start route did not resume paused remainder" unless timer_state.remaining_seconds == paused_remaining

http.handle_client(FakeClient.new("/stop"))
http.handle_client(FakeClient.new("/set?seconds=9"))
raise "set route resumed the paused remainder" unless timer_state.remaining_seconds == 9

led_off_client = FakeClient.new("/ledoff")
http.handle_client(led_off_client)
raise "LED Off route failed" unless expiry_gpio.read == 0

timer_state.reset
status_led.stop
button_during_request = FakeButtonDuringRequestClient.new("/", button_gpio)
http.handle_client(button_during_request)
raise "HTTP request wait hid button press" unless timer_state.running?
raise "button press during HTTP request did not render running state" unless button_during_request.written.include?("Status: <strong>Running</strong>")
button_gpio.simulate_input(1)
4.times { app.service_once(button_server) }

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
expiry_led.timer_started
expiry_led.update(true)
raise "expiry LED did not turn on before cleanup" unless expiry_gpio.read == 1
expiry_led.off
raise "expiry LED cleanup failed" unless expiry_gpio.read == 0

cleanup_server = FailingServer.new
tcp_server_class = Class.new do
  define_singleton_method(:new) do |_address, _port|
    cleanup_server
  end
end
Object.const_set(:TCPServer, tcp_server_class)
cleanup_app = PicoTimerApp.new
begin
  cleanup_app.run
  raise "abnormal shutdown test did not fail"
rescue RuntimeError => e
  raise unless e.message == "simulated server failure"
end
raise "abnormal shutdown left server open" unless cleanup_server.closed
raise "abnormal shutdown left status LED on" unless cleanup_app.status_led.instance_variable_get(:@gpio).read == 0
raise "abnormal shutdown left expiry LED on" unless cleanup_app.expiry_led.instance_variable_get(:@gpio).read == 0
raise "abnormal shutdown left AP active" if CYW43::AP.active?

puts "Pico Timer host smoke test passed"
