module TwoOfAKindInputHandler
  private

  def initialize_two_of_a_kind(cards)
    return false if cards.length < 4

    deck_pairs = cards.flat_map do |card|
      2.times.map do
        {
          id: card.object_id,
          term: card.term.to_s,
          meaning: card.meaning.to_s,
          context: card.context.to_s
        }
      end
    end.shuffle

    @user_hand = []
    @computer_hand = []

    @user_hand << deck_pairs.pop if deck_pairs.any?
    @computer_hand << deck_pairs.pop if deck_pairs.any?

    @two_of_a_kind_computer_questioned_ids = []
    @two_of_a_kind_deck = deck_pairs
    @user_score = 0
    @computer_score = 0
    @user_last_pair_source = nil
    @computer_last_pair_source = nil
    @user_last_pair_until = nil
    @computer_last_pair_until = nil
    @two_of_a_kind_active_player = :user
    @two_of_a_kind_show_start_message = true
    @two_of_a_kind_computer_question = nil
    @two_of_a_kind_waiting_for_answer = false
    @two_of_a_kind_game_over = false
    @user_card_index = 0
    @two_of_a_kind_scroll_y = 0
    @two_of_a_kind_visible_rows = 1
    @two_of_a_kind_draw_animation_until = nil
    @two_of_a_kind_draw_animation_player = nil
    @two_of_a_kind_computer_turn_pending = false
    @two_of_a_kind_pending_refills = []
    @two_of_a_kind_start_action_pending = false

    collect_two_of_a_kind_pairs(@user_hand, :user)
    collect_two_of_a_kind_pairs(@computer_hand, :computer)

    @test_progressbar_total = cards.length
    @test_finished_waiting = false
    @test_timer_paused = false

    @test_drill_elapsed = 0.0
    @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    update_two_of_a_kind_header_and_context
  end

  def update_two_of_a_kind_header_and_context
    selected_card = @user_hand[@user_card_index]

    if selected_card
      @two_of_a_kind_search_card_target = selected_card[:meaning]
      @two_of_a_kind_current_context = selected_card[:context]
    else
      @two_of_a_kind_search_card_target = nil
      @two_of_a_kind_current_context = nil
    end

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    computer_last_pair =
      if @computer_last_pair_until && now < @computer_last_pair_until
        case @computer_last_pair_source
        when :asked then ' (⇄)'
        when :drawn then ' (↓)'
        else ''
        end
      else
        ''
      end

    user_last_pair =
      if @user_last_pair_until && now < @user_last_pair_until
        case @user_last_pair_source
        when :asked then ' (⇄)'
        when :drawn then ' (↓)'
        else ''
        end
      else
        ''
      end

    @two_of_a_kind_header_left_text =
      "⧉:#{@computer_score}#{computer_last_pair}  🂠:#{@computer_hand.length}"

    @two_of_a_kind_header_right_text =
      "⧉:#{@user_score}#{user_last_pair} 🂠:#{@user_hand.length}"
  end

  public

  def handle_two_of_a_kind_input(key, modifiers = [])
    return false unless @current_study_mode == :two_of_a_kind
    return false if @active_focus == :popup

    # Een afgelopen animatie opruimen.
    if @two_of_a_kind_draw_animation_until &&
       !two_of_a_kind_draw_animation_active?
      @two_of_a_kind_draw_animation_until = nil
      @two_of_a_kind_draw_animation_player = nil
    end

    return true if @two_of_a_kind_active_player == :computer &&
                   !@two_of_a_kind_waiting_for_answer

    raw_key_str = key.to_s.sub(/\A:/, '')
    key_str = raw_key_str.downcase

    if key_str == '='
      target_text = nil

      if defined?(@two_of_a_kind_waiting_for_answer) && @two_of_a_kind_waiting_for_answer && @two_of_a_kind_computer_question
        target_text = @two_of_a_kind_computer_question[:term].to_s
      elsif defined?(@user_hand) && defined?(@user_card_index) && @user_hand[@user_card_index]
        current_card = @user_hand[@user_card_index]
        target_text = begin
          current_card[:term].to_s
        rescue StandardError
          current_card.term.to_s
        end
      end

      speak_term(target_text) if target_text
      return true
    end

    normalized_modifiers = modifiers.map(&:to_s).map(&:downcase)

    if %w[enter return].include?(key_str) &&
       normalized_modifiers.include?('shift')
      key_str = 'f2'
    end

    is_enter = ['space', ' ', 'enter', 'return', "\r", "\n"].include?(key_str)
    total_cards = @user_hand.length

    if key_str == 'tab'
      process_two_of_a_kind_user_has_no_card if @two_of_a_kind_waiting_for_answer
      return true
    end

    # Een spelactie die mogelijk een nieuwe kaart trekt,
    # wacht tot de huidige trekanimatie afgelopen is.
    return true if is_enter && two_of_a_kind_draw_animation_active?

    if is_enter
      if @two_of_a_kind_show_start_message
        @two_of_a_kind_show_start_message = false
        @two_of_a_kind_start_action_pending = true
        return true
      end

      @two_of_a_kind_start_action_pending = false if @two_of_a_kind_start_action_pending

      if @two_of_a_kind_waiting_for_answer
        process_two_of_a_kind_computer_question
      else
        execute_two_of_a_kind_ask_turn
      end

      return true
    end

    return true if total_cards.zero? && @two_of_a_kind_waiting_for_answer
    return false if total_cards.zero?

    @two_of_a_kind_scroll_y ||= 0

    has_ctrl = normalized_modifiers.intersect?(%w[ctrl control])
    is_page_up = %w[page_up pageup].include?(key_str) ||
                 (has_ctrl && key_str == 'u')
    is_page_down = %w[page_down pagedown].include?(key_str) ||
                   (has_ctrl && key_str == 'd')

    move_up = %w[left up k].include?(key_str) ||
              (key_str == 'p' && has_ctrl)

    move_down = %w[right down j].include?(key_str) ||
                (key_str == 'n' && has_ctrl)

    case
    when move_up
      @user_card_index = @user_card_index > 0 ? @user_card_index - 1 : total_cards - 1
      ensure_two_of_a_kind_cursor_visible
      update_two_of_a_kind_header_and_context
      return true

    when move_down
      @user_card_index = @user_card_index < total_cards - 1 ? @user_card_index + 1 : 0
      ensure_two_of_a_kind_cursor_visible
      update_two_of_a_kind_header_and_context
      return true

    when key_str == 'home' || raw_key_str == 'g'
      @user_card_index = 0
      ensure_two_of_a_kind_cursor_visible
      update_two_of_a_kind_header_and_context
      return true

    when key_str == 'end' || raw_key_str == 'G'
      @user_card_index = total_cards - 1
      ensure_two_of_a_kind_cursor_visible
      update_two_of_a_kind_header_and_context
      return true

    when %w[page_up pageup page_down pagedown u d].include?(key_str)
      return false if %w[u d].include?(key_str) && !has_ctrl
      return false unless is_page_up || is_page_down

      unless @test_timer_paused == true
        visible_rows = [@two_of_a_kind_visible_rows.to_i, 1].max
        max_offset = [total_cards - visible_rows, 0].max

        current_idx = [[@user_card_index.to_i, 0].max, total_cards - 1].min
        old_offset = [[@two_of_a_kind_scroll_y.to_i, 0].max, max_offset].min

        screen_row = current_idx - old_offset
        screen_row = [[screen_row, 0].max, visible_rows - 1].min

        if is_page_down
          if old_offset >= max_offset
            @user_card_index = total_cards - 1
            @two_of_a_kind_scroll_y = max_offset
          else
            new_offset = old_offset + visible_rows

            if new_offset >= max_offset
              @two_of_a_kind_scroll_y = max_offset
              @user_card_index = total_cards - 1
            else
              @two_of_a_kind_scroll_y = new_offset
              @user_card_index = [[new_offset + screen_row, 0].max, total_cards - 1].min
            end
          end
        elsif old_offset <= 0
          @user_card_index = 0
          @two_of_a_kind_scroll_y = 0
        else
          new_offset = old_offset - visible_rows

          if new_offset <= 0
            @two_of_a_kind_scroll_y = 0
            @user_card_index = 0
          else
            @two_of_a_kind_scroll_y = new_offset
            @user_card_index = [[new_offset + screen_row, 0].max, total_cards - 1].min
          end
        end

        ensure_two_of_a_kind_cursor_visible
        update_two_of_a_kind_header_and_context
      end

      return true
    end

    case key_str
    when 'f2'
      was_already_paused = (@test_timer_paused == true)
      unless was_already_paused
        test_toggle_pause
        @pause_for_card_edit = true
      end

      if respond_to?(:handle_table_edit_card, true)
        s_idx = @current_subject_idx || 0
        src_idx = @current_source_idx || 0
        d_idx = @current_deck_idx || 0
        active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

        if active_deck
          db_cards_list = active_deck.cards || []
          selected_hand_card = @user_hand[@user_card_index]
          current_test_card = if selected_hand_card
                                db_cards_list.find { |card| card.object_id == selected_hand_card[:id] }
                              end

          if current_test_card
            db_card_row_idx = db_cards_list.index { |card| card.equal?(current_test_card) }

            if db_card_row_idx
              if defined?(@table_state) && @table_state && @table_state.respond_to?(:select)
                @table_state.select(db_card_row_idx)
              end

              simulated_context = {
                is_edit_action: true,
                selected_row: db_card_row_idx,
                cards_list: db_cards_list
              }

              handle_table_edit_card(simulated_context)

              if @pause_for_card_edit && @popup&.active?
                @popup.on_close_callback = lambda do
                  if @pause_for_card_edit
                    @pause_for_card_edit = false
                    @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                    test_toggle_pause
                  end
                end
              end

              current_test_card.term = db_cards_list[db_card_row_idx].term
              current_test_card.context = db_cards_list[db_card_row_idx].context
              current_test_card.meaning = db_cards_list[db_card_row_idx].meaning
            end
          end
        end
      end

      @active_focus = :study_focus_mode
      @last_focus = :study_focus_mode
      @current_study_mode = :two_of_a_kind

      unless @pause_for_card_edit && @popup&.active?
        @pause_for_card_edit = false
        @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) unless was_already_paused
        test_toggle_pause unless was_already_paused
      end

      return true

    when 'f3'
      SoundManager.play(:toggle)

      if respond_to?(:toggle_handwritten_font_style, true)
        toggle_handwritten_font_style
      elsif respond_to?(:toggle_handwritten_font_style)
        toggle_handwritten_font_style
      end

      return true

    when 'f5'
      SoundManager.play(:toggle)
      test_toggle_pause if respond_to?(:test_toggle_pause)
      return true

    when 'f4'
      SoundManager.play(:toggle)
      @two_of_a_kind_show_context = !@two_of_a_kind_show_context
      return true
    end

    false
  end

  def queue_two_of_a_kind_empty_hand(hand, player)
    return unless hand.empty?
    return if @two_of_a_kind_deck.empty?

    @two_of_a_kind_pending_refills ||= []
    @two_of_a_kind_pending_refills << player unless
      @two_of_a_kind_pending_refills.include?(player)
  end

  # def log_two_of_a_kind_state(action, details = {})
  # nil unless @current_study_mode == :two_of_a_kind

  # format_hand = lambda do |hand|
  #  hand.map do |card|
  #    "#{card[:term]} [id=#{card[:id]}]"
  #  end
  # end
  #     File.open('two_of_a_kind_debug.log', 'a') do |f|
  #       f.puts
  #       f.puts '=' * 80
  #       f.puts "[#{Time.now.strftime('%H:%M:%S.%L')}] #{action}"
  #       f.puts "BEURT: #{@two_of_a_kind_active_player.inspect}"
  #       f.puts "COMPUTERBEURT_PENDING: #{@two_of_a_kind_computer_turn_pending.inspect}"
  #       f.puts "WACHT OP ANTWOORD: #{@two_of_a_kind_waiting_for_answer.inspect}"
  #       f.puts "ANIMATIE: #{@two_of_a_kind_draw_animation_player.inspect}"
  #       f.puts
  #       f.puts "GEBRUIKER (#{@user_hand.length} kaarten):"
  #       format_hand.call(@user_hand).each { |card| f.puts "  #{card}" }
  #       f.puts
  #       f.puts "COMPUTER (#{@computer_hand.length} kaarten):"
  #       format_hand.call(@computer_hand).each { |card| f.puts "  #{card}" }
  #       f.puts
  #       f.puts "STAPEL: #{@two_of_a_kind_deck.length} kaarten"
  #       f.puts "WACHTRIJ AANVULLINGEN: #{@two_of_a_kind_pending_refills.inspect}"
  #       f.puts "DETAILS: #{details.inspect}"
  #       f.puts '=' * 80
  #     end
  # end

  def execute_two_of_a_kind_ask_turn
    return unless @two_of_a_kind_active_player == :user

    selected_card = @user_hand[@user_card_index]
    return unless selected_card

    SoundManager.play(:select) # the user selects and asks for a card

    match_in_computer_hand = @computer_hand.find do |card|
      card[:id] == selected_card[:id]
    end

    # log_two_of_a_kind_state(
    #  'GEBRUIKER VRAAGT KAART',
    #  selected: selected_card,
    #  match: match_in_computer_hand
    # )
    #

    if match_in_computer_hand
      SoundManager.play(:right) # the computer has the card

      @user_score += 1
      @user_last_pair_source = :asked
      @user_last_pair_until = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3.0
      @user_hand.delete(selected_card)
      @computer_hand.delete(match_in_computer_hand)

      # Beide handen controleren.
      queue_two_of_a_kind_empty_hand(@user_hand, :user)
      queue_two_of_a_kind_empty_hand(@computer_hand, :computer)

      # De gebruiker behoudt zijn beurt.
      @two_of_a_kind_active_player = :user
      @two_of_a_kind_computer_turn_pending = false

      # log_two_of_a_kind_state(
      #  'GEBRUIKER VORMT PAAR',
      #  gevraagd: selected_card,
      #  gevonden: match_in_computer_hand,
      #  paar_voor: :user,
      #  beurt_behouden_door: @two_of_a_kind_active_player
      # )
    else
      # De gebruiker trekt aan het einde van zijn beurt.
      draw_card_and_check_pairs(@user_hand, :user)

      # Als de getrokken kaart een paar vormde en de hand leeg werd,
      # moet de gebruiker opnieuw trekken.
      queue_two_of_a_kind_empty_hand(@user_hand, :user)

      @two_of_a_kind_active_player = :computer
      @two_of_a_kind_computer_turn_pending = true

      # log_two_of_a_kind_state(
      #  'GEBRUIKER VINDT GEEN PAAR',
      #  gevraagd: selected_card,
      #  beurt_behouden_door: @two_of_a_kind_active_player
      # )
    end

    @user_card_index = [
      @user_card_index,
      [@user_hand.length - 1, 0].max
    ].min

    ensure_two_of_a_kind_cursor_visible
    update_two_of_a_kind_header_and_context
    check_two_of_a_kind_game_over
  end

  def replenish_empty_two_of_a_kind_hand(hand, player)
    return false unless hand.empty?
    return false if @two_of_a_kind_deck.empty?

    draw_card_and_check_pairs(hand, player)
    true
  end

  def draw_card_and_check_pairs(hand, player)
    return 0 if @two_of_a_kind_deck.empty?

    drawn_card = @two_of_a_kind_deck.pop

    # log_two_of_a_kind_state(
    #  'KAART WORDT GETROKKEN',
    #  speler: player,
    #  kaart: drawn_card
    # )

    # start_two_of_a_kind_draw_animation(player)
    sleep(0.25)
    SoundManager.play(:draw_card)
    sleep(0.5)

    hand << drawn_card

    pairs_found = collect_two_of_a_kind_pairs(hand, player, source: :drawn)

    # log_two_of_a_kind_state(
    #  'NA TREKKING EN PAARCONTROLE',
    #  speler: player,
    #  getrokken_kaart: drawn_card,
    #  paren_gevormd: pairs_found
    # )

    pairs_found
  end

  def collect_two_of_a_kind_pairs(hand, player, source: nil)
    score_variable = player == :user ? :@user_score : :@computer_score
    score = instance_variable_get(score_variable)

    pairs_found = 0

    loop do
      pair = hand.group_by { |card| card[:id] }
                 .find { |_id, cards| cards.length >= 2 }

      break unless pair

      cards = pair[1].first(2)
      cards.each { |card| hand.delete(card) }

      score += 1
      pairs_found += 1

      sleep(0.5)
      SoundManager.play(:right) # match from drawn card
      sleep(0.5)
    end

    instance_variable_set(score_variable, score)

    # Alleen bijwerken als er daadwerkelijk een paar is gevormd.
    if pairs_found.positive? && source
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if player == :user
        @user_last_pair_source = source
        @user_last_pair_until = now + 3.0
      else
        @computer_last_pair_source = source
        @computer_last_pair_until = now + 3.0
      end
    end

    pairs_found
  end

  def execute_two_of_a_kind_computer_turn
    return if @two_of_a_kind_game_over
    return if @two_of_a_kind_waiting_for_answer

    @two_of_a_kind_computer_turn_pending = false
    @two_of_a_kind_active_player = :computer

    # Geen kaarten meer betekent dat de computer niet kan vragen.
    # Er wordt hier niet aan het begin van de beurt getrokken.
    if @computer_hand.empty?
      @two_of_a_kind_active_player = :user

      update_two_of_a_kind_header_and_context
      check_two_of_a_kind_game_over
      return
    end

    # De computer vraagt een kaart uit zijn eigen hand.
    chosen_card = @computer_hand.sample

    # log_two_of_a_kind_state(
    #  'COMPUTER VRAAGT KAART',
    #  gevraagd: chosen_card
    # )

    @two_of_a_kind_computer_question = chosen_card

    SoundManager.play(:select) # the computer selects and asks for a card
    sleep(0.5)

    @two_of_a_kind_waiting_for_answer = true

    update_two_of_a_kind_header_and_context
  end

  def process_two_of_a_kind_computer_question
    return unless @two_of_a_kind_waiting_for_answer

    computer_question = @two_of_a_kind_computer_question
    return unless computer_question

    if @user_hand.empty?
      process_two_of_a_kind_user_has_no_card
      return
    end

    selected_card = @user_hand[@user_card_index]
    return unless selected_card

    if selected_card[:id] == computer_question[:id]
      SoundManager.play(:right) # the user has the card
      sleep(1)

      @computer_score += 1
      @computer_last_pair_source = :asked
      @computer_last_pair_until = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3.0
      @user_hand.delete(selected_card)
      @computer_hand.delete(computer_question)

      # Beide handen controleren, niet alleen die van de computer.
      queue_two_of_a_kind_empty_hand(@user_hand, :user)
      queue_two_of_a_kind_empty_hand(@computer_hand, :computer)

      @two_of_a_kind_active_player = :computer
      @two_of_a_kind_waiting_for_answer = false
      @two_of_a_kind_computer_question = nil

      @two_of_a_kind_computer_turn_pending = true

      @user_card_index = [
        @user_card_index,
        [@user_hand.length - 1, 0].max
      ].min

      ensure_two_of_a_kind_cursor_visible
      update_two_of_a_kind_header_and_context
      check_two_of_a_kind_game_over
      return
    end

    trigger_system_beep # de gebruiker drukt op <enter> maar moet op tab drukken als hij de gevraagde kaart niet heeft

    @two_of_a_kind_waiting_for_answer = true

    update_two_of_a_kind_header_and_context
  end

  # process_two_of_a_kind_user_has_no_card wordt aangeroepen tijdens de computerbeurt,
  # nadat de gebruiker heeft aangegeven dat hij de gevraagde kaart niet heeft.
  def process_two_of_a_kind_user_has_no_card
    return unless @two_of_a_kind_waiting_for_answer

    computer_question = @two_of_a_kind_computer_question
    return unless computer_question

    settings = AppConfig.settings

    matching_card = @user_hand.find do |card|
      card[:id] == computer_question[:id]
    end

    if matching_card
      trigger_system_beep # gebruiker heeft de gevraagde kaart, maar ziet het over het hoofd

      @status_message =
        "#{settings.language_string(:statusbar_study_two_of_a_kind_warning)}!"

      update_two_of_a_kind_header_and_context
      return
    end

    @two_of_a_kind_waiting_for_answer = false
    @two_of_a_kind_computer_question = nil

    # De computer trekt aan het einde van zijn beurt.
    draw_card_and_check_pairs(@computer_hand, :computer)

    # Als daardoor zijn hand leeg wordt, komt hij opnieuw in de wachtrij.
    queue_two_of_a_kind_empty_hand(@computer_hand, :computer)

    @two_of_a_kind_active_player = :user

    update_two_of_a_kind_header_and_context
    check_two_of_a_kind_game_over
  end

  def start_two_of_a_kind_draw_animation(player)
    duration = 0.8

    @two_of_a_kind_draw_animation_until =
      Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration

    @two_of_a_kind_draw_animation_player = player
  end

  def check_two_of_a_kind_game_over
    return false if @two_of_a_kind_game_over

    return false unless @two_of_a_kind_deck.empty? &&
                        @user_hand.empty? &&
                        @computer_hand.empty?

    @two_of_a_kind_game_over = true
    @two_of_a_kind_computer_turn_pending = false
    @two_of_a_kind_waiting_for_answer = false
    @test_finished_waiting = true

    update_two_of_a_kind_header_and_context

    true
  end
end
