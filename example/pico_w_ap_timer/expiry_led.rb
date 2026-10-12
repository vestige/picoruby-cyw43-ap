class PicoTimerExpiryLED
  def initialize(gpio)
    @gpio = gpio
    @expiration_handled = false
    @on = false
    @gpio.write(0)
  end

  def timer_started
    @expiration_handled = false
    off
  end

  def update(expired)
    return unless expired
    return if @expiration_handled

    @expiration_handled = true
    @on = true
    @gpio.write(1)
  end

  def off
    @on = false
    @gpio.write(0)
  end

  def on?
    @on
  end
end
