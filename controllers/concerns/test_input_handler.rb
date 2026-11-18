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
    # De poortwachters blijven intact om onnodige berekeningen te blokkeren
    return if defined?(@test_timer_paused) && @test_timer_paused == true
    return if defined?(@test_finished_waiting) && @test_finished_waiting == true
    return if @cards_to_test.nil? || @cards_to_test.empty?

    current_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # Meerkeuze: ga 3 seconden na het beantwoorden automatisch verder.
    if @current_study_mode == :multiple_choice &&
       @test_mc_answered == true &&
       @test_mc_answered_at
      move_to_next_multiple_choice_card(mark_as_learned: false) if current_time - @test_mc_answered_at >= 1.0
      return
    end

    # We voeren de berekening alleen uit als Drill, play memory of two of a kind actief is
    return unless defined?(@current_study_mode) &&
                  %i[drill memory two_of_a_kind].include?(@current_study_mode)

    # We voeren de berekening alleen nog uit als de Drill-modus actief is
    return unless defined?(@current_study_mode) && %i[drill memory two_of_a_kind].include?(@current_study_mode)

    @test_last_tick_time ||= current_time

    # Bereken exact hoeveel hele seconden er verstreken zijn
    elapsed_seconds = (current_time - @test_last_tick_time).to_i
    return unless elapsed_seconds >= 1

    @test_time_left ||= 0

    if @current_study_mode == :drill && defined?(@test_drill_timed) && @test_drill_timed == true
      # TIMED DRILL STAND: Wekker telt af tot 0 voor automatische reveal
      unless @test_show_meaning
        @test_time_left -= elapsed_seconds

        if @test_time_left <= 0
          @test_time_left = 0
          @test_show_meaning = true

          @table_changed = true if instance_variable_defined?(:@table_changed)
        end
      end
    else
      # Drill, Memory én Two of a Kind tellen lineair omhoog
      @test_time_left += elapsed_seconds
    end

    # Zet het anker vast voor de volgende stap
    @test_last_tick_time = current_time
  end
end
