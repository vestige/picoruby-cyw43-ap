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

source_path = File.expand_path("example/pico_w_ap_timer.rb")
source = File.read(source_path)
source = source.lines.reject do |line|
  line.start_with?("require ") || line.strip == "PicoTimerApp.run"
end.join
eval(source, nil, source_path)

PicoTimerApp.configure_timer(10)
raise "initial duration mismatch" unless PicoTimerApp.timer_duration_seconds == 10
raise "initial remaining mismatch" unless PicoTimerApp.timer_remaining_seconds == 10
raise "timer started unexpectedly" if PicoTimerApp.timer_running?

PicoTimerApp.start_timer
Machine.advance(3_100)
raise "running timer stopped early" unless PicoTimerApp.timer_running?
raise "remaining time mismatch" unless PicoTimerApp.timer_remaining_seconds == 7

PicoTimerApp.stop_timer
stopped_remaining = PicoTimerApp.timer_remaining_seconds
Machine.advance(2_000)
raise "stopped timer changed" unless PicoTimerApp.timer_remaining_seconds == stopped_remaining

PicoTimerApp.start_timer
Machine.advance(7_000)
raise "timer did not expire" unless PicoTimerApp.timer_expired?
raise "expired timer still running" if PicoTimerApp.timer_running?
raise "expired timer has remaining time" unless PicoTimerApp.timer_remaining_seconds == 0

PicoTimerApp.configure_timer(5)
raise "configured duration mismatch" unless PicoTimerApp.timer_duration_seconds == 5
raise "configure did not reset timer" unless PicoTimerApp.timer_remaining_seconds == 5
raise "configure left timer expired" if PicoTimerApp.timer_expired?

PicoTimerApp.configure_timer(0)
raise "minimum duration was not clamped" unless PicoTimerApp.timer_duration_seconds == 1
PicoTimerApp.configure_timer(3_601)
raise "maximum duration was not clamped" unless PicoTimerApp.timer_duration_seconds == 3_600

PicoTimerApp.configure_timer(1)
PicoTimerApp.start_timer
idle_server = FakeServer.new
100.times do
  raise "idle service unexpectedly accepted a client" if PicoTimerApp.service_once(idle_server)
end
raise "idle timer did not expire" unless PicoTimerApp.timer_expired?
raise "idle timer still running" if PicoTimerApp.timer_running?
raise "idle timer has remaining time" unless PicoTimerApp.timer_remaining_seconds == 0
10.times { PicoTimerApp.service_once(idle_server) }
raise "expired state changed during idle service" unless PicoTimerApp.timer_expired?
raise "service loop did not check signals" unless 110 <= Machine.signal_checks

root_client = FakeClient.new("/")
root_server = FakeServer.new([root_client])
raise "service did not accept a queued client" unless PicoTimerApp.service_once(root_server)
raise "root route failed" unless root_client.written.include?("200 OK")
raise "root page missing title" unless root_client.written.include?("PicoRuby Timer")
raise "service did not close the client" unless root_client.closed?

set_client = FakeClient.new("/set?seconds=12")
PicoTimerApp.handle_client(set_client)
raise "set route failed to render" unless set_client.written.include?("200 OK")
raise "set route failed" unless PicoTimerApp.timer_duration_seconds == 12

start_client = FakeClient.new("/start")
PicoTimerApp.handle_client(start_client)
raise "start route failed" unless PicoTimerApp.timer_running?

stop_client = FakeClient.new("/stop")
PicoTimerApp.handle_client(stop_client)
raise "stop route failed" if PicoTimerApp.timer_running?

reset_client = FakeClient.new("/reset")
PicoTimerApp.handle_client(reset_client)
raise "reset route failed" unless PicoTimerApp.timer_remaining_seconds == 12

missing_client = FakeClient.new("/missing")
PicoTimerApp.handle_client(missing_client)
raise "missing route did not return 404" unless missing_client.written.include?("404 Not Found")

silent_client = FakeSilentClient.new("/")
started_at = Machine.board_millis
PicoTimerApp.handle_client(silent_client)
elapsed = Machine.board_millis - started_at
raise "silent connection exceeded first-byte timeout" if elapsed > PicoTimerApp::HTTP_FIRST_BYTE_TIMEOUT_MS + PicoTimerApp::HTTP_POLL_INTERVAL_MS
raise "silent connection received a response" unless silent_client.written.empty?

puts "Pico Timer host smoke test passed"
