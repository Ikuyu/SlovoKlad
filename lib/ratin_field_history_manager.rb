class RatinFieldHistoryManager
  attr_reader :undo_stack, :redo_stack

  def initialize(max_depth = 50)
    @undo_stack = []
    @redo_stack = []
    @max_depth  = max_depth

    # Track timestamps to bundle continuous character entries together
    @last_snapshot_time = nil
    @debounce_threshold = 0.5 # seconds
  end

  # Capture text state. Force: true bypasses the timer (useful for cuts/pastes/blur)
  def save_state(text, cursor_index, force: false, visual_caret: nil)
    now = Time.now

    # Keep the first state of a continuous typing group.
    # Only refresh the debounce timer for subsequent keystrokes.
    if !force && @last_snapshot_time && (now - @last_snapshot_time < @debounce_threshold)
      @redo_stack.clear
      @last_snapshot_time = now
      return
    end

    # Clean commit or forced block
    # Avoid pushing duplicates of identical sequential states
    if @undo_stack.empty? || @undo_stack.last[:text] != text
      @undo_stack << { text: text.dup, cursor: cursor_index, visual_caret: visual_caret }
      @undo_stack.shift if @undo_stack.size > @max_depth
    end

    @redo_stack.clear
    # A forced snapshot closes the current typing debounce group.
    # The next edit must not overwrite a paste/cut undo boundary.
    @last_snapshot_time = force ? nil : now
  end

  def execute_undo(current_text, current_cursor, visual_caret: nil)
    return nil if @undo_stack.empty?

    @last_snapshot_time = nil

    # Als de bovenste toestand exact overeenkomt met wat er nu live op het scherm staat,
    # first move the current top state to the redo stack.
    if @undo_stack.last[:text] == current_text
      top_state = @undo_stack.pop
      @redo_stack << top_state
    else
      # Staat de live-tekst los van de stack? Sla de live-tekst dan op als redo-punt.
      @redo_stack << { text: current_text.dup, cursor: current_cursor, visual_caret: visual_caret }
    end

    # Now retrieve the actual previous stack state (the initial state or previous character).
    return nil if @undo_stack.empty?

    # We bekijken de toestand (.last), maar laten hem op de stack staan totdat
    # undo is pressed again. This preserves the complete history chain.
    @undo_stack.last
  end

  def execute_redo(current_text, current_cursor, visual_caret: nil)
    return nil if @redo_stack.empty?

    @last_snapshot_time = nil

    # If the current displayed text already matches the top undo state,
    # hoeven we hem niet dubbel op de stack te pushen.
    if @undo_stack.empty? || @undo_stack.last[:text] != current_text
      @undo_stack << { text: current_text.dup, cursor: current_cursor, visual_caret: visual_caret }
    end

    # Pak de eerstvolgende stap vooruit uit de redo-stack
    @redo_stack.pop
  end

  def clear
    @undo_stack.clear
    @redo_stack.clear
    @last_snapshot_time = nil
  end
end
