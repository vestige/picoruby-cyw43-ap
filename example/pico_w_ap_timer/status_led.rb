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
