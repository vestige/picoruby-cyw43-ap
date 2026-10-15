class PicoTimerControl
  def initialize(timer_state, status_led, expiry_led)
    @timer_state = timer_state
    @status_led = status_led
    @expiry_led = expiry_led
  end

  def configure(value)
    @timer_state.configure(value)
    started
  end

  def start
    @timer_state.start
    started
  end

  def stop
    @timer_state.stop
    @status_led.stop
  end

  def reset
    @timer_state.reset
    @status_led.stop
    @expiry_led.off
  end

  def led_off
    @expiry_led.off
  end

  def button_pressed
    if @timer_state.running?
      stop
    elsif @expiry_led.on?
      led_off
    else
      start
    end
  end

  private

  def started
    @status_led.start
    @expiry_led.timer_started
  end
end
