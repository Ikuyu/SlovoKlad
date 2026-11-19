module TestInputHandler
  def test_toggle_pause
    if @test_timer_paused == true
      # Hervatten: we updaten alleen de laatste tick-tijd naar NU, zodat de klok vanaf nu weer meet
      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @test_timer_paused = false
    else
      # Pauzeren: we zetten de vlag omhoog. Er wordt nu nergens meer iets berekend!
      @test_timer_paused = true
    end
  end

  private

  def test_finished
    return unless respond_to?(:trigger_statusbar_message)

    trigger_statusbar_message(
      "#{AppConfig.settings.language_string(:study_test_passed)}: #{AppConfig.settings.language_string(:study_test_completed_on_time)}!",
      type: :info,
      beep: false,
      expires: false
    )
  end

  def exit_test_study_session
    # 1. Ruim alle sessie-arrays rigoureus op
    @cards_to_test            = nil
    @test_current_idx         = nil
    @test_show_meaning        = nil
    @test_timer_paused        = nil
    @test_pause_timestamp     = nil
    @test_session_start_time  = nil
    @test_fixed_time_limit    = nil
    @test_progressbar_total   = nil
    @test_awaiting_difficulty = nil
    @test_last_deleted_card   = nil
    @test_card_directions     = nil
    # @test_show_context        = nil

    @drill_viewport_start     = nil if instance_variable_defined?(:@drill_viewport_start)
    @test_drill_timed         = nil if instance_variable_defined?(:@test_drill_timed)
    @test_drill_elapsed       = nil if instance_variable_defined?(:@test_drill_elapsed)

    @test_time_was_up_notified = nil
    @test_time_up_drawn        = nil
    @test_finished_waiting     = nil
    @test_finished_drawn       = nil

    @test_time_left            = nil
    @test_last_tick_time       = nil
    @test_paused_elapsed       = nil if instance_variable_defined?(:@test_paused_elapsed)

    # 1b. MEMORY-SESSIE VOLLEDIG OPRUIMEN
    @memory_cards              = nil
    @memory_scroll_offset      = 0
    @memory_max_scroll         = 0
    @memory_total_rows         = 0
    @memory_visible_rows       = 0
    @memory_input_buffer       = ''

    @memory_first_flipped_idx  = nil
    @memory_second_flipped_idx = nil

    # 1c. MULTIPLE CHOICE-SESSIE VOLLEDIG OPRUIMEN
    @test_mc_answered            = nil
    @test_mc_options             = nil
    @test_mc_correct_answer      = nil
    @test_mc_current_card_anchor = nil
    @test_selected_option_idx    = nil

    # 2. Bereken de échte, loepzuivere herkomst vòòr het studie-avontuur
    target_origin_pane = defined?(@menu_origin_focus) && @menu_origin_focus ? @menu_origin_focus : nil
    target_origin_pane ||= defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree
    target_origin_pane = :tree if %i[menu popup command_mode study_focus_mode].include?(target_origin_pane)

    @active_focus = target_origin_pane
    @last_focus   = target_origin_pane

    # 3. 🧹 ATOOM-STATUSBALK SANERING: Dwing de transformatie naar de normale statusmode!
    @command_mode_visible = false
    if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.clear if @statusbar_field.respond_to?(:clear)
      @statusbar_field.text = ''
      @statusbar_field.is_focused = false
      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)
    end

    @status_message = nil if instance_variable_defined?(:@status_message)
    @status_message_expires_at = nil if instance_variable_defined?(:@status_message_expires_at)

    # 4. Dwing de cockpit tot een realtime herberekening en refresh
    @tree.refresh_nodes if @tree && @tree.respond_to?(:refresh_nodes)
    @table_changed = true if instance_variable_defined?(:@table_changed)

    @current_study_mode = nil
  end

  # =========================================================================
  # ⏱️ UNIVERSELE TIMER-TICK ENGINE
  # =========================================================================
  def handle_test_timer_tick
    return if @cards_to_test.nil? || @cards_to_test.empty?
    return if @test_finished_waiting == true

    current_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Bij pauze of een geopend popupvenster loopt de tijd niet door.
    popup_is_open = defined?(@popup) && @popup &&
                    @popup.respond_to?(:active?) && @popup.active?

    if @test_timer_paused == true || popup_is_open
      @test_last_tick_time = current_time
      return
    end

    @test_last_tick_time ||= current_time
    elapsed_delta = current_time - @test_last_tick_time
    @test_last_tick_time = current_time

    return unless elapsed_delta.positive?

    if @drill_timer_zero_pending == true
      if current_time - (@drill_timer_zero_at || current_time) >= 1.0
        @drill_timer_zero_pending = false

        # Antwoord was één seconde zichtbaar.
        # Ga naar de volgende kaart en verberg het antwoord.
        move_drill_cursor(1, @cards_to_test.length)
        @test_show_meaning = false

        # Nieuwe countdown starten.
        @test_time_left = @test_drill_timer_max.to_i
        @test_last_tick_time = current_time

        @table_changed = true
      end

      return
    end

    case @current_study_mode

    when :drill, :memory, :two_of_a_kind
      @test_drill_elapsed ||= 0.0
      @test_drill_elapsed += elapsed_delta

      if @current_study_mode == :drill &&
         @test_drill_timed == true

        @test_time_left = @test_time_left.to_f - elapsed_delta

        if @test_time_left <= 0
          @test_time_left = 0

          # Bij nul het antwoord tonen.
          @test_show_meaning = true
          SoundManager.play(:select)

          # Eén seconde wachten voordat de volgende kaart komt.
          @drill_timer_zero_pending = true
          @drill_timer_zero_at = current_time

          @table_changed = true
          nil
        end
      end

    when :quiz, :multiple_choice
      # Quiz en Multiple Choice tellen af.
      unless @test_time_left.nil?
        @test_time_left = [@test_time_left.to_f - elapsed_delta, 0].max

        if @test_time_left <= 0 && !@test_time_was_up_notified
          if respond_to?(:trigger_statusbar_message)
            trigger_statusbar_message(
              "#{AppConfig.settings.language_string(:study_test_failed)}: " \
              "#{AppConfig.settings.language_string(:study_test_time_up)}!",
              type: :error,
              beep: false,
              expires: false
            )
          end

          SoundManager.play(:failed)
          @test_time_was_up_notified = true
          @test_finished_waiting = true
          @table_changed = true
          return
        end
      end

      # Quiz: na het tonen van het antwoord na één seconde verdergaan.
      if @current_study_mode == :quiz &&
         @test_show_meaning == true &&
         @quiz_meaning_shown_at &&
         (current_time - @quiz_meaning_shown_at) >= 1.0

        @quiz_meaning_shown_at = nil
        remove_current_quiz_card(exclude: false)
        return
      end

      # Multiple Choice: na beantwoorden na één seconde verdergaan.
      if @current_study_mode == :multiple_choice &&
         @test_mc_answered == true &&
         @test_mc_answered_at &&
         (current_time - @test_mc_answered_at) >= 1.0

        move_to_next_multiple_choice_card(mark_as_learned: false)
        nil
      end
    end
  end
end
