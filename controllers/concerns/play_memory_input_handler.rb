module PlayMemoryInputHandler
  private

  def initialize_memory_game(cards)
    @memory_cards = []
    @memory_scroll_offset = 0
    @memory_max_scroll = 0
    @memory_input_buffer = ''
    @memory_pending_match = nil
    @memory_search_text = nil
    @memory_message = "#{AppConfig.settings.language_string(:statusbar_study_memory_init_msg)}!"

    cards.each do |card|
      @memory_cards << {
        type: :term,
        content: card.term.to_s,
        matched: false,
        id: card.object_id
      }

      @memory_cards << {
        type: :meaning,
        content: card.meaning.to_s,
        matched: false,
        id: card.object_id
      }
    end

    @memory_cards.shuffle!

    @memory_cards.each_with_index do |card, idx|
      letter = memory_column_label(idx / 9)
      number = (idx % 9) + 1
      card[:coord] = "#{letter}#{number}"
    end

    @memory_first_flipped_idx = nil
    @memory_second_flipped_idx = nil
    @memory_search_card = nil
    @memory_header_left_text = nil
    @memory_header_right_text = nil

    @test_drill_elapsed = 0
    @test_timer_paused = false
    @test_finished_waiting = false
    @test_time_was_up_notified = false
    @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  public

  def handle_memory_input(key, modifiers = [])
    return false unless @current_study_mode == :memory

    # Popup heeft altijd voorrang op Memory-invoer.
    return false if @active_focus == :popup

    key_str = key.to_s.strip.sub(/\A:/, '')
    key_down = key_str.downcase
    mods = Array(modifiers).map { |m| m.to_s.downcase }
    has_ctrl = mods.intersect?(%w[ctrl control])

    is_up =
      key_down == 'up' ||
      (has_ctrl && key_down == 'p')

    is_down =
      key_down == 'down' ||
      (has_ctrl && key_down == 'n')

    is_page_up =
      %w[page_up pageup].include?(key_str) ||
      (has_ctrl && key_str == 'u')

    is_page_down =
      %w[page_down pagedown].include?(key_str) ||
      (has_ctrl && key_str == 'd')

    case key_down
    when 'f4'
      SoundManager.play(:toggle)
      @test_show_context = !@test_show_context
      return true

    when 'f5'
      SoundManager.play(:toggle)
      @test_timer_paused = !@test_timer_paused
      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return true

    when 'f3'
      SoundManager.play(:toggle)
      if respond_to?(:toggle_handwritten_font_style, true)
        toggle_handwritten_font_style
      elsif respond_to?(:toggle_handwritten_font_style)
        toggle_handwritten_font_style
      end
      return true

    when 'enter', "\r", "\n", 'f2'
      was_already_paused = (@test_timer_paused == true)
      test_toggle_pause unless was_already_paused

      if respond_to?(:handle_table_edit_card, true)
        active_deck = @library.subjects[@current_subject_idx || 0]
                              &.sources&.[](@current_source_idx || 0)
                              &.decks&.[](@current_deck_idx || 0)

        if active_deck
          db_cards_list = active_deck.cards || []

          active_idx = @memory_second_flipped_idx ||
                       @memory_first_flipped_idx ||
                       (@memory_cards.index(@memory_pending_match.first) if @memory_pending_match)
          memory_card = @memory_cards[active_idx] if active_idx

          if memory_card
            current_test_card = @cards_to_test.find do |card|
              card.object_id == memory_card[:id]
            end

            if current_test_card
              db_card_row_idx = db_cards_list.index do |card|
                card.equal?(current_test_card)
              end

              if db_card_row_idx
                simulated_context = {
                  is_edit_action: true,
                  selected_row: db_card_row_idx,
                  cards_list: db_cards_list
                }

                handle_table_edit_card(simulated_context)

                # Herstel Memory-focus na het sluiten van de editor.
                @active_focus       = :study_focus_mode
                @last_focus         = :study_focus_mode
                @current_study_mode = :memory

                # Synchroniseer de aangepaste kaartgegevens.
                current_test_card.term = db_cards_list[db_card_row_idx].term
                current_test_card.meaning = db_cards_list[db_card_row_idx].meaning
              end
            end
          end
        end
      end
      @active_focus       = :study_focus_mode
      @last_focus         = :study_focus_mode
      @current_study_mode = :memory

      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) unless was_already_paused
      test_toggle_pause unless was_already_paused
    end

    # Navigation remains available while the timer is paused.
    max_scroll = @memory_max_scroll.to_i
    page_size = [@memory_visible_rows.to_i, 1].max

    case key_down
    when 'up', 'down', 'p', 'n'
      if is_up
        @memory_scroll_offset = [@memory_scroll_offset - 1, 0].max
        return true
      elsif is_down
        @memory_scroll_offset = [@memory_scroll_offset + 1, max_scroll].min
        return true
      end

    when 'page_up', 'pageup', 'u'
      if is_page_up
        @memory_scroll_offset = [@memory_scroll_offset - page_size, 0].max
        return true
      end

    when 'page_down', 'pagedown', 'd'
      if is_page_down
        @memory_scroll_offset = [@memory_scroll_offset + page_size, max_scroll].min
        return true
      end

    when 'home'
      @memory_scroll_offset = 0
      return true

    when 'end'
      @memory_scroll_offset = max_scroll
      return true
    end

    # Geen kaartselectie tijdens timerpauze.
    return true if @test_timer_paused == true

    # Backspace wist de laatst ingevoerde coördinaatletter.
    if %w[backspace back_space].include?(key_down) || key == "\u007F"
      @memory_input_buffer = @memory_input_buffer[0...-1]
      return true
    end

    # Coördinaatinvoer: alleen bestaande coördinaten accepteren.
    if key_str.match?(/\A[a-zA-Z]\z/)
      candidate = key_str.upcase

      possible = @memory_cards.any? do |card|
        card[:coord].start_with?(candidate)
      end

      if possible
        @memory_input_buffer = candidate
      else
        @memory_input_buffer = ''
        trigger_system_beep if respond_to?(:trigger_system_beep)
      end

      return true
    end

    if key_str.match?(/\A[1-9]\z/)
      candidate = "#{@memory_input_buffer}#{key_str}"

      card_idx = @memory_cards.index do |card|
        card[:coord] == candidate
      end

      if card_idx
        # Scroll automatically to the selected card.
        visible_rows = [@memory_visible_rows.to_i, 1].max
        cards_per_row = [@memory_cards_per_row.to_i, 1].max
        row_idx = card_idx / cards_per_row

        current_offset = @memory_scroll_offset.to_i

        if row_idx < current_offset
          @memory_scroll_offset = (row_idx / visible_rows) * visible_rows
        elsif row_idx >= current_offset + visible_rows
          @memory_scroll_offset = (row_idx / visible_rows) * visible_rows
        end

        @memory_scroll_offset = [
          [@memory_scroll_offset, 0].max,
          @memory_max_scroll.to_i
        ].min

        execute_card_flip(card_idx)
      elsif respond_to?(:trigger_system_beep, true)
        trigger_system_beep
      end

      @memory_input_buffer = ''

      return true
    end

    false
  end

  private

  def memory_column_label(index)
    result = ''
    number = index + 1

    while number > 0
      number -= 1
      result.prepend((97 + (number % 26)).chr)
      number /= 26
    end

    result.upcase
  end

  def update_memory_header(card)
    return unless card

    @memory_header_left_text = card[:content]
    @memory_header_right_text = nil
  end

  def execute_card_flip(idx)
    card = @memory_cards[idx]
    return unless card
    return if card[:matched]

    # Remove a previously found pair when making the next selection.
    if @memory_pending_match
      @memory_pending_match.each do |matched_card|
        @memory_cards.delete(matched_card)
      end

      @memory_pending_match = nil
      @memory_first_flipped_idx = nil
      @memory_second_flipped_idx = nil
      @memory_search_card = nil
      @memory_header_left_text = nil
      @memory_header_right_text = nil

      idx = @memory_cards.index(card)
      return unless idx
    end

    # Sluit een eerder niet-gematcht paar.
    if @memory_second_flipped_idx
      first_card = @memory_cards[@memory_first_flipped_idx]
      second_card = @memory_cards[@memory_second_flipped_idx]

      first_card[:flipped] = false if first_card
      second_card[:flipped] = false if second_card

      @memory_first_flipped_idx = nil
      @memory_second_flipped_idx = nil
      @memory_search_card = nil

    elsif idx == @memory_first_flipped_idx
      return
    end

    card[:flipped] = true
    @memory_message = nil

    if @memory_first_flipped_idx.nil?
      SoundManager.play(:select)
      # Eerste kaart: boodschap links.
      @memory_first_flipped_idx = idx
      @memory_search_card = card
      @memory_header_left_text = card[:content]
      @memory_header_right_text = nil

    else
      # Tweede kaart: boodschap rechts.
      @memory_second_flipped_idx = idx
      @memory_header_right_text = card[:content]

      first_card = @memory_cards[@memory_first_flipped_idx]

      if first_card[:id] == card[:id]
        first_card[:matched] = true
        card[:matched] = true
        SoundManager.play(:right)

        @memory_pending_match = [first_card, card]

        @memory_first_flipped_idx = nil
        @memory_second_flipped_idx = nil

        @memory_message = card[:content]

        if @memory_cards.all? { |c| c[:matched] }
          @memory_pending_match.each do |matched_card|
            @memory_cards.delete(matched_card)
          end

          @memory_pending_match = nil
          @memory_first_flipped_idx = nil
          @memory_second_flipped_idx = nil

          SoundManager.play(:finished)
          @test_finished_waiting = true
        end
      else
        SoundManager.play(:wrong)
      end
    end
  end
end
