# frozen_string_literal: true

require_relative 'test_input_handler'

module QuizInputHandler
  include TestInputHandler
  include FontStyleHelper

  def handle_quiz_input(key, modifiers = [])
    raw_key_str = key.to_s.sub(/\A:/, '')
    key_str     = raw_key_str.downcase

    # =========================================================================
    # 🎯 STANDAARD AFSLUITER
    # =========================================================================
    if (defined?(@test_time_was_up_notified) && @test_time_was_up_notified == true) ||
       (defined?(@test_finished_waiting) && @test_finished_waiting == true)

      exit_test_study_session
      return true
    end

    return false if @cards_to_test.nil? || @cards_to_test.empty?

    @test_current_idx ||= 0
    @test_current_idx = [[@test_current_idx, 0].max, @cards_to_test.length - 1].min

    # =========================================================================
    # 📑 OVERIGE TOETSEN (Space & Edit via Enter)
    # =========================================================================
    case key_str
    when '='
      current_test_card = @cards_to_test[@test_current_idx]
      speak_term(current_test_card&.term) if current_test_card
      return true

    # =========================================================================
    # 📑 TOETS: TAB (Overslaan / Markeren als gekend via object_id)
    # =========================================================================
    when 'tab', :tab
      current_test_card = @cards_to_test[@test_current_idx]

      if current_test_card
        active_deck = current_quiz_active_deck

        if active_deck
          db_cards_list = active_deck.cards || []
          # 🎯 IDENTITY MATCH FIX:
          db_card_row_idx = quiz_card_row_index(db_cards_list, current_test_card)

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

      remove_current_quiz_card(exclude: true)
      return true

    when 'space', ' ', 'enter', 'return', "\r", "\n"
      return true if defined?(@test_timer_paused) && @test_timer_paused == true

      unless @test_show_meaning
        @test_show_meaning = true
        SoundManager.play(:select)
        @quiz_meaning_shown_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      return true

    when 'f5'
      SoundManager.play(:toggle)
      test_toggle_pause
      return true

    when 'f4'
      SoundManager.play(:toggle)
      @test_show_context = !(@test_show_context || false)
      return true

    when 'f3'
      SoundManager.play(:toggle)
      if respond_to?(:toggle_handwritten_font_style, true)
        toggle_handwritten_font_style
      elsif respond_to?(:toggle_handwritten_font_style)
        toggle_handwritten_font_style
      end
      return true

    when 'f2'
      was_already_paused = (@test_timer_paused == true)
      test_toggle_pause unless was_already_paused

      if respond_to?(:handle_table_edit_card, true)
        active_deck = current_quiz_active_deck

        if active_deck
          db_cards_list = active_deck.cards || []
          @test_current_idx ||= 0
          current_test_card = @cards_to_test[@test_current_idx]

          if current_test_card
            # 🎯 IDENTITY MATCH FIX:
            db_card_row_idx = quiz_card_row_index(db_cards_list, current_test_card)
            if db_card_row_idx
              if defined?(@table_state) && @table_state && @table_state.respond_to?(:select)
                @table_state.select(db_card_row_idx)
              end
              simulated_context = { is_edit_action: true, selected_row: db_card_row_idx, cards_list: db_cards_list }
              handle_table_edit_card(simulated_context)

              sync_quiz_card_fields(current_test_card, db_cards_list[db_card_row_idx])
            end
          end
        end
      end

      @active_focus             = :study_focus_mode
      @last_focus               = :study_focus_mode
      @current_study_mode       = :quiz

      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) unless was_already_paused
      test_toggle_pause unless was_already_paused

      return true
    end

    false
  end

  private

  # Werkt de bewerkbare velden van de quizkaart bij na het aanpassen van de databasekaart.
  def sync_quiz_card_fields(quiz_card, db_card)
    quiz_card.term    = db_card.term
    quiz_card.context = db_card.context
    quiz_card.meaning = db_card.meaning
  end

  # Zoekt de quizkaart op objectidentiteit in de kaarten van het actieve deck.
  def quiz_card_row_index(cards, quiz_card)
    cards.index { |card| card.equal?(quiz_card) }
  end

  # Return the deck associated with the current selection.
  def current_quiz_active_deck
    s_idx   = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx   = @current_deck_idx || 0
    @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
  end

  # Remove the current quiz card and update progress.
  # Geeft true terug als de quiz hierdoor eindigt.
  # Remove the current quiz card and update progress.
  # Geeft true terug als de quiz hierdoor eindigt.
  def remove_current_quiz_card(exclude: false)
    @test_last_deleted_card = @cards_to_test[@test_current_idx]
    @cards_to_test.delete_at(@test_current_idx)
    @test_card_directions.delete_at(@test_current_idx) if defined?(@test_card_directions) && @test_card_directions

    if @cards_to_test.empty?
      @test_excluded_count = @test_progressbar_total
      test_finished
      SoundManager.play(:finished)
      @test_finished_waiting = true
      return true
    end

    # Speel het juiste geluid af op basis van het exclude-argument
    SoundManager.play(exclude ? :exclude : :next)

    @test_current_idx = @cards_to_test.length - 1 if @test_current_idx >= @cards_to_test.length
    @test_show_meaning = false
    false
  end
end
