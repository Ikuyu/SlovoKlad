require_relative '../../lib/ratin_checkbox'

module PopupInputHandler
  public

  def notify_search_replace_no_result
    settings = AppConfig.settings
    trigger_statusbar_message(
      "#{settings.language_string(:statusbar_search_error)}: #{settings.language_string(:statusbar_no_results_found)}!",
      type: :info
    )
  end

  def wipe_all_search_artifacts
    # 1. Ruim alle actieve lokale tabel-zoekacties en transformatie-registers op
    if @search_matches || @last_search_query
      @search_matches           = nil
      @search_current_match_idx = nil
      @last_search_query        = nil
      @last_replace_text        = nil
      @last_case_sensitive      = nil
      @last_regex               = nil
    end

    # 2. Ruim alle actieve boomstructuur-zoekacties en zijbalk-registers op
    if @tree_search_matches || @last_tree_search_query
      @tree_search_matches     = nil
      @tree_search_current_idx = nil
      @last_tree_search_query  = nil
    end

    # 3. 🎯 DE NIEUWE SYSTEM-WIDE SEARCH EN STATUSBAR REPARATIE:
    # Clear all state from the All-Decks search here.
    @global_search_active           = false
    @global_search_query            = nil
    @global_search_matches          = []
    @global_search_matched_deck_ids = []
    @global_search_current_idx      = 0
    @global_search_origin_focus     = nil

    # Forceer de interactieve vlaggen ook direct naar de ruststand
    @interactively_replacing        = false
    @replace_action_performed       = false

    # 4. Synchroniseer beide componenten direct om de UI terug te brengen naar monochrome rust
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    # 🎯 Extra statusbalk-update trigger mocht je framework daar specifiek naar luisteren
    update_statusbar_matches_count if respond_to?(:update_statusbar_matches_count, true)
  end

  def trigger_search_replace_popups(key, has_ctrl, has_alt, has_shift)
    trigger = search_replace_trigger(key, has_ctrl, has_alt, has_shift)
    return false unless trigger # Toets hoort niet bij search/replace, direct afbreken

    return false unless search_replace_popup_allowed?

    origin_focus = @active_focus

    # Bereid de popup-registers voor en open het venster vloeibaar
    prepare_search_replace_popup(origin_focus) if respond_to?(:prepare_search_replace_popup, true)
    show_search_replace_popup(trigger, origin_focus)

    true
  end

  def search_replace_popup_allowed?
    has_table_search = @search_matches && @search_matches.any?
    has_tree_search  = defined?(@tree_search_matches) && @tree_search_matches && @tree_search_matches.any?
    is_in_replace    = (@active_focus == :replace_mode) ||
                       (defined?(@interactively_replacing) && @interactively_replacing == true)

    return false if has_table_search || has_tree_search || is_in_replace

    %i[table tree].include?(@active_focus)
  end

  def search_replace_trigger(key, has_ctrl, has_alt, has_shift)
    key_str = key.to_s.strip
    is_pure_f = key_str == 'f' && !has_ctrl && !has_alt && !has_shift
    is_pure_F = key_str == 'F' && !has_ctrl && !has_alt

    is_search = (key == '/' && !has_alt && !has_shift) ||
                (has_ctrl && key_str.downcase == 'f') || is_pure_f
    is_replace = (key == '\\' && !has_alt && !has_shift) ||
                 (has_ctrl && key_str.downcase == 'h') || is_pure_F

    return nil unless is_search || is_replace

    { search: is_search, replace: is_replace }
  end

  def prepare_search_replace_popup(origin_focus)
    @selected_tree_paths = []
    @selected_table_rows = [] if defined?(@selected_table_rows)

    # Als we al in de command_mode-keten zitten, overschrijf @last_focus dan NIET!
    # This tells the popup to return focus to the status bar.
    @last_focus = if defined?(@focus_before_help) && @focus_before_help == :command_mode
                    :command_mode
                  else
                    origin_focus
                  end
  end

  def show_search_replace_popup(trigger, origin_focus)
    is_replace_trigger = trigger[:replace]
    remembered_tree_path = @tree.respond_to?(:selected_path) ? @tree.selected_path : nil

    # Retrieve the language-independent field matrix, which contains :context_title_key.
    popup_fields = build_search_replace_popup_fields(is_replace_trigger)

    # 🎯 SCHOON EN ENERGIERIEK:
    # Pass an empty title because PopupView.draw_form_popup always replaces it
    # with the correctly translated language string.
    @popup.show(type: :form, title: '', fields: popup_fields) do |data|
      success = process_search_replace_popup_submission(data, is_replace_trigger, origin_focus, remembered_tree_path)
      next false unless success

      true
    end

    mark_popup_for_input_indicators
    @active_focus = :popup

    true
  end

  def build_search_replace_popup_fields(is_replace_trigger)
    settings = AppConfig.settings

    fields = {
      query: RatinField.new(placeholder: settings.language_string(:search_placeholder))
    }
    if is_replace_trigger
      fields[:replace] =
        RatinField.new(placeholder: settings.language_string(:replace_placeholder))
    end

    fields[:case_sensitive] = RatinCheckbox.new(
      label: settings.language_string(:search_case_sensitive), checked: false
    )
    fields[:regex] = RatinCheckbox.new(
      label: settings.language_string(:search_regex), checked: false
    )

    # Add the 'All' checkbox only when the table has focus.
    if @active_focus == :table || @active_focus == :replace_mode && @last_focus == :table
      fields[:global] = RatinCheckbox.new(
        label: ' All decks', checked: false
      )
    end

    fields # ➔ Bevat nu 100% pure widgets!
  end

  def process_search_replace_popup_submission(data, is_replace_trigger, origin_focus, remembered_tree_path)
    settings = AppConfig.settings
    query_text = popup_field_text(data[:query])
    replace_text = is_replace_trigger ? popup_field_text(data[:replace]) : nil

    # 🎯 FIX SEARCH/REPLACE POPUP: If the search field is empty, show a warning
    # and pass 'next false' so the popup remains open.
    if query_text.empty?
      warn_for_empty_search_query(query_text)

      @active_focus = :popup
      @tree.selected_path = remembered_tree_path if origin_focus == :tree && remembered_tree_path

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      return false # 🔒 Vertelt het codeblok om open te blijven via next false
    end

    is_case_checked = popup_case_sensitive_value(data[:case_sensitive])
    is_regex_checked = popup_case_sensitive_value(data[:regex])
    is_global_checked = popup_case_sensitive_value(data[:global])

    @tree_regex_mode = is_regex_checked if origin_focus == :tree
    @table_regex_mode = is_regex_checked if origin_focus != :tree

    begin
      if origin_focus == :tree
        process_tree_search_replace_submission(
          query_text, replace_text, is_replace_trigger, is_case_checked,
          origin_focus, remembered_tree_path
        )
      else
        process_table_search_replace_submission(
          query_text, replace_text, is_replace_trigger, is_case_checked,
          is_global_checked
        )
      end

      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    rescue RegexpError => e
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_invalid_regex)}: #{e.message}",
        type: :warning
      )

      @active_focus = :popup
      @tree.selected_path = remembered_tree_path if origin_focus == :tree && remembered_tree_path
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      false
    end
  end

  def popup_field_text(field)
    field.respond_to?(:text) ? field.text : field.to_s
  end

  def warn_for_empty_search_query(query_text)
    return unless query_text.empty?

    trigger_statusbar_message(
      "#{AppConfig.settings.language_string(:statusbar_form_error)}: #{AppConfig.settings.language_string(:statusbar_no_query_specified)}!",
      type: :warning
    )
  end

  def popup_case_sensitive_value(raw_case)
    if raw_case.respond_to?(:checked?)
      raw_case.checked?
    elsif raw_case.respond_to?(:active?)
      raw_case.active?
    elsif raw_case.respond_to?(:value)
      [true, :checked].include?(raw_case.value)
    else
      [true, :checked].include?(raw_case) || raw_case.to_s.strip.downcase == 'true'
    end
  end

  def clear_empty_search_replace_state(origin_focus)
    @search_matches = nil
    @search_current_match_idx = nil
    @last_search_query = nil
    @last_replace_text = nil

    @tree_search_matches = nil
    @tree_search_current_idx = nil
    @last_tree_search_query = nil
    @active_focus = origin_focus
    @last_focus = origin_focus
    @interactively_replacing = false
  end

  def process_tree_search_replace_submission(query_text, replace_text, is_replace_trigger, is_case_checked,
                                             origin_focus, remembered_tree_path)
    @last_tree_search_query = query_text
    @last_replace_text = replace_text if is_replace_trigger
    @tree_case_sensitive = is_case_checked
    @tree_search_matches = []
    @tree_search_current_idx = 0

    build_tree_search_matches(query_text, is_case_checked)

    if @tree_search_matches.any?
      activate_tree_search_replace(is_replace_trigger)
    else
      handle_tree_search_no_result(is_replace_trigger, origin_focus, remembered_tree_path)
    end
  end

  def build_tree_search_matches(query_text, is_case_checked)
    regex_mode = !!@tree_regex_mode

    search_regex = if regex_mode
                     flags = is_case_checked ? 0 : Regexp::IGNORECASE
                     Regexp.new(query_text.to_s, flags)
                   else
                     search_str = normalize_target_scripts(query_text, is_case_checked)
                     search_str = search_str.downcase unless is_case_checked
                     nil
                   end

    match_proc = lambda do |name_field|
      norm_field = normalize_target_scripts(name_field, is_case_checked)

      if regex_mode
        regex_text = norm_field.unicode_normalize(:nfd)
        regex_text.match?(search_regex)
      else
        norm_field = norm_field.downcase unless is_case_checked
        norm_field.include?(search_str)
      end
    end

    @library.subjects.each do |sub|
      sub_path = [sub.id.to_s]
      @tree_search_matches << sub_path if match_proc.call(sub.name)

      sub.sources.each do |src|
        src_path = sub_path + [src.id.to_s]
        @tree_search_matches << src_path if match_proc.call(src.name)

        src.decks.each do |deck|
          deck_path = src_path + [deck.id.to_s]
          @tree_search_matches << deck_path if match_proc.call(deck.name)
        end
      end
    end
  end

  def activate_tree_search_replace(is_replace_trigger)
    @active_focus = is_replace_trigger ? :replace_mode : :tree
    @last_focus = :tree
    @interactively_replacing = is_replace_trigger
    @replace_action_performed = false if is_replace_trigger

    target_path = @tree_search_matches[@tree_search_current_idx]
    @tree.selected_path = target_path
    expand_tree_search_target(target_path)
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    if respond_to?(:jump_to_absolute_tree_search_index, true)
      jump_to_absolute_tree_search_index(target_path)
    elsif @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && defined?(@tree_state) && @tree_state
      matched_idx = @tree.visible_nodes.index { |node| node[:path] == target_path }
      @tree_state.select(matched_idx || 0)
    end
  end

  def expand_tree_search_target(target_path)
    return unless @tree.respond_to?(:expanded_paths)

    @tree.expanded_paths ||= []
    (1...target_path.length).each do |i|
      parent_path = target_path[0...i]
      @tree.expanded_paths << parent_path unless @tree.expanded_paths.include?(parent_path)
    end
  end

  def handle_tree_search_no_result(is_replace_trigger, origin_focus, remembered_tree_path)
    notify_search_replace_no_result
    @tree_search_matches = nil
    @tree_search_current_idx = nil
    @last_tree_search_query = nil
    @last_replace_text = nil if is_replace_trigger
    @active_focus = :tree
    @last_focus = :tree
    @tree.selected_path = remembered_tree_path
    @interactively_replacing = false
  end

  def process_table_search_replace_submission(query_text, replace_text, is_replace_trigger, is_case_checked,
                                              is_global_checked = false)
    @last_search_query = query_text
    @last_replace_text = replace_text if is_replace_trigger
    @table_case_sensitive = is_case_checked
    @search_matches = []
    @search_current_match_idx = 0

    if is_global_checked && is_replace_trigger
      @global_search_case_sensitive = is_case_checked
      @global_search_regex_mode = !!@table_regex_mode

      perform_global_search(
        query_text,
        case_sensitive: is_case_checked,
        regex_mode: !!@table_regex_mode
      )

      if @global_search_matches.any?
        @active_focus = :replace_mode
        @last_focus = :table
        @interactively_replacing = true
        return
      end

      handle_table_search_no_result(true)
      return
    end

    cards_to_search = active_cards_for_search
    build_table_search_matches(cards_to_search, query_text, is_case_checked)

    if @search_matches.any?
      activate_table_search_replace(is_replace_trigger)
    else
      handle_table_search_no_result(is_replace_trigger)
    end
  end

  def active_cards_for_search
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0

    begin
      @library.subjects[s_idx].sources[src_idx].decks[d_idx].cards
    rescue StandardError
      @active_cards || []
    end
  end

  def build_table_search_matches(cards_to_search, query_text, is_case_checked)
    regex_mode = !!@table_regex_mode

    search_regex = if regex_mode
                     flags = is_case_checked ? 0 : Regexp::IGNORECASE
                     Regexp.new(query_text.to_s, flags)
                   else
                     build_script_insensitive_regex(query_text, is_case_checked)
                   end

    cards_to_search.each_with_index do |card, idx|
      nfd_term = card.term.to_s.unicode_normalize(:nfd)
      nfd_context = card.context.to_s.unicode_normalize(:nfd)
      nfd_meaning = card.meaning.to_s.unicode_normalize(:nfd)

      match_found = nfd_term.match?(search_regex) ||
                    nfd_context.match?(search_regex) ||
                    nfd_meaning.match?(search_regex)

      @search_matches << idx if match_found
    end
  end

  def activate_table_search_replace(is_replace_trigger)
    @active_focus = is_replace_trigger ? :replace_mode : :table
    @last_focus = :table
    @interactively_replacing = is_replace_trigger
    @table_state.select(@search_matches[@search_current_match_idx]) if defined?(@table_state) && @table_state
  end

  def handle_table_search_no_result(is_replace_trigger)
    notify_search_replace_no_result
    @search_matches = nil
    @search_current_match_idx = nil
    @last_search_query = nil
    @last_replace_text = nil if is_replace_trigger
    @active_focus = :table
    @last_focus = :table
    @interactively_replacing = false
    @replace_action_performed = false
  end

  private

  def handle_popup_input(key, modifiers = [])
    return false unless @popup&.active_popup

    raw_key_str = key.to_s
    is_space_key = raw_key_str == ' ' || raw_key_str.downcase == 'space' || key == :space
    key_str = is_space_key ? 'space' : raw_key_str.strip.downcase
    is_escape = %w[esc escape \e].include?(key_str) || key == :escape
    is_enter  = %w[enter \r \n].include?(key_str) || key == :enter

    popup_type = begin
      @popup.active_popup[:type]
    rescue StandardError
      nil
    end

    is_menu_popup = %i[help info].include?(popup_type)

    # =========================================================================
    # FIX 1: CONTEXT-AWARE ESCAPE & ANNULEER BRANDMUUR (HERSTELT FOCUS LOEPZUIVER)
    # =========================================================================
    if is_escape
      @popup.close if @popup.respond_to?(:close)
      @show_help = false if defined?(@show_help)

      if (defined?(@last_focus) && @last_focus == :command_mode) ||
         (defined?(@focus_before_help) && @focus_before_help == :command_mode)

        @active_focus = :command_mode
        @last_focus = :command_mode
        @command_mode_visible = true

        @statusbar_field.is_focused = true if defined?(@statusbar_field) && @statusbar_field

        @focus_before_help = nil if defined?(@focus_before_help)

      elsif is_menu_popup # 🟢 BIJ ESCAPE: De popup sluit, maar de focus blijft rotsvast op :menu
        @active_focus = :menu
        @last_focus = :menu
        @menu_dropdown_open = true if defined?(@menu_dropdown_open)
      else
        # Reguliere formulieren vallen terug op hun historische focus
        @active_focus = defined?(@last_focus) && @last_focus != :popup ? @last_focus : :tree
      end

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      return true
    end

    if is_enter && is_menu_popup
      @popup.close
      @show_help = false if defined?(@show_help)

      # 🟢 Bepaal het absolute startpaneel van vóór het menu-bezoek
      start_target = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : nil
      start_target ||= defined?(@menu_origin_focus) && @menu_origin_focus && @menu_origin_focus != :menu ? @menu_origin_focus : :tree
      start_target = :tree if %i[menu popup command_mode].include?(start_target)

      # 🟢 HARD-OVERRIDE BRANDMUUR: We zetten de dropdown DIRECT uit en
      # overschrijven alle menu-registers met de startpositie.
      # Dit blokkeert elke poging van handle_menu_input om de focus te kapen!
      @menu_dropdown_open = false if defined?(@menu_dropdown_open)
      @active_submenu_idx = 0 if defined?(@active_submenu_idx)
      @menu_origin_focus  = start_target if defined?(@menu_origin_focus)
      @cockpit_panel_anchor = start_target if defined?(@cockpit_panel_anchor)
      @focus_before_help = start_target if defined?(@focus_before_help)

      @active_focus = start_target
      @last_focus   = start_target

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # We retourneren true en sluiten de keten onmiddellijk af voor dit frame!
      return true
    end

    # =========================================================================
    # DETAILED ROUTING: Geef overige toetsen (zoals typen) door aan sub-handlers
    # =========================================================================
    return true if process_help_keys(key, modifiers) || process_form_keys(key, modifiers)

    # =========================================================================
    # ALGEMENE FALLBACK ACTIES (Voor simpele Info of Confirm popups zonder invoervelden)
    # =========================================================================
    case key_str

    when 'enter', "\r", "\n"
      # Algemene fallback voor Enter op Info/Confirm popupss
      @active_focus = @last_focus
      @popup.submit if @popup.respond_to?(:submit)
      return true
    end

    false # Toets niet herkend door de popup-omgeving, laat het systeem het weten
  end

  def process_help_keys(key, modifiers = [])
    popup = @popup&.active_popup
    return false unless popup && popup[:type] == :help

    mods = normalize_popup_modifiers(modifiers)
    raw_string = key.to_s
    is_space = raw_string == ' ' || raw_string.downcase == 'space' || key == :space
    key_raw = is_space ? 'space' : raw_string.strip.sub(/\A:/, '')
    key_down = key_raw.downcase

    return true if switch_help_tab(popup, key_down)

    scroll_state = help_scroll_state(popup)
    handle_help_scroll_key(popup, key_raw, key_down, mods, scroll_state)
  end

  def normalize_popup_modifiers(modifiers)
    mods = Array(modifiers).map { |m| m.to_s.downcase }
    {
      ctrl: mods.include?('ctrl') || mods.include?('control') || mods.include?('control'),
      shift: mods.include?('shift'),
      alt: mods.include?('alt') || mods.include?('option') || mods.include?('meta')
    }
  end

  def switch_help_tab(popup, key_down)
    settings = AppConfig.settings

    tabs = {
      '1' => :help_main,
      '2' => :help_startup_screen,
      '3' => :help_main_screen,
      '4' => :help_commands,
      '5' => :help_library,
      '6' => :help_deck,
      '7' => :help_study,
      '8' => :help_input_fields
    }
    message_key = tabs[key_down]
    return false unless message_key

    title_key = {
      help_main: :help_main_title,
      help_startup_screen: :help_startup_screen_title,
      help_main_screen: :help_main_screen_title,
      help_commands: :help_commands_title,
      help_library: :help_library_title,
      help_deck: :help_deck_title,
      help_study: :help_study_title,
      help_input_fields: :help_input_fields_title
    }[message_key]
    popup[:title] = " #{settings.language_string(title_key)} "
    popup[:message] = settings.language_string(message_key)
    popup[:scroll_y] = 0

    # Forcefully clear stale multi-page tracking memory indicators
    @popup_current_page = 1 if instance_variable_defined?(:@popup_current_page)
    @popup_total_pages  = 1 if instance_variable_defined?(:@popup_total_pages)

    if defined?(App) && App
      App.instance_variable_set(:@popup_current_page, 1)
      App.instance_variable_set(:@popup_total_pages, 1)
    end
    # =========================================================================

    true
  end

  def help_scroll_state(popup)
    terminal_size = RatatuiRuby.terminal_size
    terminal_width = terminal_size&.width || 80
    terminal_height = terminal_size&.height || 24

    footer_key =
      popup[:footer_key] ||
      (popup[:type] == :confirm ? :alert_cancel_ok : :alert_ok)

    footer = AppConfig.settings.language_string(footer_key)

    # Gebruik exact dezelfde splitsing als draw_text_popup.
    # Do not use rstrip: trailing blank lines count too.
    message_rows = popup[:message].to_s.split("\n")
    message_rows = [''] if message_rows.empty?
    footer_rows = [footer]

    area = RatatuiRuby::Layout::Rect.new(
      0,
      0,
      terminal_width,
      terminal_height
    )

    frame = Struct.new(:area).new(area)

    layout = PopupView.calculate_help_scroll_layout(
      frame,
      popup,
      message_rows,
      footer_rows
    )

    scrollable_height = [
      layout[:scrollable_height].to_i,
      1
    ].max

    max_scroll = [
      layout[:max_scroll].to_i,
      0
    ].max

    current_scroll = [
      [popup[:scroll_y].to_i, 0].max,
      max_scroll
    ].min

    {
      half_page_step: [scrollable_height / 2, 1].max,
      max_scroll: max_scroll,
      current_scroll: current_scroll
    }
  end

  def help_popup_height(popup, needed_box_height, max_terminal_box_height)
    if popup[:type] == :help
      calculated = needed_box_height <= max_terminal_box_height ? needed_box_height : max_terminal_box_height
      [calculated, 7].max
    else
      [needed_box_height, 5].max
    end
  end

  def handle_help_scroll_key(popup, key_raw, key_down, mods, state)
    if help_page_up_key?(key_raw, key_down, mods)
      popup[:scroll_y] = [state[:current_scroll] - state[:half_page_step], 0].max
    elsif help_page_down_key?(key_raw, key_down, mods)
      popup[:scroll_y] = [state[:current_scroll] + state[:half_page_step], state[:max_scroll]].min
    elsif key_down == 'home' || (key_raw == 'g' && !mods[:shift])
      popup[:scroll_y] = 0
    elsif key_down == 'end' || key_raw == 'G' || (key_raw == 'g' && mods[:shift])
      popup[:scroll_y] = state[:max_scroll]
    elsif help_line_up_key?(key_down, mods)
      popup[:scroll_y] = [state[:current_scroll] - 1, 0].max
    elsif help_line_down_key?(key_down, mods)
      popup[:scroll_y] = [state[:current_scroll] + 1, state[:max_scroll]].min
    else
      return false
    end

    true
  end

  def help_page_up_key?(key_raw, key_down, mods)
    (key_down == 'u' && mods[:ctrl]) ||
      %w[page_up pageup].include?(key_down) ||
      key_raw == "\x15"
  end

  def help_page_down_key?(key_raw, key_down, mods)
    (key_down == 'd' && mods[:ctrl]) ||
      %w[page_down pagedown].include?(key_down) ||
      %w[space].include?(key_down) || # 🎯 Spatiebalk-string herkenning
      key_raw == ' ' || key_raw == :space || # 🎯 Rauwe spatie-karakters en symbolen
      key_raw == "\x04"
  end

  def help_line_up_key?(key_down, mods)
    (key_down == 'p' && mods[:ctrl]) || (%w[up k].include?(key_down) && !mods[:shift] && !mods[:ctrl])
  end

  def help_line_down_key?(key_down, mods)
    (key_down == 'n' && mods[:ctrl]) || (%w[down j].include?(key_down) && !mods[:shift] && !mods[:ctrl])
  end

  def process_form_keys(key, modifiers)
    return false unless active_form_popup?

    popup = @popup.active_popup
    fields = popup[:fields] || {}
    field_keys = fields.keys
    popup[:form_focus] ||= field_keys.first
    current_key = popup[:form_focus]
    current_field = fields[current_key]

    focus_form_fields(fields, current_key)
    mods = normalize_form_modifiers(modifiers)
    key_str = key.to_s.strip.sub(/\A:/, '')
    key_down = key_str.downcase

    return true if alt_enter_key?(key_down, mods)

    result = handle_form_primary_key(key, key_down, mods, popup, fields, field_keys, current_key)
    return result unless result == :continue

    # 🎯 FIX PART 1: Als het een pure letter/karakter is (lengte 1, zoals J of K),
    # is het GEEN systeem- of navigatietoets, maar pure tekst.
    # We onderscheppen hem hier direct om Emacs-gijzeling te voorkomen.
    if key_str.length == 1 && !mods[:ctrl] && !mods[:alt] && current_field
      # Vertaal de toets naar het exacte karakter (Shift zorgt al voor de hoofdletter J/K in key_str)
      # We poetsen 'shift' uit de modifiers zodat de interne engine niet denkt dat het een macro is!
      clean_mods = Array(modifiers).map { |m| m.to_s.downcase }
      clean_mods.delete('shift')

      # Probeer de toets eerst op de gestandaardiseerde TUI-manier aan tebieden
      if current_field.respond_to?(:handle_key)
        # Sommige RatinFields willen net als de statusbalk het 'Char(...)' formaat:
        current_field.handle_key("Char('#{key_str}')", clean_mods)
        return true
      end
    end

    if form_system_or_navigation_key?(key_down)
      return handle_form_system_key(key, modifiers, key_down, popup, fields, field_keys, current_key,
                                    current_field)
    end

    inject_form_text(current_field, key, modifiers)
  end

  def active_form_popup?
    @popup&.active_popup && @popup.active_popup[:type] == :form
  end

  def focus_form_fields(fields, current_key)
    fields.each { |k, field| field.is_focused = (k == current_key) }
  end

  def normalize_form_modifiers(modifiers)
    mods = Array(modifiers).map { |m| m.to_s.downcase }
    {
      alt: mods.include?('alt') || mods.include?('meta') || mods.include?('option'),
      ctrl: mods.include?('ctrl') || mods.include?('control')
    }
  end

  def alt_enter_key?(key_down, mods)
    mods[:alt] && %w[enter \r \n].include?(key_down)
  end

  def handle_form_primary_key(key, key_down, mods, popup, fields, field_keys, current_key)
    ctrl_n = (key_down == 'n' && mods[:ctrl]) || key_down.match?(/\A(?:ctrl|control)[+_ -]?n\z/)
    ctrl_p = (key_down == 'p' && mods[:ctrl]) || key_down.match?(/\A(?:ctrl|control)[+_ -]?p\z/)

    case key_down
    when 'tab'
      return :continue if @active_focus == :tree

      cycle_form_field(popup, fields, field_keys, current_key, 1)
      true
    when 'n', 'ctrl+n', 'control+n', 'ctrl_n', 'control_n'
      return :continue unless ctrl_n
      return if @active_focus == :tree

      direction = fields[current_key]&.direction == :rtl ? -1 : 1
      cycle_form_field(popup, fields, field_keys, current_key, direction)
      true
    when 'back_tab', 'backtab', "\e[z"
      return :continue if @active_focus == :tree

      cycle_form_field(popup, fields, field_keys, current_key, -1)
      true
    when 'p', 'ctrl+p', 'control+p', 'ctrl_p', 'control_p'
      return :continue unless ctrl_p
      return if @active_focus == :tree

      direction = fields[current_key]&.direction == :rtl ? 1 : -1
      cycle_form_field(popup, fields, field_keys, current_key, direction)
      true
    when 'enter', "\r", "\n"
      @popup.submit(fields.transform_values(&:get_text)) if @popup.respond_to?(:submit)
      true
    when 'esc', "\e", 'escape'
      :continue
    else
      :continue
    end
  end

  def cycle_form_field(popup, fields, field_keys, current_key, direction)
    return true unless field_keys.any?

    current_index = field_keys.index(current_key) || 0
    new_index = (current_index + direction) % field_keys.length
    popup[:form_focus] = field_keys[new_index]
    new_field = fields[popup[:form_focus]]
    new_field.cursor_index = new_field.text.length if new_field
    true
  end

  def form_system_or_navigation_key?(key_down)
    %w[up down page_up page_down left right home end backspace delete].include?(key_down) ||
      key_down.start_with?('alt_', 'ctrl_', 'super_', 'meta_')
  end

  def handle_form_system_key(key, modifiers, key_down, popup, fields, field_keys, current_key, current_field)
    return true unless current_field

    result = current_field.handle_key(key, modifiers)
    if result == :next_field && field_keys.any?
      return if @active_focus == :tree

      cycle_form_field(popup, fields, field_keys, current_key, 1)
    elsif result == :prev_field && field_keys.any?
      return if @active_focus == :tree

      cycle_form_field(popup, fields, field_keys, current_key, -1)
    end
    true
  end

  def inject_form_text(current_field, key, modifiers)
    return false unless current_field

    current_field.handle_key(key, modifiers)
    true
  end

  def close_help_popup
    # Gebruik hier jouw bestaande sluitlogica indien die anders heet.
    @popup.close if defined?(@popup) && @popup && @popup.respond_to?(:close)

    previous_focus = @focus_before_help || :tree

    @active_focus = previous_focus

    if (@active_focus == :command_mode) && defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.is_focused = true
    end

    @last_focus = @active_focus
  end

  def restore_focus_after_help
    # Capture the historical path origins securely
    menu_origin = defined?(@menu_origin_focus) ? @menu_origin_focus : nil
    base_before = @focus_before_help || :tree

    @active_focus = if base_before == :menu || @active_focus == :menu
                      # 🟢 MENU ROUTE DETECTIE: Grijp de diepere herkomst van het actieve paneel
                      menu_origin || (defined?(@last_focus) && @last_focus != :popup ? @last_focus : :tree)
                    else
                      # 💤 Standaard route fallback
                      base_before
                    end

    # Clean up fantoom references to keep memory states uncorrupted
    @menu_origin_focus = nil if defined?(@menu_origin_focus)
    @focus_before_help = nil if defined?(@focus_before_help)

    if (@active_focus == :command_mode) && defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.is_focused = true
    end

    @last_focus = @active_focus
  end
end
