class RatatuiRubyApp
  Dir[File.join(__dir__, 'concerns', '*.rb')].sort.each { |file| require_relative file }

  include PopupInputHandler
  include NavigationInputHandler
  include NotificationHandler
  include TableInputHandler
  include TreeInputHandler
  include DrillInputHandler
  include QuizInputHandler
  include MultipleChoiceInputHandler
  include PlayMemoryInputHandler
  include TwoOfAKindInputHandler
  include TestInputHandler
  include FontStyleHelper
  include StatusbarInputHandler
  include SpeechHandler

  def capture_selection_state
    {
      focus: @active_focus,

      tree_paths: (@selected_tree_paths || []).dup,
      tree_selected: @tree_state&.selected,
      tree_anchor: @tree_selection_anchor,
      tree_anchor_index: @tree_selection_anchor_index,
      tree_shift_active: @tree_shift_selection_active,
      tree_page_viewport_start: @tree_page_viewport_start,

      table_rows: (@selected_table_rows || []).dup,
      table_selected: @table_state&.selected,
      table_anchor: @selection_anchor,
      table_viewport_offset: @table_viewport_offset,
      normal_page_viewport_start: @normal_page_viewport_start,
      search_page_viewport_start: @search_page_viewport_start,
      current_card_idx: @current_card_idx,
      search_current_match_idx: @search_current_match_idx
    }
  end

  def restore_selection_state(state)
    return false unless state

    @active_focus = state[:focus]

    @selected_tree_paths = (state[:tree_paths] || []).dup
    @tree_selection_anchor = state[:tree_anchor]
    @tree_selection_anchor_index = state[:tree_anchor_index]
    @tree_shift_selection_active = state[:tree_shift_active]

    @selected_table_rows = (state[:table_rows] || []).dup
    @selection_anchor = state[:table_anchor]

    @current_card_idx = state[:current_card_idx]
    @search_current_match_idx = state[:search_current_match_idx]

    @normal_page_viewport_start = state[:normal_page_viewport_start]
    @search_page_viewport_start = state[:search_page_viewport_start]

    @tree_state.select(state[:tree_selected]) if @tree_state
    @table_state.select(state[:table_selected]) if @table_state

    unless state[:tree_page_viewport_start].nil?
      @tree_page_viewport_start = state[:tree_page_viewport_start]
      set_tree_page_offset(state[:tree_page_viewport_start]) if respond_to?(:set_tree_page_offset, true)
    end

    set_table_viewport_offset(state[:table_viewport_offset]) unless state[:table_viewport_offset].nil?

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    true
  end

  def record_selection_change(before_state)
    after_state = capture_selection_state
    return if before_state == after_state

    @last_selection_state = after_state
  end

  def handle_undo_redo_shortcuts(key, has_ctrl, has_shift)
    return false unless key

    key_str = key.to_s.strip.downcase
    is_z = key_str == 'z'
    is_y = key_str == 'y'
    is_undo = is_z && has_ctrl && !has_shift
    is_redo = (is_y && has_ctrl) || (is_z && has_ctrl && has_shift)
    return false unless is_undo || is_redo

    @history_action_stack ||= []
    @history_redo_action_stack ||= []

    action = if is_undo
               @history_action_stack.last
             else
               @history_redo_action_stack.last
             end

    return false unless action == :data

    focus_context = @active_focus
    success = is_undo ? execute_undo : execute_redo
    return false unless success

    if is_undo
      if focus_context == :replace_mode && @last_search_query
        @active_focus = :replace_mode
        new_deck = @library.subjects[@current_subject_idx || 0]&.sources&.[](@current_source_idx || 0)&.decks&.[](@current_deck_idx || 0)

        if new_deck
          @replace_cards = new_deck.cards if defined?(@replace_cards)
          @search_matches = perform_card_scan(@last_search_query, new_deck.cards) if respond_to?(:perform_card_scan)
        end
      elsif focus_context == :tree
        @active_focus = :tree
      end

      if %i[table replace_mode].include?(focus_context) && defined?(@table_state) && @table_state
        s_idx = @current_subject_idx || 0
        src_idx = @current_source_idx || 0
        d_idx = @current_deck_idx || 0
        current_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

        if current_deck && current_deck.cards && !current_deck.cards.empty?
          current_selection = @table_state.selected || 0
          clamped_selection = [[current_selection, 0].max, current_deck.cards.length - 1].min
          @table_state.select(clamped_selection)
        else
          @table_state.select(nil)
        end
      end
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    if is_undo
      @history_action_stack.pop
      @history_redo_action_stack << action
    else
      @history_redo_action_stack.pop
      @history_action_stack << action
    end

    true
  end

  def handle_active_popup_input(key, modifiers, key_str, inline_raw_key, is_escape, has_table_search:,
                                has_tree_search:, origin_focus:, popup_is_match_navigation:, popup_search_replace_context:)
    popup_is_navigating_match = %w[n N].include?(inline_raw_key) && popup_search_replace_context
    return nil if popup_is_match_navigation && popup_search_replace_context
    return nil if popup_is_navigating_match

    is_submit = ['enter', "\r", "\n"].include?(key_str) || key == :enter

    if popup_escape_requested?(key_str, modifiers, is_escape)
      handle_popup_escape_input(key, modifiers, origin_focus)
    elsif is_submit
      handle_popup_submit_input(key, modifiers, origin_focus)
    else
      handle_popup_input(key, modifiers)
      false
    end
  end

  # Recognize Escape and the related Ctrl shortcuts that cancel a popup.
  def popup_escape_requested?(key_str, modifiers, is_escape)
    is_escape ||
      (key_str == 'c' && modifiers.any? { |m| m.to_s.downcase == 'ctrl' }) ||
      key_str == "\x03" || # ctrl+c
      (key_str == 'q' && modifiers.any? { |m| m.to_s.downcase == 'ctrl' }) ||
      key_str == "\x11" # ctrl+q
  end

  # Restore the timer state saved before the help popup was opened.
  def restore_study_timer_after_help
    return unless instance_variable_defined?(:@test_timer_paused_before_help)

    was_paused = @test_timer_paused_before_help == true

    @test_timer_paused = was_paused
    @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    @test_timer_paused_before_help = nil
  end

  # Sluit of annuleert de popup en herstelt focus, timerstatus en navigatiestatus.
  def handle_popup_escape_input(key, modifiers, origin_focus)
    # Onthoud exact welk paneel op de achtergrond actief was vòòr de wipe
    backup_origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : (origin_focus || :tree)

    return_to_command_mode =
      (defined?(@last_focus) && @last_focus == :command_mode) ||
      (defined?(@focus_before_help) && @focus_before_help == :command_mode)

    handle_popup_input(key, modifiers)

    if defined?(@focus_before_help) && @focus_before_help == :study_focus_mode
      restore_study_timer_after_help

      @active_focus = :study_focus_mode
      @last_focus   = :study_focus_mode
      @focus_before_help = nil
    elsif return_to_command_mode
      @active_focus = :command_mode
      @last_focus = :command_mode
      @command_mode_visible = true

      # De oorspronkelijke bestemming blijft behouden.
      @menu_origin_focus ||= backup_origin if %i[tree table].include?(backup_origin)

      @statusbar_field.is_focused = true if defined?(@statusbar_field) && @statusbar_field

      # 🎯 FIX: Overschrijf backup_origin niet blindelings, maar bewaar de echte herkomst (:table)
      @search_replace_background_source = @menu_origin_focus || backup_origin

    elsif defined?(@focus_before_help) && @focus_before_help == :menu
      @active_focus        = :menu
      @last_focus          = :menu
    else
      target_panel = if defined?(@cockpit_panel_anchor) && !@cockpit_panel_anchor.nil?
                       @cockpit_panel_anchor
                     elsif defined?(@menu_origin_focus) && !@menu_origin_focus.nil? && @menu_origin_focus != :menu
                       @menu_origin_focus
                     else
                       backup_origin
                     end

      target_panel = :tree if %i[menu popup command_mode].include?(target_panel)

      finalize_navigation_switch(target_panel) if respond_to?(:finalize_navigation_switch, true)

      @active_focus       = target_panel
      @last_focus         = target_panel
      @menu_dropdown_open = false
      @active_submenu_idx = 0

      @cockpit_panel_anchor = nil
      @menu_origin_focus    = nil
    end

    @focus_before_help = nil if instance_variable_defined?(:@focus_before_help)

    if !%i[command_mode menu].include?(@active_focus) && instance_variable_defined?(:@cockpit_panel_anchor)
      @cockpit_panel_anchor = nil
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  end

  # Bevestigt de popup en herstelt de juiste focus afhankelijk van de popupcontext.
  def handle_popup_submit_input(key, modifiers, origin_focus)
    settings = AppConfig.settings

    active_pop = @popup.respond_to?(:active_popup) ? @popup.active_popup : nil

    # 🔒 DE INTELLIGENTE NULL-GUARD:
    if active_pop.nil? || !active_pop.is_a?(Hash) || (active_pop[:type] == :form && active_pop[:fields].nil?)
      @active_focus = origin_focus == :popup ? :tree : (origin_focus || :tree)
      @last_focus   = @active_focus
      return true
    end

    popup_title = begin; active_pop[:title].to_s.downcase; rescue StandardError; ''; end
    form_fields = active_pop[:fields] || {}

    # Dedicated study help: close and return directly to the study session.
    if active_pop[:type] == :study_session_help
      restore_study_timer_after_help

      @popup.close if @popup.respond_to?(:close)

      @active_focus = :study_focus_mode
      @last_focus = :study_focus_mode
      @focus_before_help = nil

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      return true
    end

    # Existing info/general-help return route.
    if %i[info help].include?(active_pop[:type]) # 1. Sloop de popup fysiek en randschoon uit het schermregister
      handle_popup_input(key, modifiers)

      # 2. Bepaal het absolute startpaneel van vóór het complete menu-bezoek
      #    Check @menu_origin_focus first, then @cockpit_panel_anchor, and fall back to origin_focus.
      start_target = defined?(@menu_origin_focus) && @menu_origin_focus && @menu_origin_focus != :menu ? @menu_origin_focus : nil
      start_target ||= defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : nil
      start_target ||= (%i[menu popup].include?(origin_focus) ? :tree : (origin_focus || :tree))

      # Harde veiligheidsgrendel tegen oneindige menu/popup loops
      start_target = :tree if %i[menu popup command_mode].include?(start_target)

      # 3. INTERFACE BRANDMUUR OVERRIDE:
      # Close the menu bar unconditionally and clear all stale state,
      # exact zoals de succesvolle Escape-pipeline dat doet!
      @menu_dropdown_open   = false if instance_variable_defined?(:@menu_dropdown_open)
      @active_submenu_idx   = 0 if instance_variable_defined?(:@active_submenu_idx)
      @cockpit_panel_anchor = nil
      @menu_origin_focus    = nil
      @focus_before_help    = nil if instance_variable_defined?(:@focus_before_help)

      # 4. Effectueer de focus-as direct terug naar de echte basis-herkomst
      @active_focus = start_target
      @last_focus   = start_target

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      return true # Consumeer de Enter-toets direct hard; 0% doorlek naar de hoofd-lus!
    end

    # Haal de zoekterm op (Varaf hier draait de code uitsluitend voor geldige formulieren)
    query_widget = form_fields[:query]

    raw_query =
      if query_widget.respond_to?(:get_text)
        query_widget.get_text.to_s
      elsif query_widget.respond_to?(:text)
        query_widget.text.to_s
      else
        query_widget.to_s
      end

    search_term = raw_query.strip

    is_global = form_fields[:global].respond_to?(:checked?) ? form_fields[:global].checked? : false
    is_case   = form_fields[:case_sensitive].respond_to?(:checked?) ? form_fields[:case_sensitive].checked? : false
    is_regex  = form_fields[:regex].respond_to?(:checked?) ? form_fields[:regex].checked? : false

    # 1. Close the popup immediately using the framework default.
    handle_popup_input(key, modifiers)

    # Herstel de basis focus
    @active_focus = origin_focus == :popup ? :tree : (origin_focus || :tree)
    @last_focus   = @active_focus

    return true if search_term.empty?

    lang_tree_search = settings.language_string(:search_title_tree).to_s.downcase.strip
    lang_tree_replace = settings.language_string(:search_and_replace_title_tree).to_s.downcase.strip

    lang_table_search  = settings.language_string(:search_title_table).to_s.downcase.strip
    lang_table_replace = settings.language_string(:search_and_replace_title_table).to_s.downcase.strip

    # 1. Controleer of de actieve popup-titel overeenkomt met de Tree-vertalingen
    is_tree_context = popup_title.include?(lang_tree_search) || popup_title.include?(lang_tree_replace)

    # 2. Controleer of de actieve popup-titel overeenkomt met de Table-vertalingen
    is_table_context = popup_title.include?(lang_table_search) || popup_title.include?(lang_table_replace)

    if is_tree_context
      # 🌲 A: ZOEKACTIE IN DE TREE (Uitsluitend mapnamen)
      @tree_case_sensitive = is_case
      execute_tree_search(search_term)
      @active_focus = :tree
      @last_focus   = :tree

    elsif is_table_context
      # 📊 B: ZOEKACTIE IN DE TABLE (Flitskaart inhoud)
      if is_global
        # Search all decks (the 'All' checkbox state) while keeping focus in the table.
        perform_global_search(search_term, case_sensitive: is_case, regex_mode: is_regex)
      else
        # Otherwise, search locally in the current deck.
        @table_case_sensitive = is_case
        # execute_local_table_search(search_term, is_case, is_regex)
      end
      @active_focus = :table
      @last_focus   = :table
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  end

  # =========================================================================
  # ⌨️ PROCESS KEY INPUT (HIGH-PERFORMANCE FINAL MATRIX)
  # Popup-hiërarchie hersteld naar de absolute top om focus-gijzeling te breken!
  # =========================================================================
  def process_key_input(key, modifiers = [])
    mods_check = Array(modifiers).map { |m| m.to_s.downcase }
    has_alt_check = mods_check.include?('alt') || mods_check.include?('meta') || mods_check.include?('option')
    has_ctrl_check = mods_check.include?('ctrl') || mods_check.include?('control')
    has_shift_check = mods_check.include?('shift')
    key_raw_check = key.to_s.strip.sub(/\A:/, '').downcase

    # Ctrl+Shift+C/V are aliases for the application's Ctrl+C/V actions.
    # Normalize them before any shortcut guards or focus-specific handlers run.
    if has_ctrl_check && has_shift_check && %w[c v].include?(key_raw_check)
      modifiers = Array(modifiers).reject { |modifier| modifier.to_s.downcase == 'shift' }
      has_shift_check = false
    end

    settings = AppConfig.settings

    if @status_message
      # In command mode dismiss the status message without letting the same
      # Enter keystroke submit the command underneath it. Other keys continue
      # through normal command-mode handling so typed characters are retained.
      dismissing_command_message = @active_focus == :command_mode
      is_enter_while_dismissing = %w[enter \r \n].include?(key.to_s.strip.downcase.sub(/\A:/, '')) || key == :enter

      @status_message = nil
      @status_message_expires_at = nil

      return true if dismissing_command_message && is_enter_while_dismissing
    end

    return handle_startup_screen_input(key) if @active_focus == :startup_screen

    # 1. CENTRALE SHORTCUT BRANDMUUR Sluis:
    return true if intercept_form_control_shortcuts(key, key_raw_check, has_ctrl_check, modifiers)

    if defined?(@global_search_active) && @global_search_active
      target_action_key = key_raw_check.to_s.strip

      if %w[a A].include?(target_action_key)
        # We roepen direct de nieuwe, onafhankelijke global replace methode aan!
        execute_global_replace_all_decks if respond_to?(:execute_global_replace_all_decks)
        return true # Slik de toets onmiddellijk binarisch in!
      end
    end

    # 2. MUTATION GUARD (called by the separate function at the bottom of the file):
    return true if intercept_mutations_during_search(key, key_raw_check)

    is_escape_action = key == :escape || %w[escape esc \e].include?(key_raw_check)

    # Afhandeling van het afsluiten van een actieve leersessie.
    return true if handle_study_session_exit(key, modifiers, is_escape_action)

    # Afhandeling van de bevestiging voor een bulk-reset.
    return true if handle_bulk_reset_confirmation(key)

    # Handle confirmation for deleting duplicate cards.
    return true if handle_bulk_dedup_confirmation(key)

    # =========================================================================
    # 🎯 VIM-STYLE OVERRIDE POORTWACHTER (DE VOORDEUR BRANDMUUR)
    # 👉 OPGELOST: Als de extensie-waarschuwing actief is, vangen we 'y' of 'n'
    # direct single-char op vòòrdat het invoerveld of de Enter-lus de focus kaapt!
    # =========================================================================
    # Handle all command/status bar keys here.
    return true if handle_command_mode_input(key, modifiers, has_ctrl_check, has_alt_check, has_shift_check)

    # 🎯 ALIAS-GRENDEL: Vertaal Ctrl+N en Ctrl+P direct...

    form_popup_active = defined?(@popup) && @popup && @popup.active? &&
                        @popup.active_popup && @popup.active_popup[:type] == :form
    if has_ctrl_check && %w[n p].include?(key_raw_check) && !form_popup_active
      key = key_raw_check == 'n' ? :down : :up
      key_raw_check = key.to_s.strip.sub(/\A:/, '').downcase
      modifiers = Array(modifiers).map { |m| m.to_s.downcase }
      modifiers.delete('ctrl')
      modifiers.delete('control')
      has_ctrl_check = false
    end

    has_table_search = @search_matches && @search_matches.any?
    has_tree_search  = defined?(@tree_search_matches) && @tree_search_matches && @tree_search_matches.any?
    is_replace_mode  = (@active_focus == :replace_mode) || (defined?(@interactively_replacing) && @interactively_replacing == true)
    search_or_replace_active = has_table_search || has_tree_search || is_replace_mode
    is_already_studying = (@active_focus == :study_focus_mode)
    popup_is_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    if defined?(@active_focus) && @active_focus != :menu && @active_focus != :popup && @active_focus != :command_mode
      @cockpit_panel_anchor = @active_focus
    end

    if @active_focus == :menu
      menu_consumed = handle_menu_input(key, modifiers)
      if menu_consumed
        update_statusbar_matches_count if respond_to?(:update_statusbar_matches_count, true)
        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
        return true
      end
    end

    # Start een studiesessie wanneer de bijbehorende sneltoets is ingedrukt.
    return true if handle_study_session_initialization(
      key_raw_check, has_alt_check, has_ctrl_check, popup_is_active,
      search_or_replace_active, is_already_studying, settings
    )

    # Centrale afhandeling van de algemene toetsen en sneltoetsen.
    return true if handle_global_input_shortcuts(
      key, modifiers, key_raw_check, has_ctrl_check, has_alt_check, has_shift_check,
      popup_is_active, search_or_replace_active, is_already_studying
    )

    is_option_select_down = has_alt_check && key_raw_check == 'n'
    is_option_select_up   = has_alt_check && key_raw_check == 'p'

    if is_option_select_down || is_option_select_up
      key = is_option_select_down ? 'J' : 'K'
      # Schakel Alt uit in de modifiers array, en voeg Shift geforceerd toe!
      modifiers = Array(modifiers).map { |m| m.to_s.downcase }
      modifiers.delete('alt')
      modifiers.delete('option')
      modifiers.delete('meta')
      modifiers << 'shift' unless modifiers.include?('shift')
    end

    inline_raw_key = key.to_s.strip
    # RatatuiRuby may deliver navigation keys as symbols (e.g. :page_up).
    # Keep the original key for symbol comparisons, but normalize the textual
    # representation so both :page_up and 'page_up' follow the same route.
    key_str = inline_raw_key.downcase
    normalized_page_key = key_str.tr('-', '_')
    is_escape = ['esc', 'escape', "\e"].include?(key_str) || key == :escape

    mods = Array(modifiers).map { |m| m.to_s.downcase }
    has_alt = mods.include?('alt') || mods.include?('meta') || mods.include?('option')
    has_ctrl = mods.include?('ctrl') || mods.include?('control')
    has_shift = mods.include?('shift')

    popup_was_active = @popup.active?

    # Tijdens een actieve Search/Replace mogen PageUp/PageDown en Ctrl-U/Ctrl-D
    # must not be consumed by popup input. At that point, the popup is only
    # de invoerlaag; de navigatie hoort bij de gevonden matches.
    popup_is_page_up = %w[page_up pageup].include?(key_str) ||
                       (has_ctrl && key_str == 'u')
    popup_is_page_down = %w[page_down pagedown].include?(key_str) ||
                         (has_ctrl && key_str == 'd')
    popup_is_match_navigation = popup_is_page_up || popup_is_page_down
    # Search/Replace page navigation is tied to the component from which the
    # search/replace session was started. Do not rely on @active_focus alone:
    # during a form/popup session it may temporarily be :replace_mode.
    table_search_replace_context =
      ((@active_focus == :table || @last_focus == :table) &&
       @search_matches && @search_matches.any?) ||
      (@active_focus == :replace_mode && @last_focus == :table &&
       @search_matches && @search_matches.any?)

    tree_search_replace_context =
      ((@active_focus == :tree || @last_focus == :tree) &&
       @tree_search_matches && @tree_search_matches.any?) ||
      (@active_focus == :replace_mode && @last_focus == :tree &&
       @tree_search_matches && @tree_search_matches.any?)

    popup_search_replace_context = table_search_replace_context || tree_search_replace_context

    # =========================================================================
    # A0. SEARCH/REPLACE PAGE-NAVIGATIE — VÓÓR DE POPUP-SLUIS
    #
    # PageUp/PageDown en Ctrl-U/Ctrl-D horen tijdens Search/Replace bij de
    # matchnavigatie, ook wanneer de popup nog actief is. Bepaal de herkomst
    # uitsluitend aan de hand van de actieve/originele focus; de aanwezigheid
    # whether matches exist is checked by handle_search_page_navigation itself.
    # This prevents Table + Replace input from being consumed by the popup.
    # =========================================================================
    is_ctrl_u_alias = has_ctrl && key_str == 'u'
    is_ctrl_d_alias = has_ctrl && key_str == 'd'
    is_page_up_input = %w[page_up pageup].include?(normalized_page_key) || is_ctrl_u_alias
    is_page_down_input = %w[page_down pagedown].include?(normalized_page_key) || is_ctrl_d_alias
    is_search_replace_page_input = is_page_up_input || is_page_down_input

    search_replace_origin = if @active_focus == :replace_mode
                              @last_focus
                            else
                              @active_focus
                            end
    search_replace_page_context = %i[table tree].include?(search_replace_origin)

    if is_search_replace_page_input && search_replace_page_context &&
       respond_to?(:handle_search_page_navigation, true)
      consumed = handle_search_page_navigation(key, has_ctrl, has_alt)
      return true if consumed
    end

    # =========================================================================
    # A. DE ACTIEVE POPUP SLUIS (Voor als het formulier in beeld staat)
    # =========================================================================
    # Ook n/N zijn tijdens een actieve tree Search/Replace-sessie matchnavigatie.
    # Like PageUp/PageDown, do not let the popup form consume these keys.
    popup_is_navigating_match = %w[n N].include?(inline_raw_key) && popup_search_replace_context
    if popup_was_active && !(popup_is_match_navigation && popup_search_replace_context) && !popup_is_navigating_match
      popup_result = handle_active_popup_input(
        key, modifiers, key_str, inline_raw_key, is_escape,
        has_table_search: has_table_search, has_tree_search: has_tree_search,
        origin_focus: @last_focus || :tree,
        popup_is_match_navigation: popup_is_match_navigation,
        popup_search_replace_context: popup_search_replace_context
      )

      return popup_result unless popup_result.nil?
    end

    # =========================================================================
    # B. STANDAARD ESCAPE BRANDMUUR (Voor normale Search)
    # =========================================================================
    # Handle Escape for search/replace state; otherwise, clear only the selections.
    return true if handle_standard_search_escape(is_escape)

    # Verwerk navigatietoetsen voor actieve zoekresultaten.
    return true if handle_search_navigation_gateway(key, key_str, inline_raw_key, has_ctrl, has_shift)

    # Geef PageUp/PageDown en hun sneltoetsvarianten voorrang bij de boomstructuur.
    return true if handle_tree_page_navigation_input(
      key, normalized_page_key, has_ctrl, has_alt, has_shift
    )

    # Algemene component-routing (Tab, [, ], :).
    return handle_interactive_replace_mode(key, has_shift, modifiers) if is_replace_mode

    focus_before_nav = @active_focus
    consumed_by_nav = handle_navigation_input(key, modifiers)

    return true if consumed_by_nav || (@active_focus != focus_before_nav)

    # Let the component that currently has focus handle the key.
    handle_focus_specific_input(key, modifiers, key_raw_check, settings)
  end
end

def exit_global_search_mode
  return unless defined?(@global_search_active) && @global_search_active

  @global_search_active = false
  @global_search_query = nil
  @global_search_matches = []
  @global_search_matched_deck_ids = []
  @global_search_current_idx = 0
  @global_search_origin_focus = nil

  # Clear standard search query flags to keep highlights aligned
  @last_search_query = nil
  @last_tree_search_query = nil
  @search_matches = nil
  @tree_search_matches = nil

  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
end

def handle_startup_screen_input(key)
  settings = AppConfig.settings

  case key
  when 'f'
    SoundManager.stop(:chime)
    # Vooruit door de lettertypen
    cycle_startup_screen_font(1)
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

  when 'F'
    SoundManager.stop(:chime)
    # Achteruit door de lettertypen (Shift+f)
    cycle_startup_screen_font(-1)
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

  when 't'
    SoundManager.stop(:chime)
    # Volgende thema activeren (grijpt direct in op jouw bestaande methode!)
    rotate_application_theme(1) if respond_to?(:rotate_application_theme, true)

  when 'T'
    SoundManager.stop(:chime)
    # Vorige thema activeren (Shift+t)
    rotate_application_theme(-1) if respond_to?(:rotate_application_theme, true)

  else
    SoundManager.stop(:chime)
    active_file = settings.last_opened_filename
    active_file = 'languages.json' if active_file.nil? || active_file.to_s.strip.empty?

    # Check whether the loaded file is empty (0 bytes).
    if File.exist?(active_file) && File.zero?(active_file)
      # Activeer de waarschuwing én de hoorbare beep direct op het hoofdscherm!
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_open_error)}: #{settings.language_string(:statusbar_empty_file_error)}!",
        type: :error,
        beep: true,
        expires: true
      )
    end

    # Schakel vloeibaar door naar de tree-modus
    @spinner_countdown = 0
    @active_focus = :tree
    @last_focus   = :tree
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  true # Slik de toetsaanslag onvoorwaardelijk in
end

def cycle_startup_screen_font(direction_step = 1)
  settings = AppConfig.settings

  fonts_dir = File.join(Dir.pwd, 'fonts')
  return unless File.directory?(fonts_dir)

  available_fonts = Dir.glob(File.join(fonts_dir, '*.flf')).map { |f| File.basename(f) }.sort
  return if available_fonts.empty?

  current_font = settings.startup_screen_font_name || 'tubes.flf'
  current_idx = available_fonts.index(current_font) || 0

  # 🎯 FIX: Bereken de nieuwe index op basis van de richting (+1 of -1)
  next_idx = (current_idx + direction_step) % available_fonts.length
  next_font = available_fonts[next_idx]

  settings.startup_screen_font_name = next_font
  settings.save if settings.respond_to?(:save)
end

def intercept_mutations_during_search(key, key_raw_check)
  has_table_search = @search_matches && @search_matches.any?
  has_tree_search   = defined?(@tree_search_matches) && @tree_search_matches && @tree_search_matches.any?
  is_global_search  = defined?(@global_search_active) && @global_search_active
  is_replace_active = (@active_focus == :replace_mode) || (defined?(@interactively_replacing) && @interactively_replacing == true)

  # If no search or replace session is active, pass the key through immediately.
  return false unless has_table_search || has_tree_search || is_global_search || is_replace_active

  # 🎯 DE WATERDICHTE GRENDEL:
  # Als @interactively_replacing op true staat (of de focus staat op :replace_mode),
  # dan zijn 'a' en 'A' legitieme 'Replace All' commando's. We passeren de firewall direct!
  return false if is_replace_active && %w[a A].include?(key_raw_check)

  target_key_string = key.to_s.strip

  # De volledige zwarte lijst inclusief Shift+R, F-toetsen, Backspace en Delete
  is_mutation = %w[a e r R d delete backspace f2 f7 f8].include?(key_raw_check) ||
                %w[a e r R d delete backspace f2 f7 f8].include?(target_key_string) ||
                %w[a e r R d delete backspace f2 f7 f8].include?(target_key_string.downcase) ||
                %i[delete backspace f2 f7 f8].include?(key)

  if is_mutation
    if @active_focus == :tree
      trigger_statusbar_message('Cannot modify library structure while search/replace is active!', type: :error)
    else
      trigger_statusbar_message('Cannot modify flashcards while search/replace is active!', type: :error)
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    return true # Event geconsumeerd: harde blokkade geactiveerd!
  end

  false
end

# =========================================================================
# 🎯 INTERCEPT FORM CONTROL SHORTCUTS & ROBUUSTE COCKPIT BEEP MATRIX
# 👉 RESOLVED: Protects input fields, triggers a beep for Ctrl+C inside
#    the main panels, and prevents accidental window destruction!
# =========================================================================
def intercept_form_control_shortcuts(key, key_raw_check, has_ctrl, modifiers)
  popup_is_form = defined?(@popup) && @popup && @popup.active? &&
                  @popup.active_popup && @popup.active_popup[:type] == :form

  is_pure_ctrl_c = (key_raw_check == 'c' && has_ctrl) || key == "\x03" || key.to_s == "\x03"
  is_pure_ctrl_q = (key_raw_check == 'q' && has_ctrl) || key == "\x11" || key.to_s == "\x11"

  # 🟢 CASUS A: EEN FORMULIER POPUP STAAT IN BEELD (Shortcut Firewall)
  if popup_is_form && (is_pure_ctrl_c || is_pure_ctrl_q)
    # 🎯 FIX: Route the keystroke directly to the targeted text field instance!
    # We inspect the active popup metadata structure to fetch the focused input widget.
    active_fields = @popup.active_popup[:fields] if @popup.respond_to?(:active_popup) && @popup.active_popup
    active_focus_key = @popup.active_popup[:form_focus] if @popup.respond_to?(:active_popup) && @popup.active_popup

    targeted_field = active_fields[active_focus_key] if active_fields && active_focus_key

    if targeted_field && targeted_field.respond_to?(:handle_key)
      # 🚀 SUCCESS: Pass the event straight into the RatinField instance!
      targeted_field.handle_key(key, modifiers)
    elsif @popup.respond_to?(:handle_key)
      # Fallback to the dialog component layer if no focused field is resolved
      @popup.handle_key(key, modifiers)
    elsif defined?(@statusbar_field) && @statusbar_field && @statusbar_field.respond_to?(:handle_key)
      @statusbar_field.handle_key(key, modifiers)
    end

    return true # Consume event securely inside the interactive frame
  end

  # =========================================================================
  # 🌲 CASUS B1: SIDEBAR TREE STAND
  # 👉 If the user tries to hit Ctrl+C inside the Tree sidebar, block it
  #    and emit a warning beep (safeguards terminal processes).
  # =========================================================================
  if is_pure_ctrl_c && !popup_is_form && @active_focus == :tree
    trigger_system_beep if respond_to?(:trigger_system_beep)
    return true
  end

  # =========================================================================
  # 📊 CASUS B2: CARDS TABLE STAND
  # 👉 Return false! This unblocks the event path so Ctrl+C can bypass this
  #    firewall completely and flow right into your card clipboard logic.
  # =========================================================================
  return false if is_pure_ctrl_c && !popup_is_form && @active_focus == :table

  false
end

# Verwerkt Escape buiten pop-ups: beëindigt Search/Replace of wist selecties.
# Geeft true terug zodra Escape is afgehandeld; anders nil.
def handle_standard_search_escape(is_escape)
  return nil unless is_escape

  # Save the original focus before clearing the search state.
  origin_focus = @last_focus || :tree
  has_table_search = @search_matches && @search_matches.any?
  has_tree_search = defined?(@tree_search_matches) && @tree_search_matches && @tree_search_matches.any?
  is_replace = (@active_focus == :replace_mode)

  @global_search_active = false
  @global_search_query = nil
  @global_search_matches = []
  @global_search_matched_deck_ids = []
  @global_search_current_idx = 0

  if has_table_search || has_tree_search || is_replace
    # Gebruik de centrale opruimroutine als die beschikbaar is.
    if respond_to?(:wipe_all_search_artifacts)
      wipe_all_search_artifacts
    else
      # Fallback voor situaties waarin de centrale opruimroutine ontbreekt.
      @search_matches           = nil
      @search_current_match_idx = nil
      @last_search_query        = nil
      @last_replace_text        = nil
      @search_query             = '' if defined?(@search_query)
      @table_case_sensitive     = nil
      @last_case_sensitive      = nil
      @last_regex               = nil

      @tree_search_matches      = nil
      @tree_search_current_idx  = nil
      @last_tree_search_query   = nil
      @tree_case_sensitive      = nil
      @selected_table_rows      = [] if defined?(@selected_table_rows)
    end

    # Schakel vervangmodus uit en herstel de focus van vóór Search/Replace.
    @interactively_replacing = false
    @active_focus = origin_focus
    @last_focus = origin_focus
  else
    # Without an active search, Escape clears only manual selections.
    @selected_tree_paths = []
    @selected_table_rows = [] if defined?(@selected_table_rows)
  end

  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

# Routeert een toets naar de actieve component en behoudt diens bestaande gedrag.
# De helper geeft de afhandelstatus van de studiemodus, boomstructuur of tabel terug.
def handle_focus_specific_input(key, modifiers, key_raw_check, settings)
  focus_on_enter = @active_focus

  case @active_focus
  when :study_focus_mode
    if defined?(@test_awaiting_difficulty) && @test_awaiting_difficulty && %i[quiz
                                                                              multiple_choice].include?(@current_study_mode)
      clean_key = key_raw_check.to_s.strip.downcase
      allowed_start_keys = %w[1 2 3 escape esc \e]

      unless allowed_start_keys.include?(clean_key) || allowed_start_keys.include?(key.to_s.strip.downcase)
        # 🎯 LOCK: The main loop has already cleared the message,
        # so restore the instruction without an expiration (:expires = false).
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_difficulty)}: #{settings.language_string(:statusbar_levels)}.",
          type: :warning,
          beep: false,
          expires: false
        )
        return true # Slik de foutieve toets geruisloos in; 0% lekkage!
      end
    end
    # Verwerk eerst een eventuele moeilijkheidskeuze voor de studiesessie.
    return true if handle_study_difficulty_input(key_raw_check, settings)

    # Then pass the key to the active study mode.
    case @current_study_mode
    when :drill           then return handle_drill_input(key, modifiers)
    when :quiz            then return handle_quiz_input(key, modifiers)
    when :multiple_choice then return handle_multiple_choice_input(key, modifiers)
    when :memory          then return handle_memory_input(key, modifiers)
    when :two_of_a_kind   then return handle_two_of_a_kind_input(key, modifiers)
    end
    true

  when :tree
    # Werk na boomnavigatie de indices en de tabelweergave bij.
    tree_action_consumed = handle_tree_input(key, modifiers)
    sync_indices_from_tree_path if !tree_action_consumed && respond_to?(:sync_indices_from_tree_path)
    true

  when :table, :replace_mode
    # Handle table input only when a deck is selected.
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx   = @current_deck_idx || 0

    has_deck = @library.subjects[s_idx] &&
               @library.subjects[s_idx].sources[src_idx] &&
               @library.subjects[s_idx].sources[src_idx].decks[d_idx]

    if has_deck
      table_action_consumed = handle_table_input(key, focus_on_enter, modifiers)
      return true if table_action_consumed
    end
    false
  else
    # Bewaar de laatst bekende focus wanneer er geen componentroute past.
    @last_focus = focus_on_enter
    false
  end
end

# Verwerkt Ctrl+Shift+A en selecteert alle items binnen het actieve tabel- of boomgebied.

def handle_global_select_all_shortcut(key, key_raw_check, has_ctrl_check,
                                      has_shift_check, popup_is_active)
  return nil if popup_is_active

  is_ctrl_a = key_raw_check == 'a' && has_ctrl_check
  return nil unless is_ctrl_a

  # Ctrl+A blokkeren, Ctrl+Shift+A doorlaten.
  return nil if has_shift_check

  true
end

# Handle the r shortcut only when reset is safe in the current context.
def handle_global_reset_shortcut(key_raw_check, has_shift_check, has_ctrl_check, has_alt_check,
                                 popup_is_active, search_or_replace_active, is_already_studying)
  reset_allowed = key_raw_check == 'r' && !has_shift_check && !has_ctrl_check && !has_alt_check &&
                  !popup_is_active && !search_or_replace_active && !is_already_studying &&
                  %i[tree table].include?(@active_focus)
  return nil unless reset_allowed

  perform_reset
  true # Slik de resettoets direct in voor dit frame.
end

# Handle the d shortcut only when deduplication is safe in the current context.
def handle_global_dedup_shortcut(key_raw_check, has_shift_check, has_ctrl_check, has_alt_check,
                                 popup_is_active, search_or_replace_active, is_already_studying)
  dedup_allowed = key_raw_check == 'd' && !has_shift_check && !has_ctrl_check && !has_alt_check &&
                  !popup_is_active && !search_or_replace_active && !is_already_studying &&
                  %i[tree table].include?(@active_focus)
  return nil unless dedup_allowed

  perform_dedup
  true # Slik de deduplicatietoets direct in voor dit frame.
end

# Wisselt de zichtbaarheid van tabelscheidingslijnen en synchroniseert de tabel indien mogelijk.
def handle_table_divider_shortcut(key_raw_check, popup_is_active)
  return nil unless key_raw_check == '|' && !popup_is_active

  SoundManager.play(:toggle)
  @show_table_dividers = !@show_table_dividers
  true
end

# Handle the help shortcut, with a dedicated help menu during study sessions.

def handle_global_help_shortcut(key, modifiers, key_raw_check, has_ctrl_check, has_alt_check, popup_is_active)
  return nil unless key_raw_check == '?' && !has_ctrl_check && !has_alt_check

  study_modes = %i[drill quiz multiple_choice memory two_of_a_kind]

  if study_modes.include?(@current_study_mode)
    return true if popup_is_active

    open_study_session_help_popup
    return true
  end

  # Preserve the existing study-focus protection.
  return true if @active_focus == :study_focus_mode
  return true if popup_is_active

  captured_origin = defined?(@menu_origin_focus) && @menu_origin_focus ? @menu_origin_focus : nil
  captured_origin ||= defined?(@active_focus) && @active_focus != :command_mode ? @active_focus : :tree
  captured_origin = :table if defined?(@last_focus) && @last_focus == :table

  exit_global_search_mode

  return unless respond_to?(:open_help_popup, true)

  if @active_focus == :menu
    @active_menu_idx    = 1
    @active_submenu_idx = 0
    @menu_dropdown_open = true
    @focus_before_help  = :menu
    @menu_origin_focus  ||= :menu
  else
    @focus_before_help = :command_mode
    @menu_origin_focus = captured_origin
  end

  open_help_popup

  @last_focus   = :popup
  @active_focus = :popup

  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

# Start de gekozen studiemodus en controleert of er een geldig deck met kaarten is.
# Return true if the shortcut was handled; otherwise return nil so input can continue.
def handle_study_session_initialization(key_raw_check, has_alt_check, has_ctrl_check,
                                        popup_is_active, search_or_replace_active,
                                        is_already_studying, settings)
  # =========================================================================
  # 🎯 UNIVERSELE INITIALISATIE-POORT (ALT+1..4 EN 't' VOOR TIMED DRILL)
  # Gecentraliseerd aan de absolute voordeur: start vanuit tree én tabel!
  # =========================================================================
  is_alt_study_trigger = has_alt_check && %w[1 2 3 4 5].include?(key_raw_check)

  is_on_study_menu = (defined?(@active_focus) && @active_focus == :study_focus_mode) ||
                     (defined?(@last_focus) && @last_focus == :study_focus_mode)

  is_timed_drill_trigger = key_raw_check == 't' &&
                           !has_alt_check && !has_ctrl_check && is_on_study_menu

  if (is_alt_study_trigger || is_timed_drill_trigger) &&
     !popup_is_active && !search_or_replace_active && !is_already_studying

    # Studeren mag alleen starten als de tree daadwerkelijk op een deck staat.
    selected_path = @tree.respond_to?(:selected_path) ? @tree.selected_path : nil

    valid_tree_selection =
      @active_focus == :tree &&
      selected_path.is_a?(Array) &&
      selected_path.length == 3

    valid_table_selection = @active_focus == :table

    unless valid_tree_selection || valid_table_selection
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_study_session_error)}: #{settings.language_string(:statusbar_no_deck_selected)}!",
          type: :info
        )
      end

      return true
    end

    # Update the indices based on the selected tree path.
    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path, true)

    s_idx   = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx   = @current_deck_idx || 0

    active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

    if active_deck.nil? || active_deck.cards.nil? || active_deck.cards.empty?
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_study_session_error)}: #{settings.language_string(:statusbar_deck_empty)}!",
          type: :info
        )
      end

      return true
    end

    @selected_tree_paths = []
    @selected_table_rows = [] if defined?(@selected_table_rows)

    wipe_all_search_artifacts if respond_to?(:wipe_all_search_artifacts)
    study_strategy = settings.study_strategy || :fronts_random

    @cards_to_test = if active_deck.respond_to?(:study)
                       active_deck.study(study_strategy)
                     else
                       (active_deck.cards || []).dup
                     end

    # Memory gebruikt A-Z en 1-9 als coördinaten:
    # 26 letters × 9 cijfers = 234 posities.
    # Twee kaarten per paar = maximaal 117 paren.
    if key_raw_check == '4'
      max_memory_pairs = (26 * 9) / 2

      if @cards_to_test.length > max_memory_pairs
        @current_study_mode = nil

        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_study_session_error)}: #{settings.language_string(:statusbar_study_memory_limit_reached)}: #{max_memory_pairs}",
          type: :info
        )

        return true
      end
    end

    # Determine the selected study mode.
    @current_study_mode = if key_raw_check == 't'
                            :drill
                          else
                            case key_raw_check
                            when '1' then :drill
                            when '2' then :quiz
                            when '3' then :multiple_choice
                            when '4' then :memory
                            when '5' then :two_of_a_kind
                            end
                          end

    if %i[multiple_choice two_of_a_kind].include?(@current_study_mode) && active_deck.cards.length < 4
      @current_study_mode = nil
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_study_session_error)}: #{settings.language_string(:statusbar_min_req_cards)}!",
        type: :info
      )

      return true
    elsif @cards_to_test.nil? || @cards_to_test.empty? || (@current_study_mode == :multiple_choice && @cards_to_test.length < 4)
      @current_study_mode = nil
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_study_session_error)}: #{settings.language_string(:statusbar_not_enough_cards_selected)}!", type: :info
      )
      return true
    end

    @test_current_idx  = 0
    @test_show_meaning = false

    if @current_study_mode == :drill
      @test_awaiting_difficulty = false
      @active_focus = :study_focus_mode
      @last_focus   = :study_focus_mode

      # Registers instellen voor een progressbar
      deck_start_length        = @cards_to_test.length
      @test_progressbar_total  = deck_start_length
      @test_timer_paused       = false
      @test_time_was_up_notified = false
      @test_drill_elapsed      = 0

      # 🎯 SPEED SELECTION CORE DEFAULT:
      # We initialized the maximum ceiling firmly on 5 seconds out-of-the-box!
      @test_drill_timer_max    = 2 # De drill-timer staat standaard op 2 seconden als de gebruiker kiest voor stampen

      if key_raw_check == 't'
        @test_drill_timed = true
        @test_time_left   = @test_drill_timer_max # Uses the safe dynamic register!
      else
        @test_drill_timed = false
        @test_time_left   = 0
      end

      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return true
    end

    if @current_study_mode == :memory
      @test_awaiting_difficulty = false
      @active_focus = :study_focus_mode
      @last_focus   = :study_focus_mode

      initialize_memory_game(@cards_to_test)

      # Eén voortgangseenheid per paar, niet per losse kaart.
      @test_progressbar_total = @cards_to_test.length

      @test_drill_elapsed = 0
      @test_drill_timed = false
      @test_time_left = 0

      @test_timer_paused = false
      @test_finished_waiting = false
      @test_time_was_up_notified = false

      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return true
    end

    if @current_study_mode == :two_of_a_kind
      @test_awaiting_difficulty = false
      @active_focus = :study_focus_mode
      @last_focus   = :study_focus_mode

      # Initialiseer de kaarten voor Two of a Kind
      unless respond_to?(:initialize_two_of_a_kind, true) && initialize_two_of_a_kind(@cards_to_test)
        @current_study_mode = nil

        trigger_statusbar_message(
          'Two of a Kind kon niet worden gestart. Controleer of er voldoende kaarten beschikbaar zijn.',
          type: :info
        )

        return true
      end

      # 🎯 Borging tegen direct afsluiten
      @test_finished_waiting = false
      @test_time_was_up_notified = false
      @test_timer_paused = false

      @test_progressbar_total = @cards_to_test.length
      @test_drill_elapsed = 0.0
      @test_drill_timed = false
      @test_time_left = 0

      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return true
    end

    if @current_study_mode == :quiz || @current_study_mode == :multiple_choice
      @test_awaiting_difficulty = true
      @active_focus = :study_focus_mode
      @last_focus   = :study_focus_mode

      if respond_to?(:trigger_statusbar_message)
        trigger_statusbar_message("#{settings.language_string(:statusbar_difficulty)}: #{settings.language_string(:statusbar_levels)}.",
                                  type: :warning, beep: settings.beeps, expires: false)
      end
      return true
    end

    @active_focus = :study_focus_mode
    @last_focus = :study_focus_mode
    true
  elsif has_alt_check && %w[1 2 3 4].include?(key_raw_check) && is_already_studying
    true
  end
end

# Verwerkt de moeilijkheidskeuze aan het begin van een quiz-/studiesessie.
# Initialiseert timer, kaartvolgorde en eventuele meerkeuzeopties; geeft nil terug
# wanneer de sessie niet op een moeilijkheidskeuze wacht.
def handle_study_difficulty_input(key_raw_check, settings)
  return nil unless defined?(@test_awaiting_difficulty) && @test_awaiting_difficulty

  key_raw_check = key_raw_check.to_s
  return true unless %w[1 2 3].include?(key_raw_check)

  # Statusbalk onmiddellijk wissen
  @status_message = nil
  @status_message_expires_at = nil

  secs_per_card = case key_raw_check
                  when '1' then 6
                  when '3' then 3
                  else 4
                  end

  @test_current_idx  = 0
  @test_show_meaning = false

  study_strategy = settings.study_strategy || :fronts_random

  @test_card_directions = []

  @cards_to_test.each_with_index do |_, idx|
    direction = case study_strategy
                when :backs_random
                  :back
                when :alternately_fronts_and_backs_random
                  idx.even? ? :front : :back
                when :everything_random
                  rand < 0.5 ? :front : :back
                else
                  :front
                end

    @test_card_directions << direction
  end

  deck_start_length = @cards_to_test.length

  @test_progressbar_total = deck_start_length
  @test_time_left = deck_start_length * secs_per_card

  @test_timer_paused = false
  @test_time_was_up_notified = false
  @test_awaiting_difficulty = false

  @active_cards_cache_node  = nil
  @active_cards_cache_cards = nil

  if @current_study_mode == :multiple_choice &&
     respond_to?(:initialize_multiple_choice_options, true)

    @test_mc_current_card_anchor = nil
    initialize_multiple_choice_options
  end

  # tussenscherm activeren en aftelling starten
  @test_starting = true
  @test_start_countdown = 3

  @test_start_countdown_deadline =
    Process.clock_gettime(Process::CLOCK_MONOTONIC) + 1.0

  # Start sound without blocking the event loop.
  @test_start_sound = SoundManager.play(:start)

  @test_start_sound_deadline = if @test_start_sound && @test_start_sound.respond_to?(:duration)
                                 Process.clock_gettime(Process::CLOCK_MONOTONIC) +
                                   @test_start_sound.duration
                               else
                                 Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.5
                               end

  true
end

# Verwerkt navigatietoetsen voor actieve zoekresultaten in de boomstructuur of tabel.
# Geeft true terug als de zoeknavigatie de toets heeft afgehandeld; anders nil.
def handle_search_navigation_gateway(key, key_str, inline_raw_key, has_ctrl, has_shift)
  # =========================================================================
  # 🎯 UNIVERSELE GLOBAL SEARCH NAVIGATIE BRANDMUUR (Gecorrigeerde Toetsen Sync)
  # 👉 RESOLVED: Always recognize all Up/Down variants,
  #    inclusief symbolen en de Ctrl+P alias van de hoofd-lus!
  # =========================================================================
  if defined?(@global_search_active) && @global_search_active
    target_key = key_str.to_s.strip.downcase
    raw_key_string = key.to_s.strip.downcase

    exit_global_search_mode if (target_key == ':' || key == ':') && respond_to?(:exit_global_search_mode, true)

    # Vang alle mogelijke navigatie-inputs (strings én symbolen) viltstrak af
    shift_active = (has_shift == true) || (defined?(@has_shift) && @has_shift)

    is_search_action = %w[n j k up down].include?(target_key) ||
                       %w[n j k up down].include?(raw_key_string) ||
                       %i[n N up down].include?(key) ||
                       inline_raw_key == 'N'

    if is_search_action
      handle_search_match_navigation(key, has_shift)
      return true # Slik de toets direct hard in voor het all-decks proces!
    end
  end

  # =========================================================================
  # 💤 NIET VERVANGEN: Originele lokale fallbacks voor normale Search/Replace
  # =========================================================================
  is_search_nav_key = %w[n g up down j k home end].include?(key_str) ||
                      key_str == 'n' || key_str == 'g' ||
                      inline_raw_key == 'N' || inline_raw_key == 'G' ||
                      %i[n N up down home end].include?(key)

  return nil unless is_search_nav_key && !has_ctrl

  allow_search_navigation = false

  if @active_focus == :tree && @tree_search_matches && @tree_search_matches.any?
    allow_search_navigation = true
  elsif @active_focus == :replace_mode && @last_focus == :tree && @tree_search_matches && @tree_search_matches.any?
    allow_search_navigation = true
  elsif (@active_focus == :table || @active_focus == :replace_mode) && @search_matches && @search_matches.any?
    allow_search_navigation = inline_raw_key == 'N' || key_str == 'n' || key_str == 'N'
  end

  return nil unless allow_search_navigation

  handle_search_match_navigation(key, has_shift)
  true
end

# Stuurt PageUp/PageDown (en Ctrl-U/Ctrl-D/Ctrl-V/Alt-V) rechtstreeks naar de
# tree handler before running the general navigation router.
def handle_tree_page_navigation_input(key, normalized_page_key, has_ctrl, has_alt, has_shift)
  normalized_key = key.to_s.strip.downcase
  page_key = %w[page_up pageup page_down pagedown page-down].include?(normalized_page_key) ||
             %w[page_up pageup page_down pagedown page-down].include?(normalized_key) ||
             (has_ctrl && %w[u d v].include?(normalized_key)) ||
             (has_alt && %w[v].include?(normalized_key))

  return nil unless page_key && @active_focus == :tree &&
                    respond_to?(:handle_tree_page_navigation, true)

  consumed = handle_tree_page_navigation(key, normalized_key, has_ctrl, has_alt, has_shift)
  return nil unless consumed

  sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
  true
end

# Rondt een voltooide leersessie af of verwerkt Escape tijdens een actieve leersessie.
# Retourneert true als deze functie de toets heeft afgehandeld; anders nil.
def handle_study_session_exit(key, modifiers, is_escape_action)
  # Active only when the study session is running or has focus.
  return nil unless @active_focus == :study_focus_mode ||
                    (defined?(@current_study_mode) && @current_study_mode)

  # Scenario A: de leersessie is voltooid en wacht op een toets om af te sluiten.
  if defined?(@test_finished_waiting) && @test_finished_waiting == true
    @status_message = nil if instance_variable_defined?(:@status_message)
    @status_message_expires_at = nil if instance_variable_defined?(:@status_message_expires_at)
    exit_test_study_session if respond_to?(:exit_test_study_session)
    @test_finished_waiting     = nil
    @test_time_was_up_notified = nil
    @current_study_mode        = nil

    # Bepaal waar de gebruiker na de leersessie naar terug moet.
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx) if defined?(@library)

    target_origin = if defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor &&
                       @cockpit_panel_anchor != :study_focus_mode
                      @cockpit_panel_anchor
                    elsif active_deck && active_deck.cards && !active_deck.cards.empty?
                      :table
                    else
                      :tree
                    end

    @active_focus = target_origin
    @last_focus = target_origin
    @cockpit_panel_anchor = nil

    return true
  end

  # Scenario B: Escape breekt een nog actieve leersessie af.
  if is_escape_action
    # Laat het studie-helpmenu door naar de normale popup-afhandeling.
    active_popup = @popup&.active_popup

    return nil if active_popup && active_popup[:type] == :study_session_help

    # Andere actieve popups blijven hun bestaande Escape-afhandeling gebruiken.
    return true if active_popup && handle_popup_input(key, modifiers)

    # Startgeluid onmiddellijk stoppen.
    SoundManager.stop(:start)

    # Startprocedure annuleren.
    @test_start_sound = nil
    @test_start_sound_deadline = nil
    @test_start_countdown_deadline = nil
    @test_starting = false

    exit_test_study_session if respond_to?(:exit_test_study_session, true)

    @test_awaiting_difficulty = false
    @status_message            = nil
    @status_message_expires_at = nil
    @current_study_mode = nil

    # Bepaal het paneel waarnaar de gebruiker moet terugkeren.
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx) if defined?(@library)

    target_origin = if defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor &&
                       @cockpit_panel_anchor != :study_focus_mode
                      @cockpit_panel_anchor
                    elsif active_deck && active_deck.cards && !active_deck.cards.empty?
                      :table
                    else
                      :tree
                    end

    @active_focus = target_origin
    @last_focus = target_origin
    @cockpit_panel_anchor = nil
    @command_mode_visible = false

    return true
  end

  # Geen van de situaties hierboven was van toepassing; laat de toets verdergaan.
  nil
end

# Verwerkt de y/n/Escape-bevestiging voor een bulk-reset.
def handle_bulk_reset_confirmation(key)
  return nil unless defined?(@awaiting_bulk_reset_confirm) && @awaiting_bulk_reset_confirm == true

  return unless defined?(@awaiting_bulk_reset_confirm) && @awaiting_bulk_reset_confirm == true

  key_str = key.to_s.strip.downcase
  settings = AppConfig.settings

  # 🔑 NATIVE KEY CONTEXT DISPATCHER
  # Safely extracts pure raw escape sequence conditions
  is_escape_key = key == :escape || %w[escape esc \e].include?(key_str) || key == "\e"

  if key_str == 'y'
    # 🟢 ACCEPTED: Purge registers and execute flashcard reset with bang override forced
    @awaiting_bulk_reset_confirm = nil
    @awaiting_bulk_reset_confirm_name = nil
    perform_reset(true)
    true

  elsif key_str == 'n' || is_escape_key
    # 🔴 CANCELLED VIA 'N' OR ESCAPE: Instantly fold up the status bar and restore focus!
    @awaiting_bulk_reset_confirm = nil
    @awaiting_bulk_reset_confirm_name = nil

    clear_command_mode_visuals
    @command_mode_visible = false
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Smoothly route user navigation straight back to their last active window component
    @active_focus = defined?(@last_focus) && @last_focus && @last_focus != :command_mode ? @last_focus : :tree
    @last_focus = @active_focus
    @status_message = nil
    true

  else
    # 🔒 LOCKOUT STANDARD: Freeze any other floating characters out of the input line
    trigger_statusbar_message("#{settings.language_string(:statusbar_reset_all_in)} \"#{@awaiting_bulk_reset_confirm_name}\"? (y/n)",
                              type: :warning, expires: false)
    true
  end
end

# Handle the y/n/Escape confirmation for deleting duplicate cards.
def handle_bulk_dedup_confirmation(key)
  return nil unless defined?(@awaiting_bulk_dedup_confirm) && @awaiting_bulk_dedup_confirm == true

  return unless defined?(@awaiting_bulk_dedup_confirm) && @awaiting_bulk_dedup_confirm == true

  key_str = key.to_s.strip.downcase
  settings = AppConfig.settings
  is_escape_key = key == :escape || %w[escape esc \e].include?(key_str) || key == "\e"

  if key_str == 'y'
    # 🟢 ACCEPTED: Clear the state and run perform_dedup with the forced override.
    @awaiting_bulk_dedup_confirm = nil
    @awaiting_bulk_dedup_confirm_name = nil
    perform_dedup(true)
    true

  elsif key_str == 'n' || is_escape_key
    # 🔴 GEANNULEERD VIA 'N' OF ESCAPE: Klap de statusbalk in en herstel de focus rustig!
    @awaiting_bulk_dedup_confirm = nil
    @awaiting_bulk_dedup_confirm_name = nil

    clear_command_mode_visuals
    @command_mode_visible = false
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @status_message = nil

    @active_focus = defined?(@last_focus) && @last_focus && @last_focus != :command_mode ? @last_focus : :tree
    @last_focus = @active_focus

    true

  else
    # 🔒 LOCKOUT STANDARD: Slik alle andere letters/cijfers/backspaces geruisloos in
    if respond_to?(:trigger_statusbar_message, true)
      trigger_statusbar_message("#{settings.language_string(:statusbar_remove_duplicates_from)} \"#{@awaiting_bulk_dedup_confirm_name}\"? (y/n)",
                                type: :warning, expires: false)
    end
    true
  end
end

# Verwerkt toetsen en bevestigingsprompts wanneer de command/statusbalk focus heeft.
def handle_command_mode_input(key, modifiers, has_ctrl_check, has_alt_check, has_shift_check)
  return nil unless defined?(@active_focus) && @active_focus == :command_mode

  exit_global_search_mode

  settings = AppConfig.settings

  return unless defined?(@active_focus) && @active_focus == :command_mode

  has_active_prompt = (defined?(@last_warned_file) && !@last_warned_file.nil?) ||
                      (defined?(@awaiting_import_confirmation) && !@awaiting_import_confirmation.nil?) ||
                      (defined?(@awaiting_export_format_selection) && !@awaiting_export_format_selection.nil?) ||
                      (defined?(@awaiting_export_header_selection) && !@awaiting_export_header_selection.nil?) ||
                      (defined?(@awaiting_duplicate_scope) && !@awaiting_duplicate_scope.nil?) ||
                      (defined?(@awaiting_duplicate_confirm) && !@awaiting_duplicate_confirm.nil?)

  if has_active_prompt
    clean_key = key.to_s.strip.sub(/\A:/, '').downcase

    is_legal = if defined?(@awaiting_export_format_selection) && !@awaiting_export_format_selection.nil?
                 %w[1 2].include?(clean_key)
               elsif defined?(@awaiting_duplicate_scope) && !@awaiting_duplicate_scope.nil?
                 %w[1 2].include?(clean_key) # 🎯 1 of 2 toegestaan voor de scope
               else
                 %w[y n].include?(clean_key)
               end

    # afbreken van propmts (:expires = false etc.)
    if %w[escape esc \e].include?(clean_key) || key == :escape
      @last_warned_file = nil
      @awaiting_import_confirmation = nil
      @awaiting_export_format_selection = nil
      @awaiting_export_header_selection = nil
      @awaiting_duplicate_scope = nil
      @awaiting_duplicate_confirm = nil
      @status_message = nil if defined?(@status_message)

      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)

      return true
    end

    if is_legal
      execute_statusbar_command(clean_key) if respond_to?(:execute_statusbar_command)
      return true
    else
      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)

      if respond_to?(:trigger_statusbar_message, true)
        if defined?(@awaiting_export_format_selection) && !@awaiting_export_format_selection.nil?
          trigger_statusbar_message("#{settings.language_string(:statusbar_choose_format)}: #{settings.language_string(:statusbar_format)}", type: :warning, beep: settings.beeps,
                                                                                                                                             expires: false)
        elsif defined?(@awaiting_export_header_selection) && !@awaiting_export_header_selection.nil?
          trigger_statusbar_message(settings.language_string(:statusbar_include_header), type: :warning,
                                                                                         beep: settings.beeps, expires: false)
        elsif defined?(@awaiting_import_confirmation) && !@awaiting_import_confirmation.nil?
          trigger_statusbar_message("#{settings.language_string(:statusbar_deck_not_empty)}!", type: :warning,
                                                                                               beep: settings.beeps, expires: false)
        else
          trigger_statusbar_message(settings.language_string(:statusbar_unexpected_extension),
                                    type: :warning, beep: settings.beeps, expires: false)
        end
      end
      return true
    end
  end

  if defined?(@status_message) && @status_message
    @status_message = nil # ➔ ...wist een willekeurige toets de melding...
    return true           # ➔ ...en breekt hij HIER direct af!
  end

  @statusbar_field.is_focused = true if defined?(@statusbar_field) && @statusbar_field
  raw_key_str = key.to_s.strip

  is_enter_trigger = %w[enter \r \n].include?(raw_key_str.downcase) || key == :enter
  is_escape_trigger = %w[escape esc].include?(raw_key_str.downcase) || key == :escape

  if is_enter_trigger
    command_text =
      if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.text.to_s.strip
      else
        ''
      end

    command_success = if respond_to?(:execute_statusbar_command, true)
                        execute_statusbar_command(command_text)
                      else
                        false
                      end

    if command_success
      @statusbar_field.is_focused = false
      @statusbar_field.text = ''

      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)

      @active_focus = @menu_origin_focus || :tree
      @last_focus = @active_focus
      @menu_origin_focus = nil
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  elsif is_escape_trigger
    SoundManager.play(:switch)
    trigger_rotation_indicator
    @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)

    @active_focus = @menu_origin_focus || @last_focus || :tree
    @active_focus = :tree if %i[menu popup command_mode].include?(@active_focus)

    @last_focus   = @active_focus

    @menu_origin_focus = nil
    @focus_before_help = nil if defined?(@focus_before_help)
    @command_mode_visible = false

    true
  else
    # 🚀 EMACS & NAVIGATION PASS-THROUGH VALVE:
    # If control keys or navigational shortcuts are pressed, we pass the raw 'key' character
    # ('a', 'e', 'u', 'k') with its modifiers array directly to RatinField.
    # This breaks the global select-all and edit blocks instantly! [5]

    if defined?(@statusbar_field) && @statusbar_field && @statusbar_field.respond_to?(:handle_key, true)
      any_key = raw_key_str.sub(/\A:/, '')

      is_control_shortcut = has_ctrl_check || has_alt_check || has_shift_check
      is_nav_word_trigger = %w[backspace left right home end delete tab].include?(any_key.downcase)

      if is_control_shortcut || is_nav_word_trigger
        @statusbar_field.handle_key(key, modifiers)
      elsif any_key.length == 1
        @statusbar_field.handle_key('Char(\'' + any_key + '\')', modifiers)
      else
        # 🟢 Dit stuurt symbolen zoals :up of :down inclusief ["meta"]/["cmd"] direct door!
        @statusbar_field.handle_key(key, modifiers)
      end

    end

    true
  end
end

# Verwerkt globale sneltoetsen voor scheidingslijnen, help, selectie, reset en deduplicatie.
def handle_global_input_shortcuts(key, modifiers, key_raw_check, has_ctrl_check, has_alt_check,
                                  has_shift_check, popup_is_active, search_or_replace_active,
                                  is_already_studying)
  return nil if key_raw_check.nil?

  # Verwerk het wisselen van tabelscheidingslijnen apart.
  return true if handle_table_divider_shortcut(key_raw_check, popup_is_active)

  # Handle the help shortcut separately to keep other global shortcuts clear.
  return true if handle_global_help_shortcut(
    key, modifiers, key_raw_check, has_ctrl_check, has_alt_check, popup_is_active
  )

  # Houd selectie, reset en deduplicatie elk in een eigen, gerichte helper.
  return true if handle_global_select_all_shortcut(
    key, key_raw_check, has_ctrl_check, has_shift_check, popup_is_active
  )
  return true if handle_global_reset_shortcut(
    key_raw_check, has_shift_check, has_ctrl_check, has_alt_check,
    popup_is_active, search_or_replace_active, is_already_studying
  )
  return true if handle_global_dedup_shortcut(
    key_raw_check, has_shift_check, has_ctrl_check, has_alt_check,
    popup_is_active, search_or_replace_active, is_already_studying
  )

  nil
end

# Reset only the selected rows in the table.

def handle_selected_table_reset
  return false unless @active_focus == :table && defined?(@selected_table_rows) && @selected_table_rows.any?

  settings = AppConfig.settings
  s_idx = @current_subject_idx || 0
  src_idx = @current_source_idx || 0
  d_idx = @current_deck_idx || 0
  active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
  return false unless active_deck && active_deck.cards

  target_cards = @selected_table_rows.map { |idx| active_deck.cards[idx] }.compact
  reset_count = 0
  snapshot_taken = false

  target_cards.each do |card|
    next unless card.respond_to?(:study) && [false, 'false'].include?(card.study)

    unless snapshot_taken
      allow_snapshot!
      save_history_snapshot
      snapshot_taken = true
    end

    card.study = true
    reset_count += 1
  end

  @library_dirty = true if reset_count.positive?
  @selected_table_rows = []
  clear_command_mode_visuals
  @command_mode_visible = false
  @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
  trigger_statusbar_message(
    "#{reset_count} #{settings.language_string(:statusbar_reset_success)}: \"#{active_deck.name}\"!",
    type: :info
  )
  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

# Reset de kaarten in het gekozen deck, de bron of het onderwerp.
# Geeft het aantal kaarten terug dat vóór de reset als geleerd stond geregistreerd.
def reset_cards_for_target(target_type, active_deck, active_source, active_subject)
  total_reset_cards = 0

  case target_type
  when :deck
    if active_deck
      total_reset_cards += count_memorised_cards([active_deck])
      active_deck.reset
    end
  when :source
    if active_source && active_source.decks
      total_reset_cards += count_memorised_cards(active_source.decks)
      active_source.decks.each(&:reset)
    end
  when :subject
    if active_subject && active_subject.sources
      active_subject.sources.each do |src|
        if src.decks
          total_reset_cards += count_memorised_cards(src.decks)
          src.decks.each(&:reset)
        end
      end
    end
  end

  total_reset_cards
end

def handle_selected_tree_multi_reset(settings)
  total_reset_cards = 0
  snapshot_taken = false

  @selected_tree_paths.each do |path|
    next unless path.is_a?(Array)

    subject = @library.subjects.find { |s| s.id.to_s == path[0].to_s }
    next unless subject

    target_decks = case path.length
                   when 1
                     subject.sources.flat_map { |src| src.decks || [] }
                   when 2
                     source = subject.sources.find { |src| src.id.to_s == path[1].to_s }
                     source ? (source.decks || []) : []
                   when 3
                     source = subject.sources.find { |src| src.id.to_s == path[1].to_s }
                     deck = source&.decks&.find { |d| d.id.to_s == path[2].to_s }
                     deck ? [deck] : []
                   else
                     []
                   end

    target_decks.each do |deck|
      reset_count = count_memorised_cards([deck])
      next unless reset_count.positive?

      unless snapshot_taken
        allow_snapshot!
        save_history_snapshot
        snapshot_taken = true
      end

      deck.reset
      total_reset_cards += reset_count
    end
  end

  @library_dirty = true if total_reset_cards.positive?
  @selected_tree_paths = []

  clear_command_mode_visuals if respond_to?(:clear_command_mode_visuals, true)
  @command_mode_visible = false
  @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

  if total_reset_cards.zero?
    trigger_statusbar_message(
      "#{settings.language_string(:statusbar_nothing_to_reset_in)} #{settings.language_string(:statusbar_selected_items)}!",
      type: :info
    )
  else
    trigger_statusbar_message(
      "#{total_reset_cards} #{settings.language_string(:statusbar_reset_success)} #{settings.language_string(:statusbar_selected_items)}!",
      type: :info
    )
  end

  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

def perform_reset(has_bang_override = false)
  settings = AppConfig.settings

  # Handle table selection separately; on success, the tree does not need to be checked.
  return true if handle_selected_table_reset

  # 🌲 🎯 TREE MULTI-SELECT GATEWAY:
  # Als er met shift meerdere items zijn gemarkeerd in de boomstructuur, verwerken we die hier direct!
  if @active_focus == :tree && defined?(@selected_tree_paths) && @selected_tree_paths.any? && handle_selected_tree_multi_reset(settings)
    return true
  end

  # 1. Inspecteer de geografische selectiestand van de boomstructuur
  selected_path = @tree.respond_to?(:selected_path) ? @tree.selected_path : nil
  path_length = selected_path.is_a?(Array) ? selected_path.length : 0

  return false if path_length.zero?

  # 2. Get the active objects and the selected item's name.
  active_subject = @library.subjects[@current_subject_idx || 0]
  active_source  = active_subject&.sources&.[](@current_source_idx || 0)
  active_deck    = active_source&.decks&.[](@current_deck_idx || 0)

  target_name = ''
  target_type = :deck

  case path_length
  when 1
    target_name = active_subject&.name.to_s
    target_type = :subject
  when 2
    target_name = active_source&.name.to_s
    target_type = :source
  when 3
    target_name = active_deck&.name.to_s
    target_type = :deck
  end

  if %i[subject source].include?(target_type) && !has_bang_override
    # Check if the user is currently typing a command string in the entry field
    is_typing_command = defined?(@command_mode_visible) && @command_mode_visible &&
                        @statusbar_field.respond_to?(:text) && !@statusbar_field.text.to_s.empty?

    if is_typing_command
      # Scenario A: User typed raw ':reset' -> Enforce standard Vim-bang error block
      trigger_statusbar_message(
        "\"#{target_name}\" #{settings.language_string(:statusbar_contains_sub_decks)}!",
        type: :warning
      )
      @active_focus = :command_mode
      @command_mode_visible = true
      return false
    else
      # Scenario B: User hit the 'r' key -> Detour cleanly into the y/n prompt loop!
      @awaiting_bulk_reset_confirm = true
      @awaiting_bulk_reset_confirm_name = target_name
      @active_focus = :command_mode
      @command_mode_visible = true # Keeps the bar awake to receive 'y' or 'n'

      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_reset_all_in)} \"#{target_name}\"? (y/n)",
        type: :warning,
        expires: false
      )

      return false
    end
  end

  total_reset_cards = count_memorised_cards(
    case target_type
    when :deck
      [active_deck].compact
    when :source
      active_source ? active_source.decks : []
    when :subject
      active_subject ? active_subject.sources.flat_map { |src| src.decks || [] } : []
    else
      []
    end
  )

  if total_reset_cards.positive?
    allow_snapshot!
    save_history_snapshot
    reset_cards_for_target(target_type, active_deck, active_source, active_subject)
  end

  # 5. SUCCES FEEDBACK
  clear_command_mode_visuals

  origin_focus = if defined?(@last_focus) && @last_focus && @last_focus != :command_mode
                   @last_focus
                 elsif defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor
                   @cockpit_panel_anchor
                 else
                   :tree # Safe global fallback standard
                 end

  @library_dirty = true if total_reset_cards.positive?
  @active_focus = origin_focus
  @last_focus = origin_focus

  @command_mode_visible = false
  @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

  if total_reset_cards.zero?
    trigger_statusbar_message(
      "#{settings.language_string(:statusbar_nothing_to_reset_in)}: \"#{target_name}\"!",
      type: :info
    )
  else
    trigger_statusbar_message(
      "#{total_reset_cards} #{settings.language_string(:statusbar_reset_success)}: \"#{target_name}\"!",
      type: :info
    )
  end

  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

# Remove duplicates only within the selected table rows.
def handle_selected_table_dedup
  return false unless @active_focus == :table && defined?(@selected_table_rows) && @selected_table_rows.any?

  settings = AppConfig.settings
  s_idx = @current_subject_idx || 0
  src_idx = @current_source_idx || 0
  d_idx = @current_deck_idx || 0
  active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
  return false unless active_deck && active_deck.cards

  target_cards = @selected_table_rows.map { |idx| active_deck.cards[idx] }.compact
  seen = {}
  duplicates_removed = 0
  snapshot_taken = false

  target_cards.each do |card|
    sig = "#{card.term.to_s.strip}|#{card.context.to_s.strip}|#{card.meaning.to_s.strip}"

    if seen[sig]
      unless snapshot_taken
        allow_snapshot!
        save_history_snapshot
        snapshot_taken = true
      end

      active_deck.cards.delete(card)
      duplicates_removed += 1
    else
      seen[sig] = true
    end
  end

  @library_dirty = true if duplicates_removed.positive?
  @selected_table_rows = []
  clear_command_mode_visuals
  @command_mode_visible = false
  @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
  if duplicates_removed > 0
    trigger_statusbar_message(
      "#{duplicates_removed} #{settings.language_string(:statusbar_duplicates_removed_from)}: \"#{active_deck.name}\"!", type: :info
    )
  else
    trigger_statusbar_message("#{settings.language_string(:statusbar_no_duplicates_found_in_selection)}!", type: :info)
  end
  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

def handle_selected_tree_multi_dedup(settings)
  total_duplicates_removed = 0
  snapshot_taken = false

  @selected_tree_paths.each do |path|
    next unless path.is_a?(Array)

    subject = @library.subjects.find { |s| s.id.to_s == path[0].to_s }
    next unless subject

    selected_decks = case path.length
                     when 1
                       subject.sources.flat_map { |src| src.decks || [] }
                     when 2
                       source = subject.sources.find { |src| src.id.to_s == path[1].to_s }
                       source ? (source.decks || []) : []
                     when 3
                       source = subject.sources.find { |src| src.id.to_s == path[1].to_s }
                       deck = source&.decks&.find { |d| d.id.to_s == path[2].to_s }
                       deck ? [deck] : []
                     else
                       []
                     end

    selected_decks.each do |deck|
      next unless deck.respond_to?(:cards) && deck.respond_to?(:remove_duplicates!)

      duplicate_count = deck.cards.length - deck.cards.map do |card|
        "#{card.term.to_s.strip}|#{card.context.to_s.strip}|#{card.meaning.to_s.strip}"
      end.uniq.length

      next unless duplicate_count.positive?

      unless snapshot_taken
        allow_snapshot!
        save_history_snapshot
        snapshot_taken = true
      end

      total_duplicates_removed += deck.remove_duplicates!
    end
  end

  @library_dirty = true if total_duplicates_removed.positive?
  @selected_tree_paths = []

  clear_command_mode_visuals if respond_to?(:clear_command_mode_visuals, true)
  @command_mode_visible = false
  @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

  if total_duplicates_removed.zero?
    main_msg = settings.language_string(:statusbar_no_duplicates_found_in).to_s
    suffix = settings.language_string(:statusbar_selected_items).to_s
    trigger_statusbar_message("#{main_msg} #{suffix}!", type: :info)
  else
    main_msg = settings.language_string(:statusbar_duplicates_removed_from).to_s
    suffix = settings.language_string(:statusbar_selected_items).to_s
    trigger_statusbar_message("#{total_duplicates_removed} #{main_msg} #{suffix}!", type: :info)
  end

  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

def perform_dedup(has_bang_override = false)
  settings = AppConfig.settings

  # Verwerk tabelselecties in een aparte helper.
  return true if handle_selected_table_dedup

  # 🌲 🎯 TREE MULTI-SELECT GATEWAY (DEDUP):
  # Als er met shift meerdere items zijn gemarkeerd in de boomstructuur, voeren we hier de bulk-dedup uit!
  if @active_focus == :tree && defined?(@selected_tree_paths) && @selected_tree_paths.any? && handle_selected_tree_multi_dedup(settings)
    return true
  end

  # 1. Inspecteer de geografische selectiestand van de boomstructuur
  selected_path = @tree.respond_to?(:selected_path) ? @tree.selected_path : nil
  path_length = selected_path.is_a?(Array) ? selected_path.length : 0

  return false if path_length.zero?

  # 2. Get the active objects and the selected item's name.
  active_subject = @library.subjects[@current_subject_idx || 0]
  active_source  = active_subject&.sources&.[](@current_source_idx || 0)
  active_deck    = active_source&.decks&.[](@current_deck_idx || 0)

  target_name = ''
  target_type = :deck

  case path_length
  when 1
    target_name = active_subject&.name.to_s
    target_type = :subject
  when 2
    target_name = active_source&.name.to_s
    target_type = :source
  when 3
    target_name = active_deck&.name.to_s
    target_type = :deck
  end

  if %i[subject source].include?(target_type) && !has_bang_override
    is_typing_command = defined?(@command_mode_visible) && @command_mode_visible &&
                        @statusbar_field.respond_to?(:text) && !@statusbar_field.text.to_s.empty?

    if is_typing_command
      # Genereert exact dezelfde waarschuwing dat de map sub-decks bevat
      trigger_statusbar_message("\"#{target_name}\" #{settings.language_string(:statusbar_contains_sub_decks)}!",
                                type: :warning)
      @active_focus = :command_mode
      @command_mode_visible = true
      return false
    else
      # Symmetrische omleiding naar de y/n prompt voor dedup
      @awaiting_bulk_dedup_confirm = true
      @awaiting_bulk_dedup_confirm_name = target_name
      @active_focus = :command_mode
      @command_mode_visible = true

      trigger_statusbar_message("#{settings.language_string(:statusbar_remove_duplicates_from)} \"#{target_name}\"? (y/n)", type: :warning,
                                                                                                                            expires: false)
      return false
    end
  end

  # 4. UITVOERING: deduplicatie met één snapshot bij echte wijzigingen
  total_duplicates_removed = 0
  snapshot_taken = false

  selected_decks = case target_type
                   when :deck
                     active_deck ? [active_deck] : []
                   when :source
                     active_source ? (active_source.decks || []) : []
                   when :subject
                     active_subject ? active_subject.sources.flat_map { |src| src.decks || [] } : []
                   else
                     []
                   end

  selected_decks.each do |deck|
    next unless deck.respond_to?(:cards) && deck.respond_to?(:remove_duplicates!)

    duplicate_count = deck.cards.length - deck.cards.map do |card|
      "#{card.term.to_s.strip}|#{card.context.to_s.strip}|#{card.meaning.to_s.strip}"
    end.uniq.length

    next unless duplicate_count.positive?

    unless snapshot_taken
      allow_snapshot!
      save_history_snapshot
      snapshot_taken = true
    end

    total_duplicates_removed += deck.remove_duplicates!
  end

  # 5. SUCCES FEEDBACK
  clear_command_mode_visuals

  origin_focus = if defined?(@last_focus) && @last_focus && @last_focus != :command_mode
                   @last_focus
                 elsif defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor
                   @cockpit_panel_anchor
                 else
                   :tree
                 end

  @library_dirty = true if total_duplicates_removed.positive?
  @active_focus = origin_focus
  @last_focus = origin_focus

  @command_mode_visible = false
  @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

  if total_duplicates_removed.zero?
    trigger_statusbar_message("#{settings.language_string(:statusbar_no_duplicates_found_in)}: \"#{target_name}\"!",
                              type: :info)
  else
    trigger_statusbar_message(
      "#{total_duplicates_removed} #{settings.language_string(:statusbar_duplicates_removed_from)}: \"#{target_name}\"!", type: :info
    )
  end

  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end

# Helper om het exacte aantal gememoriseerde (study == false) kaarten vooraf te tellen
# reset_cards_for_target returns a number: the count of cards whose study value was false (or text such as "false") before reset.
def count_memorised_cards(decks_array)
  Array(decks_array).sum do |deck|
    Array(deck.cards).count do |card|
      card.respond_to?(:study) &&
        card.study.to_s.strip.casecmp?('false')
    end
  end
end

# =========================================================================
# 🎯 BULK SELECT ALL ENGINES (TABLE & TREE SCOPE PARTITY)
# Instantly marks all rows or paths for group modifications / deletions.
# =========================================================================

# 📊 1. TABLE: Selects all rows within the currently loaded deck
def execute_table_select_all
  s_idx   = @current_subject_idx || 0
  src_idx = @current_source_idx || 0
  d_idx   = @current_deck_idx || 0
  active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)

  return false if active_deck.nil? || active_deck.cards.nil? || active_deck.cards.empty?

  # Initialize the array if it doesn't exist yet
  @selected_table_rows ||= []

  # Fill it cleanly with every row index (0 up to the last card)
  @selected_table_rows = (0...active_deck.cards.length).to_a

  # Trigger a live terminal refresh so the selection checkboxes blink onto the screen
  true
end

# =========================================================================
# 🌲 2. TREE SELECT ALL (GLOBAL SIDEBAR OVERRIDE)
# Instantly range-selects EVERY SINGLE item currently visible or expanded
# in your tree sidebar for global bulk operations / multi-deletions.
# =========================================================================
def execute_tree_select_all
  return false unless @tree && @tree.respond_to?(:visible_nodes)

  visible_nodes = @tree.visible_nodes || []
  return false if visible_nodes.empty?

  # Initialize or reset the active sidebar selection track
  @selected_tree_paths ||= []

  # 🎯 FIX: Loop through every visible terminal node on screen and ingest its path.
  # This immediately overrides individual boundary checks so that all rows highlight at once!
  visible_nodes.each do |node|
    path = node[:path]
    @selected_tree_paths << path if path && !@selected_tree_paths.include?(path)
  end

  # Set the range anchor directly to the bottom line to keep the engine stable
  @tree_selection_anchor_index = visible_nodes.length - 1

  # Dwing een vloeibare hertekening van de boomstructuur cockpit af
  @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  true
end
