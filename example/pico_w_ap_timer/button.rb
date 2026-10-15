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
  def initialize(button, control)
    @button = button
    @control = control
  end

  def update
    return unless @button.pressed?
    @control.button_pressed
  end
end
