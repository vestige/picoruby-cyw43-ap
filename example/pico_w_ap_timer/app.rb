class PicoTimerApp
  AP_SSID = "PicoRuby-Timer"
  AP_PASSWORD = "12345678"
  HTTP_PORT = 80
  SERVICE_LOOP_INTERVAL_MS = 10
  STATUS_LED_BLINK_INTERVAL_MS = 500
  EXPIRY_LED_PIN = 15
  BUTTON_PIN = 16
  BUTTON_DEBOUNCE_MS = 30
  DEFAULT_SECONDS = 10
  MAX_SECONDS = 60 * 60

  attr_reader :timer_state, :status_led, :expiry_led, :control, :button, :button_control, :http

  def initialize
    @timer_state = PicoTimerState.new(DEFAULT_SECONDS, MAX_SECONDS)
  end

  def setup_leds
    gpio = CYW43::GPIO.new(CYW43::GPIO::LED_PIN)
    @status_led = PicoTimerStatusLED.new(gpio, STATUS_LED_BLINK_INTERVAL_MS)
    expiry_gpio = GPIO.new(EXPIRY_LED_PIN, GPIO::OUT)
    @expiry_led = PicoTimerExpiryLED.new(expiry_gpio)
    @control = PicoTimerControl.new(@timer_state, @status_led, @expiry_led)
    button_gpio = GPIO.new(BUTTON_PIN, GPIO::IN | GPIO::PULL_UP)
    @button = PicoTimerButton.new(button_gpio, BUTTON_DEBOUNCE_MS)
    @button_control = PicoTimerButtonControl.new(@button, @control)
    @http = PicoTimerHTTP.new(@timer_state, @expiry_led, @control, @button_control)
    gpio
  end

  def run
    puts "Pico Timer starting"
    Machine.signal_self_manage
    CYW43.init("JP")
    raise "failed to enable AP mode" unless CYW43::AP.enable(AP_SSID, AP_PASSWORD)

    server = nil
    begin
      setup_leds
      address = CYW43::AP.ipv4_address
      raise "AP has no IPv4 address" unless address
      server = TCPServer.new("0.0.0.0", HTTP_PORT)
      puts "AP started: #{CYW43::AP.ssid}"
      puts "Open http://#{address}/"

      loop do
        raise "AP stopped unexpectedly" unless CYW43::AP.active?
        service_once(server)
      end
    rescue Interrupt
      puts "Stopping Pico Timer"
    ensure
      begin
        server.close if server
      rescue
      ensure
        @status_led.stop if @status_led
        @expiry_led.off if @expiry_led
        CYW43::AP.disable
        puts "AP active?: #{CYW43::AP.active?}"
      end
    end
  end

  def service_once(server)
    Machine.check_signal
    @timer_state.update
    @status_led.update(@timer_state.running?) if @status_led
    @expiry_led.update(@timer_state.expired?) if @expiry_led
    @button_control.update if @button_control
    client = server.accept_nonblock
    unless client
      sleep_ms(SERVICE_LOOP_INTERVAL_MS)
      return false
    end

    begin
      @http.handle_client(client)
    rescue => e
      puts "HTTP error: #{e.class}: #{e.message}"
    ensure
      client.close
    end
    true
  end

end
