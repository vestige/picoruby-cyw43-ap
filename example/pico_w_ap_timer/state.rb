class PicoTimerState
  attr_reader :duration_seconds, :max_seconds

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

  def remaining_seconds
    update
    milliseconds = @running ? current_remaining_ms : @remaining_ms
    (milliseconds + 999) / 1000
  end
end
