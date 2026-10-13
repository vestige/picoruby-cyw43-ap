class PicoTimerButton
  def initialize(gpio, debounce_ms)
    @gpio = gpio
    @debounce_ms = debounce_ms
    @raw_value = @gpio.read
    @stable_value = @raw_value
    @changed_at_ms = Machine.board_millis
  end

  def pressed?
    value = @gpio.read
    if value != @raw_value
      @raw_value = value
      @changed_at_ms = Machine.board_millis
      return false
    end

    return false if value == @stable_value
    return false if Machine.board_millis - @changed_at_ms < @debounce_ms

    @stable_value = value
    value == 0
  end
end

class PicoTimerButtonControl
  def initialize(button, timer_state, status_led, expiry_led)
    @button = button
    @timer_state = timer_state
    @status_led = status_led
    @expiry_led = expiry_led
  end

  def update
    return unless @button.pressed?

    if @timer_state.running?
      @timer_state.stop
      @status_led.stop
    elsif @expiry_led.on?
      @expiry_led.off
    else
      @timer_state.start
      @status_led.start
      @expiry_led.timer_started
    end
  end
end
