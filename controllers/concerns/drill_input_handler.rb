# frozen_string_literal: true

module DrillInputHandler
  def handle_drill_input(key, modifiers = [])
    raw_key_str = key.to_s.sub(/\A:/, '')
    key_str     = raw_key_str.downcase
    normalized_modifiers = modifiers.map(&:to_s).map(&:downcase)

    if (defined?(@test_time_was_up_notified) && @test_time_was_up_notified == true) ||
       (defined?(@test_finished_waiting) && @test_finished_waiting == true)

      # Vuur de centrale schoonmaak-as af. Deze ruimt alle registers op.
      exit_test_study_session if respond_to?(:exit_test_study_session)

      return true # Slik de toets onvoorwaardelijk in om doorlekken te stoppen!
    end

    # 🚨 DEZE BEVEILIGING STAAT NU VEILIG HIERONDER:
    return false if @cards_to_test.nil? || @cards_to_test.empty?

    @test_current_idx ||= 0
    @test_show_meaning = false if @test_show_meaning.nil?
    total_cards = @cards_to_test.length

    # Gebruik dezelfde zichtbare kaartrijen als render_drill_view.
    @test_drill_scroll_y ||= 0

    visible_rows = @test_drill_visible_rows.to_i
    visible_rows = drill_page_metrics.first.to_i if visible_rows <= 0
    visible_rows = [visible_rows, 1].max

    @drill_viewport_start = @test_drill_scroll_y

    case key_str
    when '='
      current_test_card = @cards_to_test[@test_current_idx]
      SpeechHandler.speak_term(current_test_card&.term) if current_test_card
      return true
    # =========================================================================
    # 📑 TOETS 1: TAB (Overslaan / Markeren als gekend in de library)
    # Exact synchroon met de werking van quiz en multiple choice!
    # =========================================================================
    when 'tab', :tab
      current_test_card = @cards_to_test[@test_current_idx]

      if current_test_card
        s_idx   = @current_subject_idx || 0
        src_idx = @current_source_idx || 0
        d_idx   = @current_deck_idx || 0
        active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

        if active_deck
          db_cards_list = active_deck.cards || []
          # 🎯 IDENTITY MATCH FIX: We zoeken via de unieke equal? identiteit!
          db_card_row_idx = db_cards_list.index { |card| card.equal?(current_test_card) }

          if db_card_row_idx
            db_card = db_cards_list[db_card_row_idx]
            if db_card.respond_to?(:study=)
              db_card.study = false
            elsif db_card.respond_to?(:instance_variable_set)
              db_card.instance_variable_set(:@study, false)
            end
            @library_dirty = true
          end
        end
      end

      # Remove the card from this temporary session's active drill list.
      @test_last_deleted_card = @cards_to_test[@test_current_idx]
      @cards_to_test.delete_at(@test_current_idx)
      @test_card_directions.delete_at(@test_current_idx) if defined?(@test_card_directions) && @test_card_directions

      # Check of de lijst nu leeg is
      if @cards_to_test.empty?
        @test_excluded_count = @test_progressbar_total
        SoundManager.play(:finished) # 🏁 Alleen finished als dit de laatste was!
        test_finished if respond_to?(:test_finished)
        @test_finished_waiting = true
      else
        SoundManager.play(:exclude)  # 🎯 Alleen exclude als er nog kaarten overblijven!
        # Prepare the cursor and timer for the next card.
        prepare_drill_after_card_removal
      end

      return true

      # =========================================================================
      # 📑 TOETS: SPATIEBALK (Reveal & Move Engine met x-Sec Timer Reset)
      # =========================================================================
    when 'space', ' ', 'enter', 'return', "\r", "\n"
      return true if defined?(@test_timer_paused) && @test_timer_paused == true

      if !@test_show_meaning
        @test_show_meaning = true
      else
        # Continue to the next row.
        @test_show_meaning = false
        # 🎯 TIMED DRILL RESET: If the automatic timer is running, reset it now to a fresh x-second interval.
        reset_drill_card_state
        move_drill_cursor(1, total_cards)
      end

      return true

    # =========================================================================
    # HOME / END / g / G
    # =========================================================================
    when 'home'
      unless defined?(@test_timer_paused) && @test_timer_paused == true
        @test_current_idx = 0
        @test_drill_scroll_y = 0
        @drill_viewport_start = 0
        reset_drill_card_state
      end
      return true

    when 'end'
      unless defined?(@test_timer_paused) && @test_timer_paused == true
        visible_rows, = drill_page_metrics
        calculated_max_offset = [total_cards - visible_rows, 0].max

        @test_current_idx = total_cards - 1
        @test_drill_scroll_y = calculated_max_offset
        @drill_viewport_start = @test_drill_scroll_y
        reset_drill_card_state
      end
      return true

    when 'g'
      unless defined?(@test_timer_paused) && @test_timer_paused == true
        visible_rows, = drill_page_metrics
        calculated_max_offset = [total_cards - visible_rows, 0].max
        is_bottom = raw_key_str == 'G' || normalized_modifiers.include?('shift')

        # 🎯 COMPACTE STRUCTUUR: Inline toewijzing op basis van de hoofdletter-check
        @test_current_idx    = is_bottom ? total_cards - 1 : 0
        @test_drill_scroll_y = is_bottom ? calculated_max_offset : 0

        @drill_viewport_start = @test_drill_scroll_y
        reset_drill_card_state
      end
      return true

    # =========================================================================
    # UP / DOWN / j / k
    # =========================================================================
    when 'up', 'k'
      unless defined?(@test_timer_paused) && @test_timer_paused == true
        reset_drill_card_state
        move_drill_cursor(-1, total_cards)
      end
      return true

    when 'down', 'j'
      unless defined?(@test_timer_paused) && @test_timer_paused == true
        reset_drill_card_state
        move_drill_cursor(1, total_cards)
      end
      return true

    when 'page_up', 'pageup', 'page_down', 'pagedown', 'u', 'd'
      has_ctrl = normalized_modifiers.intersect?(%w[ctrl control])
      has_alt = normalized_modifiers.intersect?(%w[alt option meta])

      is_page_up =
        %w[page_up pageup].include?(key_str) ||
        (has_ctrl && key_str == 'u')

      is_page_down =
        %w[page_down pagedown].include?(key_str) ||
        (has_ctrl && key_str == 'd')

      return false if %w[u d v].include?(key_str) && !has_ctrl && !has_alt
      return false unless is_page_up || is_page_down

      unless defined?(@test_timer_paused) && @test_timer_paused == true
        visible_rows, = drill_page_metrics
        max_offset = [total_cards - visible_rows, 0].max

        current_idx = [[@test_current_idx.to_i, 0].max, total_cards - 1].min
        old_offset  = [[@test_drill_scroll_y.to_i, 0].max, max_offset].min

        screen_row = current_idx - old_offset
        screen_row = [[screen_row, 0].max, visible_rows - 1].min

        if is_page_down
          # 🎯 SMART BOUNDARY DOWN: Als de laatste regel al in beeld is,
          # spring dan direct naar de allerlaatste kaart zonder de scroll te muteren!
          if old_offset >= max_offset
            @test_current_idx = total_cards - 1
            @test_drill_scroll_y = max_offset
          else
            new_offset = old_offset + visible_rows
            if new_offset >= max_offset
              # The next page reaches or passes the bottom: scroll to the maximum
              # and move the cursor to the absolute last row.
              @test_drill_scroll_y = max_offset
              @test_current_idx = total_cards - 1
            else
              @test_drill_scroll_y = new_offset
              @test_current_idx = [[new_offset + screen_row, 0].max, total_cards - 1].min
            end
          end
        else
          # 🎯 SMART BOUNDARY UP: Als de eerste regel (index 0) al in beeld is,
          # spring dan direct naar de allereerste kaart zonder te scrollen!
          if old_offset <= 0
            @test_current_idx = 0
            @test_drill_scroll_y = 0
          else
            new_offset = old_offset - visible_rows
            if new_offset <= 0
              # The previous page reaches or passes the top: reset scrolling to 0
              # and move the cursor to the absolute first row.
              @test_drill_scroll_y = 0
              @test_current_idx = 0
            else
              @test_drill_scroll_y = new_offset
              @test_current_idx = [[new_offset + screen_row, 0].max, total_cards - 1].min
            end
          end
        end

        @drill_viewport_start = @test_drill_scroll_y
        reset_drill_card_state
      end

      return true

    # =========================================================================
    # 📑 TOETSEN: ENTER / LIVE CARD UPDATES VIA POPUP (OBJECT IDENTITY FIX)
    # FIXED: Always retrieve the correct duplicate card by object_id.
    # =========================================================================
    when 'f2'
      was_already_paused = (@test_timer_paused == true)
      test_toggle_pause unless was_already_paused

      if respond_to?(:handle_table_edit_card, true)
        s_idx   = @current_subject_idx || 0
        src_idx = @current_source_idx || 0
        d_idx   = @current_deck_idx || 0
        active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

        if active_deck
          db_cards_list = active_deck.cards || []
          current_test_card = @cards_to_test[@test_current_idx]

          if current_test_card
            # 🎯 IDENTITY MATCH REVOLUTIE:
            # We zoeken niet meer naar gelijke tekst, maar naar exact HETZELFDE object
            # in het computergeheugen (.equal? of object_id). Dit lost duplicaat-fouten direct op!
            db_card_row_idx = db_cards_list.index { |card| card.equal?(current_test_card) }

            if db_card_row_idx
              if defined?(@table_state) && @table_state && @table_state.respond_to?(:select)
                @table_state.select(db_card_row_idx)
              end
              simulated_context = { is_edit_action: true, selected_row: db_card_row_idx, cards_list: db_cards_list }
              handle_table_edit_card(simulated_context)

              # Neem de gewijzigde gegevens direct synchroon over in de actieve testsessie
              current_test_card.term    = db_cards_list[db_card_row_idx].term
              current_test_card.context = db_cards_list[db_card_row_idx].context
              current_test_card.meaning = db_cards_list[db_card_row_idx].meaning
            end
          end
        end
      end

      @active_focus       = :study_focus_mode
      @last_focus         = :study_focus_mode
      @current_study_mode = :drill

      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) unless was_already_paused
      test_toggle_pause unless was_already_paused

      return true

    when 'f5'
      SoundManager.play(:toggle)
      test_toggle_pause if respond_to?(:test_toggle_pause)
      return true

    when 'f4'
      SoundManager.play(:toggle)
      @test_show_context = !(@test_show_context || false)
      return true

      # =========================================================================
      # 🎯 TOETS: t (LIVE DRILL-TIMER IN- / UITSCHAKELEN TIJDENS HET OEFENEN!)
      # =========================================================================
    when 't'
      return true if defined?(@test_timer_paused) && @test_timer_paused == true

      # Toggle the flag (true becomes false, and false becomes true).
      @test_drill_timed = !(@test_drill_timed || false)

      if @test_drill_timed
        @test_timer_paused = false
        restart_drill_timer
      else
        @test_time_left = 0
        # Ook bij uitschakelen het frame-anker vernieuwen.
        @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      return true

    when 'f3'
      SoundManager.play(:toggle)
      # Omdat toggle_handwritten_font_style inside de NavigationInputHandler module leeft,
      # kunnen we deze hier direct veilig aanroepen op de app-instantie!
      if respond_to?(:toggle_handwritten_font_style, true)
        toggle_handwritten_font_style
      elsif respond_to?(:toggle_handwritten_font_style)
        toggle_handwritten_font_style
      end

      return true

    # =========================================================================
    # 🎯 TOETS: s (UNIVERSELE DRILL-TIMER SNELHEIDS-SCHAKELAAR: 5" ➔ 4" ➔ 6" ➔ 5")
    # =========================================================================
    when 's'
      return true if defined?(@test_timer_paused) && @test_timer_paused == true

      # 🔄 Cyclic rotation matrix logic (2" ➔ 3" ➔ 4" ➔ 2 ➔ …")
      @test_drill_timer_max = case @test_drill_timer_max
                              when 2 then 3 # als de gebruiker op 's' drukt en de timer staat op '3' seconden, zet hem dan nu op '2'
                              when 3 then 4 # als de gebruiker op 's' drukt en de timer staat op '2' seconden, zet hem dan nu op '4'
                              else 2 # fallback als er toch iets fout zou gaan bij het kiezen
                              end

      # Live update: Alleen als de timer op dit moment ACTIEF loopt én het antwoord
      # has not been shown yet, update the running timer immediately.
      restart_drill_timer if defined?(@test_drill_timed) && @test_drill_timed == true && !@test_show_meaning

      return true

    end

    false
  end

  private

  # Calculate how many rows are visible and how many a page jump covers.
  def drill_page_metrics
    # If the TUI has already determined an active region height, always use it.
    visible_rows = defined?(@test_drill_visible_rows) && @test_drill_visible_rows.to_i > 0 ? @test_drill_visible_rows.to_i : nil

    unless visible_rows
      terminal_height = RatatuiRuby.terminal_size&.height || 24
      drill_region_height = terminal_height - 3
      visible_rows = @test_show_context ? (drill_region_height - 4) : (drill_region_height - 2)
    end

    visible_rows = [visible_rows.to_i, 1].max
    page_step = [visible_rows - 1, 1].max

    [visible_rows, page_step]
  end

  def reset_drill_card_state
    @test_show_meaning = false

    # 🎯 FIX: Keep the scroll state following the cursor during Space/Enter updates.
    visible_rows, = drill_page_metrics
    total_cards = @cards_to_test.length
    keep_drill_scroll_synchronized(visible_rows, total_cards)

    return unless defined?(@test_drill_timed) && @test_drill_timed == true

    restart_drill_timer
  end

  # Begrenst een waarde tot de opgegeven minimum- en maximumgrens.
  def clamp_drill_value(value, min_value, max_value)
    [[value, min_value].max, max_value].min
  end

  # Move the drill cursor by one card, wrapping at the list boundaries.
  def move_drill_cursor(direction, total_cards)
    return if total_cards <= 0

    current_idx = [[@test_current_idx.to_i, 0].max, total_cards - 1].min
    visible_rows, = drill_page_metrics
    max_offset = [total_cards - visible_rows, 0].max

    # 1. Calculate the new cursor index with correct wrapping.
    new_idx = (current_idx + direction) % total_cards

    # 2. Bepaal de stabiele scroll offset (nooit groter dan max_offset, nooit kleiner dan 0!)
    offset = [[@test_drill_scroll_y.to_i, 0].max, max_offset].min

    # 3. Scroll the viewport if the cursor moves outside the visible area.
    if new_idx < offset
      offset = new_idx
    elsif new_idx >= offset + visible_rows
      offset = new_idx - visible_rows + 1
    end

    # 4. Enforce wrap boundaries when crossing an edge.
    if current_idx == 0 && direction == -1
      offset = max_offset
    elsif current_idx == total_cards - 1 && direction == 1
      offset = 0
    end

    @test_current_idx = new_idx
    @test_drill_scroll_y = [[offset, 0].max, max_offset].min
    @drill_viewport_start = @test_drill_scroll_y
  end

  def keep_drill_scroll_synchronized(visible_rows, total_cards)
    @test_current_idx = @test_current_idx.to_i
    visible_rows = [visible_rows.to_i, 1].max
    max_offset = [total_cards - visible_rows, 0].max

    # Keep the current scroll offset within the table's strict bounds.
    offset = [[@test_drill_scroll_y.to_i, 0].max, max_offset].min

    if @test_current_idx < offset
      offset = @test_current_idx
    elsif @test_current_idx >= offset + visible_rows
      offset = @test_current_idx - visible_rows + 1
    end

    @test_drill_scroll_y = [[offset, 0].max, max_offset].min
    @drill_viewport_start = @test_drill_scroll_y
  end

  # Restart the countdown and set the time anchor to the current moment.
  def restart_drill_timer
    @test_time_left = @test_drill_timer_max
    @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Correct the cursor and reset the card state after removing a card.
  # Called only when cards remain in the drill.
  def prepare_drill_after_card_removal
    @test_current_idx = @cards_to_test.length - 1 if @test_current_idx >= @cards_to_test.length
    reset_drill_card_state
  end

  # Springt naar de eerste of laatste kaart en vernieuwt de kaartstatus.
  def jump_drill_cursor(position, total_cards)
    @test_current_idx = position == :first ? 0 : [total_cards - 1, 0].max
    reset_drill_card_state
  end
end
