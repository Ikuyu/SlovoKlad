class SoftwareCursor
  BLINK_INTERVAL = 0.5 # seconden

  attr_reader :visible

  def initialize
    @visible = true
    @last_toggle = monotonic_time
  end

  # Return true when another render is needed.
  def update
    now = monotonic_time
    elapsed = now - @last_toggle

    return false if elapsed < BLINK_INTERVAL

    # Houd de timing stabiel, ook als een render iets langer duurt
    toggles = (elapsed / BLINK_INTERVAL).floor
    @last_toggle += toggles * BLINK_INTERVAL

    @visible = !@visible if toggles.odd?

    true
  end

  private

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
