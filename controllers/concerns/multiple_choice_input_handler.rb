# frozen_string_literal: true

require_relative 'test_input_handler'

module MultipleChoiceInputHandler
  include TestInputHandler
  include FontStyleHelper

  def handle_multiple_choice_input(key, modifiers = [])
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

    # Initialiseer de 4 opties stabiel voor deze kaart
    @test_mc_answered ||= false

    # =========================================================================
    # 📑 ANTWOORD-INPUT: Toetsen 1 t/m 4 om een optie te kiezen
    # =========================================================================
    if %w[1 2 3 4].include?(key_str) && !@test_mc_answered
      return true if defined?(@test_timer_paused) && @test_timer_paused == true

      @test_selected_option_idx = key_str.to_i - 1
      @test_mc_answered = true
      @test_mc_answered_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      chosen_text = @test_mc_options[@test_selected_option_idx]

      if chosen_text == @test_mc_correct_answer
        SoundManager.play(:right)
      else
        SoundManager.play(:wrong)
      end

      return true
    end

    # =========================================================================
    # 📑 OVERIGE TOETSEN (Spatiebalk & Edit)
    # =========================================================================
    case key_str
    when '='
      current_test_card = @cards_to_test[@test_current_idx]
      speak_term(current_test_card&.term) if current_test_card
      return true

    when 'tab', :tab
      current_test_card = @cards_to_test[@test_current_idx]

      if current_test_card
        s_idx   = @current_subject_idx || 0
        src_idx = @current_source_idx || 0
        d_idx   = @current_deck_idx || 0
        active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

        if active_deck
          db_cards_list = active_deck.cards || []
          # 🎯 IDENTITY MATCH FIX:
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

      move_to_next_multiple_choice_card(mark_as_learned: false, play_exclude_sound: true)
      return true

    when 'space', ' ', 'enter', 'return', "\r", "\n"

      return true if defined?(@test_timer_paused) && @test_timer_paused == true

      if @test_mc_answered
        # Space advances to the next card without marking it as learned.
        move_to_next_multiple_choice_card(mark_as_learned: false, play_exclude_sound: false)
      else
        trigger_system_beep
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
        s_idx   = @current_subject_idx || 0
        src_idx = @current_source_idx || 0
        d_idx   = @current_deck_idx || 0
        active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

        if active_deck
          db_cards_list = active_deck.cards || []
          @test_current_idx ||= 0
          current_test_card = @cards_to_test[@test_current_idx]

          if current_test_card
            # 🎯 IDENTITY MATCH FIX:
            db_card_row_idx = db_cards_list.index { |card| card.equal?(current_test_card) }
            if db_card_row_idx
              if defined?(@table_state) && @table_state && @table_state.respond_to?(:select)
                @table_state.select(db_card_row_idx)
              end
              simulated_context = { is_edit_action: true, selected_row: db_card_row_idx, cards_list: db_cards_list }
              handle_table_edit_card(simulated_context)

              current_test_card.term    = db_cards_list[db_card_row_idx].term
              current_test_card.context = db_cards_list[db_card_row_idx].context
              current_test_card.meaning = db_cards_list[db_card_row_idx].meaning
            end
          end
        end
      end

      @active_focus             = :study_focus_mode
      @last_focus               = :study_focus_mode
      @current_study_mode       = :multiple_choice

      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) unless was_already_paused
      test_toggle_pause unless was_already_paused

      return true
    end

    false
  end

  private

  # =========================================================================
  # 🎲 JOUW ONWRIKKBARE OPTIE GENERATOR (RICHTING MATRIX VOLLEDIG GESPIEGELD)
  # =========================================================================
  def initialize_multiple_choice_options
    return if defined?(@test_mc_current_card_anchor) && @test_mc_current_card_anchor == @test_current_idx

    current_card = @cards_to_test[@test_current_idx]
    return unless current_card

    # 🎯 DYNAMIC COCKPIT SYNC: We kijken naar de specifieke richting van DEZE kaart!
    # Dit ondersteunt feilloos fronts, backs én de afwisselende (alternating) modus.
    current_direction = defined?(@test_card_directions) && @test_card_directions ? @test_card_directions[@test_current_idx] : :front
    is_question_a_term = (current_direction == :front)

    @test_mc_correct_answer = if is_question_a_term
                                # Vraag = Term -> Opties MOETEN Meanings zijn!
                                current_card.meaning.to_s
                              else
                                # Vraag = Meaning -> Opties MOETEN Terms zijn!
                                current_card.term.to_s
                              end

    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
    all_cards = active_deck ? (active_deck.cards || []) : []

    # 🎯 DYNAMIC EXTRACTIE: Trek de pool ALTIJD uit de tegenovergestelde kolom van de actieve vraag!
    pool = all_cards.map do |c|
      is_question_a_term ? c.meaning.to_s : c.term.to_s
    end.uniq

    # Haal het juiste antwoord gegarandeerd uit de foute-opties pool
    pool.delete(@test_mc_correct_answer.to_s)

    # Kies 3 willekeurige foute afleiders uit de JUISTE kolom
    distractors = pool.sample(3)
    distractors << '' while distractors.length < 3

    # Voeg het onfeilbare juiste antwoord samen met de 3 afleiders en hussel ze grondig
    @test_mc_options = (distractors + [@test_mc_correct_answer]).shuffle
    @test_mc_current_card_anchor = @test_current_idx
    @test_selected_option_idx = nil
  end

  def move_to_next_multiple_choice_card(mark_as_learned: false, play_exclude_sound: false)
    current_test_card = @cards_to_test[@test_current_idx]

    if mark_as_learned && current_test_card
      s_idx = @current_subject_idx || 0
      src_idx = @current_source_idx || 0
      d_idx = @current_deck_idx || 0
      active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
      if active_deck
        db_cards = active_deck.cards || []
        # 🎯 IDENTITY MATCH FIX:
        row_idx = db_cards.index { |c| c.equal?(current_test_card) }
        if row_idx
          db_cards[row_idx].study = false
          @library_dirty = true
        end
      end
    end

    @test_last_deleted_card = @cards_to_test[@test_current_idx]
    @cards_to_test.delete_at(@test_current_idx)
    @test_card_directions.delete_at(@test_current_idx) if defined?(@test_card_directions) && @test_card_directions

    if @cards_to_test.empty?
      @test_excluded_count = @test_progressbar_total
      test_finished if respond_to?(:test_finished)
      SoundManager.play(:finished) # 🏁 Alleen finished klinkt bij de laatste kaart!
      @test_finished_waiting = true
      return
    end

    # Play exclude als er op tab werd gedrukt
    SoundManager.play(:exclude) if play_exclude_sound && !mark_as_learned

    # Correct the cursor and reset the interface for the next card.
    @test_current_idx = @cards_to_test.length - 1 if @test_current_idx >= @cards_to_test.length
    @test_mc_answered = false
    @test_mc_current_card_anchor = nil

    # Bereid de opties voor de volgende kaart voor
    initialize_multiple_choice_options if respond_to?(:initialize_multiple_choice_options, true)
  end
end
