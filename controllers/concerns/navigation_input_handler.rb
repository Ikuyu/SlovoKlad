module NavigationInputHandler
  private

  def activate_menu_focus
    @active_focus = :menu
    @active_menu_idx = 0 # Forceer highlight direct op het eerste item (app_name)
    @active_submenu_idx = 0
    @menu_dropdown_open = false
  end

  def handle_navigation_input(key, modifiers = [])
    # Tijdens een actieve studie F3 toestaan voor de handwritten-stijl
    if @active_focus == :study_focus_mode
      if key.to_s.downcase == 'f3'
        toggle_handwritten_font_style
        return true
      end

      return false
    end

    # has_alt = modifiers.include?('alt') || modifiers.include?('meta') || modifiers.include?('option')
    has_ctrl = modifiers.include?('ctrl') || modifiers.include?('control')
    # has_shift = modifiers.include?('shift')

    # 🎯 ENCAPSULATED COUPLING: Route directly into the clean clipboard engine
    return true if handle_flashcard_clipboard_operations(key, has_ctrl)

    is_replace_active =
      @interactively_replacing == true ||
      @active_focus == :replace_mode

    is_deck_active = tree_deck_active?

    focus_before_switch = @active_focus

    consumed = handle_primary_navigation_key(
      key,
      is_replace_active,
      is_deck_active
    )

    # 👉 STAP 2: DE DEFINITIEVE RESET TRIGGER!
    # Als de toets is geconsumeerd én de focus is daadwerkelijk veranderd,
    # dan dwingen we de applicatie om de selecties te wissen en te hertekenen!
    if consumed && @active_focus != focus_before_switch
      # =========================================================================
      # 🌲 JOUW LIFECYCLE INTERCEPTOR
      # 👉 IMPORTANT: Clear all asterisks whenever panels are switched manually.
      # =========================================================================
      if respond_to?(:exit_global_search_mode, true) && %i[tree table menu command_mode].include?(@active_focus)
        exit_global_search_mode
      end

      finalize_navigation_switch(focus_before_switch) if respond_to?(:finalize_navigation_switch, true)
    end

    consumed
  end

  # =========================================================================
  # 📋 UNIVERSAL FLASHCARD CLIPBOARD OPERATIONS ENGINE
  # 👉 Handles bulk copying from tables and isolated pasting into decks.
  # =========================================================================
  def handle_flashcard_clipboard_operations(key, has_ctrl)
    return false unless has_ctrl

    key_char = key.to_s.strip.downcase
    return false unless %w[c v].include?(key_char)

    if key_char == 'c' && @active_focus == :table
      execute_flashcard_table_copy
    elsif key_char == 'v'
      execute_flashcard_deck_paste
    else
      false
    end
  end

  def execute_flashcard_table_copy
    cards = active_cards_for_table
    return true if cards.empty?

    # 🔍 DYNAMISCHE POOL-TRACKING:
    # We kijken of er bulk-gemarkeerde rijen zijn.
    # If the array is empty or nil, use the active cursor index.
    selected_indices = if defined?(@selected_table_rows) && @selected_table_rows && @selected_table_rows.any?
                         @selected_table_rows.map(&:to_i)
                       elsif @table_state && @table_state.respond_to?(:selected) && @table_state.selected
                         [@table_state.selected.to_i]
                       else
                         []
                       end

    # Sanitize the indices by making them unique and keeping them within the deck bounds.
    selected_indices = selected_indices.compact.uniq.select { |idx| idx >= 0 && idx < cards.length }
    return true if selected_indices.empty?

    selected_cards = selected_indices.map { |idx| cards[idx] }.compact
    return true if selected_cards.empty?

    # Deep-copy de kaarten via Marshal om de geheugenreferenties volledig los te koppelen
    @copied_cards_buffer = Marshal.load(Marshal.dump(selected_cards))

    true
  end

  def execute_flashcard_deck_paste
    # 🔒 STRIC STRUCTURAL BOUNDARY GUARD
    # Validate the absolute directory level depth of your current tree node:
    # A path size of exactly 3 explicitly matches an isolated deck object.
    is_deck_focused = @tree && @tree.selected_path && @tree.selected_path.size == 3

    unless is_deck_focused
      trigger_system_beep
      return true
    end

    if defined?(@copied_cards_buffer) && @copied_cards_buffer && @copied_cards_buffer.any?
      # 🔍 TARGET EXTRACTION MATRIX:
      # Instead of using the static cockpit indexes, we extract the target deck
      # directly from the active visual tree path IDs. This guarantees it pastes
      # onto whatever row your cursor highlight bar is resting on right now!
      path = @tree.selected_path
      active_target_deck = nil

      if @library && @library.subjects
        target_sub = @library.subjects.find { |s| s.id.to_s == path[0].to_s }
        target_src = target_sub&.sources&.find { |src| src.id.to_s == path[1].to_s }
        active_target_deck = target_src&.decks&.find { |d| d.id.to_s == path[2].to_s }
      end

      if active_target_deck
        # Create unique duplicated copies via Marshal to sever memory references
        fresh_duplicates = Marshal.load(Marshal.dump(@copied_cards_buffer))

        active_target_deck.cards ||= []
        fresh_duplicates.each { |card| active_target_deck.cards << card }

        @library_dirty = true

        # Force synchronize the app's internal database loop indices
        # to point directly onto this deck now that it's modified
        if @library && @library.subjects
          s_idx = @library.subjects.index(target_sub) || 0
          src_idx = target_sub.sources.index(target_src) || 0
          d_idx = target_src.decks.index(active_target_deck) || 0

          @current_subject_idx = s_idx
          @current_source_idx  = src_idx
          @current_deck_idx    = d_idx
        end

        # VISUAL CURSOR AND VIEWPORT ALIGNMENT
        new_total_cards = active_target_deck.cards.length
        new_last_index  = [new_total_cards - 1, 0].max

        # Move the data grid cursor down onto the absolute bottom card row
        @table_state.select(new_last_index) if @table_state && @table_state.respond_to?(:select)

        # Force the table layout viewport viewport offset down smoothly
        visible_height = defined?(@table_visible_height) && @table_visible_height.to_i > 0 ? @table_visible_height.to_i : 10
        calculated_offset = [new_total_cards - visible_height, 0].max

        if respond_to?(:set_table_viewport_offset, true)
          set_table_viewport_offset(calculated_offset)
        elsif defined?(@table_viewport_offset)
          @table_viewport_offset = calculated_offset
        end

        # Force a UI repaint across the whole terminal board
        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      end
    end
    true
  end

  def toggle_handwritten_font_style
    return if defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    settings = AppConfig.settings
    active_card_lang = nil

    # 🔍 DYNAMIC LIFECYCLE DETECTION
    if defined?(@current_study_mode) && @current_study_mode && defined?(@cards_to_test) && @cards_to_test
      current_card = @cards_to_test[@test_current_idx]
      active_card_lang = current_card.respond_to?(:language) ? current_card.language : nil
    elsif @active_focus == :table && defined?(@library)
      s_idx = @current_subject_idx || 0
      src_idx = @current_source_idx || 0
      d_idx = @current_deck_idx || 0
      active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
      active_card_lang = active_deck.respond_to?(:language) ? active_deck.language : nil
    end

    # 🎯 DE GLOBALISERING: Fallback instantly onto your main interface language code
    # (:en, :nl, :fr, :de) instead of hardcoding any specific language block!
    active_card_lang ||= settings.language || :en
    active_lang_sym = active_card_lang.to_s.gsub(/\A:/, '').to_sym

    # Toggle the active state register inside your volatile Hash.new(false) memory bank
    SoundManager.play(:toggle)
    settings.toggle_handwritten(active_lang_sym)

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def handle_primary_navigation_key(key, is_replace_active, is_deck_active)
    case key

    when '?'
      open_help_popup
      true

    when ':'
      @statusbar_saved_tree_selection_backup = defined?(@selected_tree_paths) && @selected_tree_paths ? @selected_tree_paths.dup : nil
      @statusbar_saved_table_selection_backup = defined?(@selected_table_rows) && @selected_table_rows ? @selected_table_rows.dup : nil

      @statusbar_saved_tree_selection ||= @statusbar_saved_tree_selection_backup
      @statusbar_saved_table_selection ||= @statusbar_saved_table_selection_backup

      @menu_origin_focus = @active_focus
      @active_focus = :command_mode
      @command_mode_visible = true

      if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.clear if @statusbar_field.respond_to?(:clear)
        @statusbar_field.is_focused = true
      end
      true

    when 't'
      if %i[tree table].include?(@active_focus)
        rotate_application_theme(1)
        true
      else
        false # Laat de 't' vloeibaar doorstromen naar handle_study_session_initialization!
      end

    when 'T'
      # Pas exact dezelfde veiligheidsgrendel toe voor achterwaarts wisselen
      if %i[tree table].include?(@active_focus)
        rotate_application_theme(-1)
        true
      else
        false
      end

    when 'f10', :f10
      @menu_origin_focus = @active_focus
      activate_menu_focus
      true

    when '['
      handle_left_navigation
      true

    when ']'
      handle_right_navigation(is_replace_active, is_deck_active)
      true

    when 'tab', :tab, "\e[Z"
      handle_tab_navigation(is_replace_active, is_deck_active)
      true

    when 'back_tab', :back_tab
      handle_back_tab_navigation(is_replace_active, is_deck_active)
      true

    when 'm'
      rotate_study_strategy
      true

    when 's'
      rotate_marker_symbol
      true

    when 'f3'
      SoundManager.play(:toggle)
      toggle_handwritten_font_style
      true

    when 'c'
      rotate_corner_type
      true

    when 'i'
      toggle_rotation_indicator
      true

    else
      false
    end
  end

  def toggle_rotation_indicator
    settings = AppConfig.settings

    settings.rotation_indicator_enabled = !settings.rotation_indicator_enabled

    if settings.rotation_indicator_enabled
      activate_rotation_indicator(play_sound: false)
    else
      @rotation_indicator_countdown = 0
    end

    settings.rotation_indicator_enabled ? SoundManager.play(:toggle) : SoundManager.play(:off)
    settings.save

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def rotate_study_strategy
    # Blokkeer de rotatie als er onverhoopt een popup actief is
    return if defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    settings = AppConfig.settings

    strategies = %i[
      fronts_random
      backs_random
      alternately_fronts_and_backs_random
      everything_random
    ]

    # 1. Haal de actieve stand live op uit de centrale settings
    current_strat = settings.study_strategy || :fronts_random
    curr_idx = strategies.index(current_strat) || 0

    # 2. Advance the index by exactly one position (rotation loop).
    SoundManager.play(:cycle)
    next_idx = (curr_idx + 1) % strategies.length

    # 3. Schrijf de nieuwe stand direct persistent weg naar config/settings.yml!
    settings.study_strategy = strategies[next_idx]
    settings.save if AppConfig.settings.respond_to?(:save)

    # 4. Dwing de app om alle interface registers direct live te synchroniseren
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def rotate_marker_symbol
    # Blokkeer de rotatie als er onverhoopt een popup actief is
    return if defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    settings = AppConfig.settings

    # 1. Haal de beschikbare markers dynamisch op uit de AppConfig definitie
    available_markers = %i[cross block plus asterisk]

    # 2. Haal de actieve stand live op uit de centrale settings
    current_marker = settings.selected_marker_symbol || :cross
    curr_idx = available_markers.index(current_marker) || 0

    # 3. Advance the index by exactly one position (rotation loop).
    SoundManager.play(:cycle)
    next_idx = (curr_idx + 1) % available_markers.length
    target_marker = available_markers[next_idx]

    # 4. Schrijf de nieuwe stand direct permanent weg naar config/settings.yml!
    settings.selected_marker = target_marker
    settings.save if settings.respond_to?(:save)

    # 5. Dwing de app om alle interface registers direct live te synchroniseren
    @tree.refresh_nodes if @tree.refresh_nodes
  end

  def rotate_corner_type
    # Blokkeer de rotatie als er onverhoopt een popup actief is
    return if defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    settings = AppConfig.settings

    # 1. Haal de beschikbare corners op uit de AppConfig definitie
    available_corners = %i[rounded plain]

    # 2. Haal de actieve stand live op uit de centrale settings
    current_corner = settings.corner_type || :rounded
    current_corner = current_corner.to_s.gsub(/\A:/, '').to_sym

    curr_idx = available_corners.index(current_corner) || 0

    # 3. Advance the index by exactly one position (rotation loop).
    SoundManager.play(:toggle)
    next_idx = (curr_idx + 1) % available_corners.length
    target_corner = available_corners[next_idx]

    # 4. Schrijf de nieuwe stand direct permanent weg naar config/settings.yml!
    settings.corner = target_corner
    settings.save if settings.respond_to?(:save)

    # 5. Dwing de app om alle interface registers direct live te synchroniseren
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def tree_deck_active?
    @tree && @tree.selected_path && @tree.selected_path.size == 3
  end

  def open_help_popup
    @focus_before_help = @active_focus unless @focus_before_help == :menu
    @menu_origin_focus = :menu if @active_focus == :menu

    @popup.show(
      title: " #{AppConfig.settings.language_string(:help_main_title)} ",
      message: AppConfig.settings.language_string(:help_main),
      type: :help,
      alignment: :left
    )
    @active_focus = :popup
  end

  # Open the dedicated help menu for an active study session.
  def open_study_session_help_popup
    # Preserve the exact pause state, including a manual pause.
    @test_timer_paused_before_help = (@test_timer_paused == true)

    # Pause both the countdown timer and the elapsed-time stopwatch.
    @test_timer_paused = true
    @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    @focus_before_help = :study_focus_mode
    @last_focus = :study_focus_mode

    @popup.show(
      title: " #{AppConfig.settings.language_string(:help_study_title)} ",
      message: AppConfig.settings.language_string(:help_study),
      type: :study_session_help,
      alignment: :left
    )

    @active_focus = :popup
  end

  def handle_left_navigation
    if @active_focus == :replace_mode && @last_focus == :table
      execute_undo if @replace_action_performed && respond_to?(:execute_undo) && @undo_stack && !@undo_stack.empty?
      @replace_action_performed = false
      @active_focus = :tree
    elsif @active_focus == :tree || @active_focus == :replace_mode
      trigger_system_beep
    else
      @active_focus = :tree
    end
  end

  def handle_right_navigation(is_replace_active, is_deck_active)
    unless @active_focus == :tree || @active_focus == :menu || (@active_focus == :replace_mode && @last_focus == :tree)
      return trigger_system_beep
    end
    return trigger_system_beep unless is_deck_active

    if @active_focus == :replace_mode && @last_focus == :tree
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      @active_focus = :table
    else
      @active_focus = if is_replace_active && @search_matches && @search_matches.any?
                        :replace_mode
                      else
                        :table
                      end
    end
    select_first_active_deck_card
  end

  def select_first_active_deck_card
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

    return unless active_deck && active_deck.cards.any? && @table_state

    @table_state.select(0) # Forceer de selectiebalk naar de 1e rij

    # Herstel direct de visuele scroll-offset van de tabel naar het absolute begin
    if respond_to?(:set_table_viewport_offset, true)
      set_table_viewport_offset(0)
    elsif defined?(@table_viewport_offset)
      @table_viewport_offset = 0
    end
  end

  def rotate_application_theme(direction_step = 1)
    settings = AppConfig.settings

    # Safety boundary block: Prevent theme shifts if an active dialogue popup is open
    return if defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    # Define the sequence loop of installed aesthetic color palettes
    available_themes = %i[default cga julia crt amber borland dracula ttx c64 tos terminal]

    # 1. Fetch the currently active design theme layout string from AppConfig
    current_theme = settings.respond_to?(:theme) ? settings.theme : :default
    current_theme = current_theme.to_s.strip.downcase.to_sym

    # Alias conversion layer to keep the index tracker stable
    current_theme = :default if %i[classic standard monochrome mono dark].include?(current_theme)

    current_idx = available_themes.index(current_theme) || 0

    # 2. Advance or reverse the selector exactly 1 slot based on the step argument
    SoundManager.play(:cycle)
    next_idx = (current_idx + direction_step) % available_themes.length
    target_theme = available_themes[next_idx]

    # =========================================================================
    # 🧹 CUSTOM THEME UNLINKING FIREWALL (NEW)
    # 👉 Since we are cycling back onto a native built-in theme track profile,
    # we MUST scrub out old custom metadata paths and names from the settings record.
    # This prevents the boot manager from re-loading a custom theme on the next start!
    # =========================================================================
    if settings.respond_to?(:custom_theme_name=)
      settings.custom_theme_name = nil
      settings.custom_theme_path = nil
    else
      # Dynamic backup variable wipe for strict instance encapsulation
      settings.instance_variable_set(:@custom_theme_name, nil)
      settings.instance_variable_set(:@custom_theme_path, nil)
    end
    # =========================================================================

    # 3. Mutate the active configuration
    settings.theme = target_theme

    if target_theme == :terminal
      initialize_terminal_theme
    else
      settings.theme_items.clear
    end

    settings.save if AppConfig.settings.respond_to?(:save)

    # 4. Trigger an immediate, live UI repaint cycle across your terminal dashboard
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def handle_tab_navigation(is_replace_active, is_deck_active)
    case @active_focus
    when :tree
      if is_deck_active
        @active_focus = table_or_replace_focus(is_replace_active)
        select_first_active_deck_card
      else
        # 👉 GEFIXT: Als er geen deck actief is (d.w.z. de gebruiker staat op een subject of een source), springen we naar de menubalk en initialiseren we deze
        @menu_origin_focus = @active_focus
        activate_menu_focus
      end
    when :table
      # 👉 GEFIXT: Vanuit de tabel tab je nu direct door naar de menubalk
      @menu_origin_focus = @active_focus
      activate_menu_focus
    when :replace_mode
      handle_replace_mode_tab(is_deck_active)
    when :menu
      # 👉 GEFIXT: Vanuit de menubalk sluit de loop en gaan we terug naar de sidebar tree
      @menu_dropdown_open = false
      @active_focus = :tree
    else
      @active_focus = :tree
    end
  end

  def table_or_replace_focus(is_replace_active)
    is_replace_active && @search_matches && @search_matches.any? ? :replace_mode : :table
  end

  def handle_replace_mode_tab(is_deck_active)
    if @last_focus == :tree && is_deck_active
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      @active_focus = :table
      select_first_active_deck_card
    elsif @last_focus == :tree
      @active_focus = :menu
    else
      @active_focus = :menu
    end
  end

  def handle_back_tab_navigation(is_replace_active, is_deck_active)
    case @active_focus
    when :tree
      # 👉 GEFIXT: Achteruit vanaf de tree spring je direct naar de menubalk
      @menu_origin_focus = @active_focus
      activate_menu_focus
    when :menu
      # 👉 GEFIXT: Achteruit vanaf de menubalk ga je naar de tabel (indien actief) of anders naar de tree
      if is_deck_active
        @active_focus = table_or_replace_focus(is_replace_active)
        select_first_active_deck_card
      else
        @active_focus = :tree
      end
    when :table, :replace_mode
      handle_back_tab_from_data_focus(is_deck_active)
    else
      @active_focus = :tree
    end
  end

  def handle_back_tab_from_data_focus(is_deck_active)
    if is_deck_active
      if @active_focus == :replace_mode
        @active_focus = :tree
      else
        # 👉 DE GEFIXTE ROUTE: Vanuit de tabel ga je met Backtab ALTIJD direct terug naar de tree sidebar!
        @active_focus = :tree
      end
    else
      @menu_origin_focus = @active_focus
      activate_menu_focus
    end
  end

  def navigation_switch_key?(key, key_str)
    ['tab', 'back_tab', '[', ']', ':', 'f10'].include?(key_str) || %i[tab back_tab].include?(key)
  end

  def handle_unchanged_switch(key, is_deck_active, _focus_before_switch)
    if key == ']' && is_deck_active
      if @active_focus == :table || @active_focus == :replace_mode
        trigger_system_beep
      else
        @active_focus = :table
        @tree_state.select(0)
      end
    elsif key == ']'
      trigger_system_beep
    elsif key == 'back_tab'
      @active_focus = :tree
    end
  end

  def finalize_navigation_switch(focus_before_switch)
    @last_focus = @active_focus

    if @active_focus != :command_mode && focus_before_switch != :command_mode
      @selected_table_rows = []
      @selected_tree_paths = []
    end

    # 🎯 AUTOMATISCHE OPRIUMACTIE BIJ PANEL WISSEL:
    # Als de gebruiker uit de tabel stapt terwijl de All-Decks search draait, sluiten we de modus af!
    exit_global_search_mode if defined?(@global_search_active) && @global_search_active && @active_focus != :table

    cleanup_table_search_on_navigation(focus_before_switch)
    cleanup_tree_search_on_navigation(focus_before_switch)

    activate_rotation_indicator if focus_before_switch != @active_focus

    @sort_indicator_visible = false if @active_focus == :table && focus_before_switch != :table
    @last_focus = @active_focus

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def cleanup_table_search_on_navigation(focus_before_switch)
    return unless %i[table replace_mode].include?(focus_before_switch)

    @sort_indicator_visible = false
    @search_matches = nil
    @search_current_match_idx = nil
    @last_search_query = nil
    @last_replace_text = nil
    @last_case_sensitive = nil
    @last_regex = nil
    return unless %i[tree menu].include?(@active_focus)

    @interactively_replacing = false
    @replace_action_performed = false
  end

  def cleanup_tree_search_on_navigation(focus_before_switch)
    return unless focus_before_switch == :tree || (focus_before_switch == :replace_mode && @tree_search_matches)

    @tree_search_matches = nil
    @tree_search_current_idx = nil
    @last_tree_search_query = nil
    @interactively_replacing = false if %i[table menu].include?(@active_focus)
  end

  def activate_rotation_indicator(play_sound: true)
    return unless AppConfig.settings.rotation_indicator_enabled

    @rotation_indicator_countdown = 8
    @animation_tick ||= 0
    @rotation_indicator_play_sound = play_sound
    @rotation_indicator_sound_played = false
  end
end
