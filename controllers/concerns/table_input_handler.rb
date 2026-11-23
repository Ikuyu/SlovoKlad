require_relative '../../lib/ratin_checkbox'
require_relative '../../audio/sound_manager'

module TableInputHandler
  private

  def execute_search(query_text)
    return if query_text.to_s.strip.empty?

    @search_matches = []
    @search_current_match_idx = 0
    @last_search_query = query_text.to_s

    is_strict = (@table_case_sensitive == true)
    search_str = query_text.to_s
    search_cmp = is_strict ? search_str : search_str.downcase

    cards_to_search = respond_to?(:active_cards) ? active_cards : (@active_cards || [])

    cards_to_search.each_with_index do |card, idx|
      term = card.term.to_s
      context = card.context.to_s
      meaning = card.meaning.to_s
      match_found = if is_strict
                      term.include?(search_cmp) || context.include?(search_cmp) || meaning.include?(search_cmp)
                    else
                      term.downcase.include?(search_cmp) ||
                        context.downcase.include?(search_cmp) ||
                        meaning.downcase.include?(search_cmp)
                    end

      @search_matches << idx if match_found
    end

    if @search_matches.any?
      @table_state.select(@search_matches[@search_current_match_idx]) if @table_state
    else
      @search_matches = nil
    end
  end

  def normalize_search_data(search_data)
    if search_data.is_a?(Hash)
      {
        query: (search_data[:query] || search_data[:search] || search_data.values.first).to_s.strip,
        case_sensitive: search_data[:case_sensitive].to_s == 'true' || search_data[:case_sensitive] == true,
        regex: search_data[:regex].to_s == 'true' || search_data[:regex] == true
      }
    else
      {
        query: search_data.to_s.strip,
        case_sensitive: defined?(@last_case_sensitive) ? @last_case_sensitive : false,
        regex: defined?(@last_regex) ? @last_regex : false
      }
    end
  end

  def perform_card_scan(query, cards)
    matches = []
    search_query = query.to_s
    case_sensitive = (@last_case_sensitive == true)

    matcher = if @last_regex
                begin
                  flags = case_sensitive ? 0 : Regexp::IGNORECASE
                  Regexp.new(@last_search_query.to_s, flags)
                rescue RegexpError
                  nil
                end
              end
    comparison = case_sensitive ? search_query : search_query.downcase

    cards.each_with_index do |card, index|
      matched = if matcher
                  matcher.match?(card.term.to_s) ||
                    matcher.match?(card.context.to_s) ||
                    matcher.match?(card.meaning.to_s)
                elsif case_sensitive
                  card.term.to_s.include?(comparison) ||
                    card.context.to_s.include?(comparison) ||
                    card.meaning.to_s.include?(comparison)
                else
                  card.term.to_s.downcase.include?(comparison) ||
                    card.context.to_s.downcase.include?(comparison) ||
                    card.meaning.to_s.downcase.include?(comparison)
                end

      matches << index if matched
    end

    matches
  end

  def execute_replace(query_text, replace_text, replace_all = false)
    return if query_text.to_s.strip.empty?

    is_strict = (@table_case_sensitive == true)
    regex_opts = is_strict ? 0 : Regexp::IGNORECASE
    search_regex = Regexp.new(Regexp.escape(query_text.to_s), regex_opts)

    cards_to_search = respond_to?(:active_cards) ? active_cards : (@active_cards || [])

    # Hulpmethode om een kaart veilig inline te modificeren
    modify_card = lambda do |card|
      card.term    = card.term.gsub(search_regex, replace_text)    if card.term =~ search_regex
      card.context = card.context.gsub(search_regex, replace_text) if card.context =~ search_regex
      card.meaning = card.meaning.gsub(search_regex, replace_text) if card.meaning =~ search_regex
    end

    if replace_all
      # 1. Lokale bulk-wijziging: we muteren alleen het actieve deck!
      # 👉 We gebruiken hier dus je standaard snapshot-pipeline voor data parity!
      snapshot_saved = false
      changes_made = false

      cards_to_search.each do |card|
        %i[term context meaning].each do |field|
          original = card.public_send(field)
          next unless original =~ search_regex

          replacement = original.gsub(search_regex, replace_text)
          next if replacement == original

          unless snapshot_saved
            allow_snapshot! if respond_to?(:allow_snapshot!)
            save_history_snapshot if respond_to?(:save_history_snapshot)
            snapshot_saved = true
          end

          card.public_send("#{field}=", replacement)
          changes_made = true
        end
      end

      @library_dirty = true if changes_made
      # 2. ⚡ DE EXIT GRENDEL: Sluit alle vlaggen direct en onherroepelijk af!
      @interactively_replacing = false
      @replace_action_performed = false
      @active_focus = :table
      @last_focus   = :table

      wipe_all_search_artifacts if respond_to?(:wipe_all_search_artifacts)

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # 🔥 DE ABSOLUTE REDDING: Vroege return!
      # Dit voorkomt dat de execute_search hieronder de zojuist gewiste registers overschrijft!
      true
    else
      # =========================================================================
      # SINGLE MATCH REPLACEMENT (Volgt de reguliere stappen-as)
      # =========================================================================
      return unless @search_matches && @search_matches[@search_current_match_idx]

      current_card_idx = @search_matches[@search_current_match_idx]
      target_card = cards_to_search[current_card_idx]

      if target_card
        changes = %i[term context meaning].filter_map do |field|
          original = target_card.public_send(field)
          next unless original =~ search_regex

          replacement = original.gsub(search_regex, replace_text)
          [field, replacement] if replacement != original
        end

        unless changes.empty?
          allow_snapshot! if respond_to?(:allow_snapshot!)
          save_history_snapshot if respond_to?(:save_history_snapshot)

          changes.each do |field, replacement|
            target_card.public_send("#{field}=", replacement)
          end

          @library_dirty = true
        end
      end

      # Run a fresh search to keep the remaining highlights up to date.
      execute_search(query_text)
    end
  end

  def enforce_replace_state
    if @search_matches && @search_matches.any?
      # Gevonden! Activeer geforceerd de replace-mode en selecteer de eerste regel
      @active_focus = :replace_mode
      @search_current_match_idx = 0
      target_row = @search_matches[@search_current_match_idx]

      @table_state.select(target_row) if @table_state
    else
      # Als er ECHT 0 matches zijn, herstellen we direct de normale tabelomgeving
      @active_focus      = :table
      @search_matches    = nil
      @last_replace_text = nil
    end
  end

  def handle_table_input(key, focus_on_enter, modifiers = [])
    mods = Array(modifiers).map { |m| m.to_s.downcase }
    key_raw = key.to_s

    key = case key
          when :backspace, :back_space
            'backspace'
          else
            case key_raw
            when "\b", "\x7f", "\u007f", '127', 'Backspace', 'back_space'
              'backspace'
            else
              key
            end
          end

    is_normal_space = (key == :space || key_raw == ' ' || key_raw == 'space') &&
                      !mods.include?('shift') && !mods.include?('alt') &&
                      !mods.include?('option') && !mods.include?('ctrl') && !mods.include?('control')

    if is_normal_space
      # Verrijk de context direct handmatig voor de bulk-wijziging
      s_idx = @current_subject_idx || 0
      src_idx = @current_source_idx || 0
      d_idx = @current_deck_idx || 0
      active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
      cards_list = active_deck ? (active_deck.cards || []) : []

      # 🎯 GEFIXEERD: Alle zwevende breuken en komma's zijn hier viltstrak opgeruimd!
      simulated_context = {
        key_str: ' ',
        has_alt: false,
        has_ctrl: false,
        has_shift: false,
        cards_list: cards_list,
        current_idx: defined?(@table_state) && @table_state ? @table_state.selected : nil,
        has_active_search: @search_matches && @search_matches.any?,
        is_replace_mode: (@active_focus == :replace_mode)
      }

      return handle_table_space_input(key, simulated_context)
    end

    context = prepare_table_input_context(key, modifiers)

    return true if context[:pure_alt_space_handled]
    return false if context[:invalid_ctrl]

    key = context[:key]

    # Shift+Enter: ga vanuit de table terug naar de tree.
    is_enter_key = key.to_s.strip.downcase.sub(/\A:/, '') == 'enter' ||
                   key.to_s == "\r" || key.to_s == "\n" || key == :enter

    if @active_focus == :table && context[:has_shift] && is_enter_key
      wipe_all_search_artifacts
      @last_focus = :tree
      @active_focus = :tree

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      return true
    end

    process_table_input_page_navigation(context, key)
    return true if context[:page_navigation_consumed]

    return true if (@active_focus == :replace_mode) && handle_interactive_replace_mode(key, context[:has_shift])

    trigger_search_replace_popups(key, context[:has_ctrl], context[:has_alt], context[:has_shift]) ||
      handle_undo_redo_shortcuts(key, context[:has_ctrl], context[:has_shift]) ||
      false

    return false unless %i[table replace_mode].include?(@active_focus) && key
    return false unless table_input_active_deck?(context)

    context = enrich_table_input_context(context)
    if table_input_navigation_key?(key, context)
      consumed = handle_table_input_navigation(context, key, focus_on_enter)
      return true if consumed
    end

    dispatch_table_input_key(key, focus_on_enter, context)
  end

  def prepare_table_input_context(key, modifiers)
    mods = Array(modifiers).map { |m| m.to_s.downcase }
    has_alt = mods.include?('alt') || mods.include?('option')
    has_shift = mods.include?('shift')
    has_ctrl = mods.include?('ctrl') || mods.include?('control')
    key_raw_str = key.to_s
    is_pure_alt_space = (key_raw_str == ' ' && has_alt) || (key_raw_str.bytes == [32] && has_alt) ||
                        key_raw_str == "\u00A0" || key_raw_str == "\xC2\xA0" || key_raw_str.bytes == [194, 160]

    if is_pure_alt_space
      has_active_search = @search_matches && @search_matches.any?
      is_replace_mode = (@active_focus == :replace_mode)
      unless has_active_search || is_replace_mode
        current_idx = @table_state.selected if defined?(@table_state) && @table_state
        if current_idx
          toggle_mark(current_idx)
          return { pure_alt_space_handled: true }
        end
      end
      return { pure_alt_space_handled: true }
    end

    check_key = key.to_s.strip.sub(/\A:/, '').downcase
    if has_ctrl && %w[n p].include?(check_key)
      key = check_key == 'n' ? :down : :up
      has_ctrl = false
    end

    key_str = key.to_s.strip.sub(/\A:/, '')
    if has_ctrl
      allowed_tree_ctrl_keys = %w[u d f h z y n p a]
      ctrl_key = key_str.tr('-', '_').downcase

      unless allowed_tree_ctrl_keys.include?(ctrl_key)
        return {
          pure_alt_space_handled: true,
          invalid_ctrl: true
        }
      end

      if ctrl_key == 'a'
        # Alleen Ctrl+Shift+A mag door naar de selectieactie.
        unless has_shift
          return {
            pure_alt_space_handled: true,
            invalid_ctrl: true
          }
        end

        key = 'A'
        key_str = 'A'
      end
    end

    search_page_key = key.to_s.strip.sub(/\A:/, '').tr('-', '_').downcase
    is_search_page_up = %w[page_up pageup ctrl_u].include?(search_page_key) ||
                        (has_ctrl && search_page_key == 'u') || key == "\x15"
    is_search_page_down = %w[page_down pagedown ctrl_d].include?(search_page_key) ||
                          (has_ctrl && search_page_key == 'd') || key == "\x04"

    { pure_alt_space_handled: false, key: key, has_alt: has_alt, has_shift: has_shift, has_ctrl: has_ctrl, key_str: key_str,
      is_search_page_up: is_search_page_up, is_search_page_down: is_search_page_down, modifiers: modifiers }
  end

  def process_table_input_page_navigation(context, key)
    return true if context[:invalid_ctrl]

    is_shift_page_up   = context[:is_search_page_up] && context[:has_shift]
    is_shift_page_down = context[:is_search_page_down] && context[:has_shift]

    if is_shift_page_up || is_shift_page_down
      before_state = capture_selection_state
      # 🎯 CHIRURGISCHE LOCK: Voorkom dat dit event straks nóg een keer door handle_table_navigation stroomt!
      context[:page_navigation_consumed] = true

      enriched = enrich_table_input_context(context)
      start_row = enriched[:selected_row]
      total_rows = enriched[:number_of_rows]
      visible_height = enriched[:visible_height]
      current_offset = @table_viewport_offset.to_i

      # 🎯 EXACTE PARITEIT STAP: Zorgt voor exact dezelfde spronggrootte als de normale navigatie (visible_height - 1)
      step = table_page_step(visible_height)
      max_offset = [total_rows - visible_height, 0].max

      # 💻 Calculate the exact current screen row (the cursor's visible position).
      screen_row = start_row - current_offset

      # Calculate the viewport ... through the target_row calculation:
      # Viewport verschuift met het volledige aantal zichtbare regels.
      wanted_offset = current_offset + (is_shift_page_down ? step : -step)
      target_offset = [[wanted_offset, 0].max, max_offset].min

      # Selectie telt de beginregel mee: daarom step - 1.
      selection_step = [step - 1, 0].max

      target_row = if is_shift_page_down
                     [start_row + selection_step, total_rows - 1].min
                   else
                     [start_row - selection_step, 0].max
                   end

      @selection_anchor ||= start_row

      update_table_range_selection(@selection_anchor, target_row)

      # 🎯 EFFECTUERING NAAR DE INTERFACE
      @table_state.select(target_row) if @table_state
      set_table_viewport_offset(target_offset)

      if @search_matches && @search_matches.any?
        @search_page_viewport_start = @table_viewport_offset
      else
        @normal_page_viewport_start = @table_viewport_offset
      end

      record_selection_change(before_state)

      return true
    end

    if (context[:is_search_page_up] || context[:is_search_page_down]) &&
       (@active_focus == :replace_mode || (@search_matches && @search_matches.any?)) &&
       respond_to?(:handle_search_page_navigation, true)
      consumed = handle_search_page_navigation(key, context[:has_ctrl], context[:has_alt])
      context[:page_navigation_consumed] = true if consumed
    end
    true
  end

  def table_input_active_deck?(context)
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    return false if @library.subjects[s_idx].nil? ||
                    @library.subjects[s_idx].sources[src_idx].nil? ||
                    @library.subjects[s_idx].sources[src_idx].decks[d_idx].nil?

    true
  end

  def table_page_step(visible_rows)
    [visible_rows.to_i, 1].max
  end

  def enrich_table_input_context(context)
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    cards_list = @library.subjects[s_idx].sources[src_idx].decks[d_idx].cards || []
    number_of_rows = cards_list.length
    selected_row = @table_state.selected || 0
    terminal_height = RatatuiRuby.terminal_size&.height || 24
    @table_visible_height = [terminal_height - 10, 1].max
    visible_height = @table_visible_height || 10
    step = [table_page_step(visible_height) - 1, 1].max
    @total_pages = (number_of_rows.to_f / step).ceil
    @total_pages = [@total_pages, 1].max
    @current_page = (selected_row / step) + 1
    @current_page = [[@current_page, 1].max, @total_pages].min
    current_idx = @table_state.selected if defined?(@table_state) && @table_state
    normalized_nav_key = context[:key_str].tr('-', '_').downcase
    has_active_search = @search_matches && @search_matches.any?
    is_replace_mode = (@active_focus == :replace_mode)
    context.merge(cards_list: cards_list, number_of_rows: number_of_rows, selected_row: selected_row, visible_height: visible_height,
                  current_idx: current_idx, normalized_nav_key: normalized_nav_key, has_active_search: has_active_search, is_replace_mode: is_replace_mode)
  end

  def table_input_navigation_key?(key, context)
    normalized = context[:normalized_nav_key]

    %w[up down j k g G d u home end page_up page_down pageup
       pagedown].include?(normalized) || key == :page_up || key == :page_down
  end

  def handle_table_input_navigation(context, key, focus_on_enter)
    is_global_active = defined?(@global_search_active) && @global_search_active

    if (context[:has_active_search] || context[:is_replace_mode]) && !is_global_active
      return true if context[:has_shift] && %w[j k up down].include?(context[:normalized_nav_key])

      if !context[:has_shift] && %w[j k up down].include?(context[:normalized_nav_key])
        virtual_search_key = %w[j down].include?(context[:normalized_nav_key]) ? 'n' : 'N'
        handle_search_match_navigation(virtual_search_key)
        return true
      end
    end

    consumed = handle_table_navigation(key, context[:selected_row], context[:number_of_rows], context[:visible_height],
                                       context[:visible_height], context[:has_shift], context[:has_ctrl], context[:has_alt], focus_on_enter)
    return true if consumed

    false
  end

  def dispatch_table_input_key(key, focus_on_enter, context)
    case key
    when 'A'
      handle_table_select_all_visible(context)
    when '1', '2', '3', '4'
      handle_table_sorting(key)
    when 'up', 'down', 'j', 'k', 'J', 'K', 'g', 'G', 'd', 'u', 'home', 'end', 'page_up', 'page_down'
      handle_table_navigation(key, context[:selected_row], context[:number_of_rows], context[:visible_height],
                              context[:visible_height], context[:has_shift], context[:has_ctrl], focus_on_enter)
    when :space, 'space', ' ', "\u00A0", "\xC2\xA0", 'M', 'm'
      handle_table_space_input(key, context)
    when 'a', 'e', 't', 'b', 'enter', "\r", "\n", '+', 'f2', 'f7', '='
      # Als het '+' of '=' is, handelen we dit af als spraak of mutatie
      if key == '='
        handle_table_speech(context)
      else
        handle_table_mutation(key, context[:modifiers], focus_on_enter, context[:selected_row])
      end
    when 'n', 'N'
      handle_search_match_navigation(key)
    when 'backspace', "\x7f", '-', 'f8', :f8
      handle_card_deletion(key, context[:has_alt])
    else
      false
    end
  end

  def handle_table_speech(context)
    cards_list = context[:cards_list]
    row = context[:selected_row]
    return false if cards_list.nil? || cards_list.empty? || row.nil?

    card = cards_list[row]
    return false unless card

    speak_term(card.term)
    true
  end

  def handle_table_space_input(key, context)
    is_alt_space = (context[:key_str] == ' ' && context[:has_alt]) || context[:key_str] == "\u00A0" ||
                   context[:key_str] == "\xC2\xA0" || context[:key_str].bytes == [194, 160]
    is_shift_m = (context[:key_str] == 'M') || (%w[M].include?(context[:key_str]) && context[:has_shift])
    is_normal_space = (context[:key_str] == ' ' || key == :space) && !context[:has_shift] && !context[:has_alt] && !context[:has_ctrl]

    if context[:has_active_search] || context[:is_replace_mode]
      return true if %w[space M].include?(context[:key_str]) || is_alt_space

      false
    elsif is_normal_space && defined?(@selected_table_rows) && @selected_table_rows && @selected_table_rows.any?
      handle_table_bulk_study_toggle(context[:cards_list])
      true
    elsif is_shift_m || is_alt_space
      toggle_mark(context[:current_idx])
      false
    elsif context[:current_idx]
      handle_table_space_key(key, context[:current_idx])
      true
    else
      false
    end
  end

  # =========================================================================
  # 🎯 BULK STUDY TOGGLE ENGINE
  # Toggle the learned state of all selected cards at once.
  # Kijkt naar de status van de allereerste kaart om te bepalen of we alles
  # op true of op false gaan zetten (vloeibare toggle-as).
  # =========================================================================
  def handle_table_bulk_study_toggle(cards_list)
    return false if cards_list.nil? || cards_list.empty?
    return false unless @selected_table_rows && @selected_table_rows.any?

    # Resolve valid, unique cards before creating the snapshot.
    selected_cards = @selected_table_rows.filter_map do |idx|
      cards_list[idx]
    end.uniq

    return false if selected_cards.empty?

    # One snapshot for the entire bulk toggle.
    allow_snapshot! if respond_to?(:allow_snapshot!)
    save_history_snapshot if respond_to?(:save_history_snapshot)

    selected_cards.each do |card|
      card.study = !card.study
    end

    # Sla de library direct veilig op naar de harde schijf
    @library_dirty = true

    # Clear the selection checkmarks so the result is visible immediately.
    @selected_table_rows = []

    true
  end

  def handle_table_space_key(key, selected_row)
    key_str = key.to_s.strip
    return false unless key == :space || key_str == ''

    s_idx   = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx   = @current_deck_idx || 0
    deck = @library.subjects[s_idx]&.sources[src_idx]&.decks[d_idx]
    card = deck&.cards&.[](selected_row)
    return false unless card

    allow_snapshot! if respond_to?(:allow_snapshot!)

    save_history_snapshot if respond_to?(:save_history_snapshot)
    card.study = !card.study
    @library_dirty = true
    true
  end

  def toggle_mark(index)
    return unless index

    @selected_table_rows ||= []
    if @selected_table_rows.include?(index)
      @selected_table_rows.delete(index)
    else
      @selected_table_rows << index
    end
    true
  end

  def handle_table_sorting(key)
    key_str = key.to_s.strip
    return false unless %w[1 2 3 4].include?(key_str)
    return false unless @active_focus == :table

    target_column = case key_str
                    when '1' then :study
                    when '2' then :term
                    when '3' then :context
                    when '4' then :meaning
                    end

    if target_column
      # De driehoek is een tijdelijke visuele indicator: een nieuwe 1-4-actie
      # makes it visible while preserving the underlying sort order.
      @sort_indicator_visible = true

      # Toggle sorting direction if the same column is triggered again
      if @current_sort_col == target_column
        @current_sort_dir = @current_sort_dir == :asc ? :desc : :asc
      else
        # Brand new column selected: default to ascending order
        @current_sort_col = target_column
        @current_sort_dir = :asc
      end

      # Dynamische deck-selectie op basis van actieve indices
      s_idx   = @current_subject_idx || 0
      src_idx = @current_source_idx || 0
      d_idx   = @current_deck_idx || 0
      current_deck = @library.subjects[s_idx].sources[src_idx].decks[d_idx]

      current_deck.sort!(@current_sort_col, @current_sort_dir)

      # Reset the table cursor to row 1 to prevent out-of-bounds crashes.
      @table_state.select(0)
      @table_state.scroll_up_by(current_deck.cards.length) if @table_state.respond_to?(:scroll_up_by)
      return true # Sortering succesvol afgehandeld
    end

    false
  end

  def set_table_viewport_offset(offset)
    offset = [offset.to_i, 0].max
    # the app owns the table viewport explicitly, just like the reference
    # implementation: selected is an absolute row and this is the absolute
    # first visible row.  The renderer consumes this value directly.
    @table_viewport_offset = offset

    # Keep TableState in sync when the installed RatatuiRuby exposes a setter,
    # but never use scroll_*_by here: those methods change selection.
    if @table_state&.respond_to?(:set_offset)
      @table_state.set_offset(offset)
    elsif @table_state&.respond_to?(:offset=)
      @table_state.offset = offset
    end

    offset
  end

  def handle_table_navigation(key, selected_row, number_of_rows, step, visible_height, has_shift, has_ctrl, has_alt,
                              focus_on_enter = nil)
    key_data = build_table_navigation_context(
      key, selected_row, number_of_rows, visible_height,
      has_shift, has_ctrl, has_alt
    )
    return false unless key_data

    before_state = capture_selection_state

    target = calculate_table_navigation_target(key_data)

    if target[:consumed]
      record_selection_change(before_state)
      return true
    end

    apply_table_navigation_target(target, key_data)

    record_selection_change(before_state)

    true
  end

  def build_table_navigation_context(key, selected_row, number_of_rows, visible_height, has_shift, has_ctrl, has_alt)
    key_str = key.to_s.strip.sub(/\A:/, '')
    key_down = key_str.downcase
    nav_keys = %w[down up j k g d u home end page_down page_up pageup pagedown]
    return nil unless nav_keys.include?(key_down) || %i[down up home end page_up page_down].include?(key)
    return nil if number_of_rows.to_i <= 0

    total_rows = number_of_rows.to_i
    visible_rows = [[visible_height.to_i, 1].max, total_rows].min
    @selected_table_rows ||= []
    selected = if @table_state&.respond_to?(:selected) && !@table_state.selected.nil?
                 @table_state.selected.to_i
               else
                 selected_row.to_i
               end
    selected = [[selected, 0].max, total_rows - 1].min
    max_offset = [total_rows - visible_rows, 0].max
    current_offset = if defined?(@table_viewport_offset) && !@table_viewport_offset.nil?
                       @table_viewport_offset.to_i
                     elsif defined?(@normal_page_viewport_start) && !@normal_page_viewport_start.nil?
                       @normal_page_viewport_start.to_i
                     elsif @table_state&.respond_to?(:offset)
                       @table_state.offset.to_i
                     else
                       0
                     end
    current_offset = [[current_offset, 0].max, max_offset].min
    unless selected >= current_offset && selected < current_offset + visible_rows
      current_offset = selected < current_offset ? selected : [selected - visible_rows + 1, max_offset].min
    end
    screen_row = selected - current_offset
    is_ctrl_u = has_ctrl && key_down == 'u'
    is_ctrl_d = has_ctrl && key_down == 'd'
    is_page_up = %w[page_up pageup].include?(key_down) || key == :page_up || is_ctrl_u
    is_page_down = %w[page_down pagedown].include?(key_down) || key == :page_down || is_ctrl_d
    is_jump_to_top = (key_str == 'g' && !has_shift) || (key_down == 'home') || (key == :home)
    is_jump_to_bottom = (key_str == 'G') || (key_down == 'end') || (key == :end) || (has_shift && key_down == 'g')
    is_shift_j = (has_shift && key_down == 'down') || (has_shift && key_down == 'j')
    is_shift_k = (has_shift && key_down == 'up') || (has_shift && key_down == 'k')
    is_up = %w[up k].include?(key_down) && !has_shift
    is_down = %w[down j].include?(key_down) && !has_shift
    is_shift_m = %w[m M].include?(key_str) && has_shift
    is_alt_space = (key_str == ' ' && has_alt) || key_str == "\u00A0" || key_str == "\xC2\xA0" || key_str.bytes == [
      194, 160
    ]
    { key: key, key_str: key_str, key_down: key_down, total_rows: total_rows, visible_rows: visible_rows, max_offset: max_offset,
      selected: selected, current_offset: current_offset, screen_row: screen_row, is_page_up: is_page_up, is_page_down: is_page_down,
      is_jump_to_top: is_jump_to_top, is_jump_to_bottom: is_jump_to_bottom, is_shift_j: is_shift_j, is_shift_k: is_shift_k,
      is_up: is_up, is_down: is_down, is_shift_m: is_shift_m, is_alt_space: is_alt_space, has_shift: has_shift }
  end

  def calculate_table_navigation_target(data)
    selected = data[:selected]
    target_selected = selected
    target_offset = data[:current_offset]
    if data[:is_alt_space] || data[:is_shift_m]
      if @selected_table_rows.include?(selected)
        @selected_table_rows.delete(selected)
      else
        @selected_table_rows << selected
      end

      return { consumed: true }
    end
    if data[:is_page_up] || data[:is_page_down]
      page_step = table_page_step(data[:visible_rows])

      wanted_offset =
        data[:current_offset] +
        (data[:is_page_down] ? page_step : -page_step)

      # Laatste sprong naar beneden
      if data[:is_page_down] && wanted_offset >= data[:max_offset]
        target_offset = data[:max_offset]
        target_selected = data[:total_rows] - 1

      # Eerste sprong naar boven
      elsif data[:is_page_up] && wanted_offset <= 0
        target_offset = 0
        target_selected = 0

      # Normale paginasprong: oorspronkelijke schermregel behouden
      else
        target_offset = [
          [wanted_offset, 0].max,
          data[:max_offset]
        ].min

        wanted_selected = target_offset + data[:screen_row]

        target_selected = [
          [wanted_selected, 0].max,
          data[:total_rows] - 1
        ].min

        # Veiligheidscontrole binnen de zichtbare tabel
        viewport_last_row =
          target_offset + data[:visible_rows] - 1

        if target_selected > viewport_last_row
          target_selected = [
            viewport_last_row,
            data[:total_rows] - 1
          ].min
        end
      end
    elsif data[:is_jump_to_top]
      has_active_search = @search_matches && @search_matches.any?
      is_replace_mode = (@active_focus == :replace_mode)
      if has_active_search || is_replace_mode
        @search_current_match_idx = 0
        first_match_row = @search_matches[@search_current_match_idx]
        target_selected = first_match_row
        target_offset = (first_match_row / data[:visible_rows]) * data[:visible_rows]
        target_offset = [[target_offset, 0].max, data[:max_offset]].min
      else
        target_selected = 0
        target_offset = 0
      end
    elsif data[:is_jump_to_bottom]
      has_active_search = @search_matches && @search_matches.any?
      is_replace_mode = (@active_focus == :replace_mode)
      if has_active_search || is_replace_mode
        @search_current_match_idx = @search_matches.length - 1
        last_match_row = @search_matches[@search_current_match_idx]
        target_selected = last_match_row
        target_offset = (last_match_row / data[:visible_rows]) * data[:visible_rows]
        target_offset = [[target_offset, 0].max, data[:max_offset]].min
      else
        target_selected = data[:total_rows] - 1
        target_offset = data[:max_offset]
      end
    elsif data[:is_up] || data[:is_shift_k]
      target_selected = selected - 1
      if target_selected < 0
        target_selected = data[:total_rows] - 1
        target_offset = data[:max_offset]
      elsif target_selected < data[:current_offset]
        target_offset = target_selected
      end
    elsif data[:is_down] || data[:is_shift_j]
      target_selected = selected + 1
      if target_selected >= data[:total_rows]
        target_selected = 0
        target_offset = 0
      elsif target_selected >= data[:current_offset] + data[:visible_rows]
        target_offset = [target_selected - data[:visible_rows] + 1, data[:max_offset]].min
      end
    end
    if data[:has_shift] &&
       (data[:is_shift_j] || data[:is_shift_k] ||
        data[:is_page_up] || data[:is_page_down] ||
        data[:is_jump_to_top] || data[:is_jump_to_bottom])
      @selection_anchor ||= selected
      @selected_table_rows ||= []

      old_min, old_max = [@selection_anchor, selected].sort
      new_min, new_max = [@selection_anchor, target_selected].sort

      (old_min..old_max).each do |idx|
        @selected_table_rows.delete(idx) unless idx >= new_min && idx <= new_max
      end

      (new_min..new_max).each do |idx|
        @selected_table_rows << idx unless @selected_table_rows.include?(idx)
      end
    end

    target_selected = [[target_selected, 0].max, data[:total_rows] - 1].min
    target_offset = [[target_offset, 0].max, data[:max_offset]].min

    { target_selected: target_selected, target_offset: target_offset, consumed: false }
  end

  def apply_table_navigation_target(target, data)
    return true if target[:consumed]

    # Iedere gewone navigatie wist de rijselectie.
    clear_table_range_selection unless data[:has_shift]

    @table_state.select(target[:target_selected]) if @table_state
    set_table_viewport_offset(target[:target_offset])
    @search_page_viewport_start = target[:target_offset] if @search_matches && @search_matches.any?
    @normal_page_viewport_start = target[:target_offset] unless @search_matches && @search_matches.any?
    @current_card_idx = target[:target_selected]
  end

  def handle_table_mutation(key, modifiers, focus_on_enter, selected_row)
    context = build_table_mutation_context(key, modifiers, selected_row)
    return false unless context
    return handle_table_add_card(context) if context[:is_add_action]
    return handle_table_edit_card(context) if context[:is_edit_action]

    false
  end

  def build_table_mutation_context(key, modifiers, selected_row)
    return false unless @active_focus == :table || @active_focus == :replace_mode

    wipe_all_search_artifacts
    key_str = key.to_s.strip.downcase
    nav_mutation_keys = %w[a e enter f2 f7 + \r \n]
    return false unless nav_mutation_keys.include?(key_str) || key == :enter

    modifier_names = Array(modifiers).map { |m| m.to_s.downcase }
    has_alt = modifier_names.intersect?(%w[alt option meta])
    has_ctrl = modifier_names.intersect?(%w[ctrl control])
    lang = AppConfig.settings.language
    is_enter = ['enter', "\r", "\n"].include?(key_str)

    is_add_action = (((has_alt || has_ctrl) && is_enter) || key_str == '+' || key_str == 'f7' || key_str == 'a') && !has_ctrl
    is_edit_action = (!has_alt && !has_ctrl && is_enter) || key_str == 'f2' || key_str == 'e' && !has_ctrl

    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    active_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
    return false if active_deck.nil?

    { key: key, key_str: key_str, has_alt: has_alt, has_ctrl: has_ctrl, is_add_action: is_add_action,
      is_edit_action: is_edit_action, selected_row: selected_row, cards_list: active_deck.cards || [] }
  end

  def handle_table_add_card(context)
    cards_list = context[:cards_list]
    @last_focus = :table
    @selected_table_rows = []

    @popup.show(title: " #{AppConfig.settings.language_string(:table_title_add_card)} ", type: :form,
                fields: { term: RatinField.new(placeholder: AppConfig.settings.language_string(:table_placeholder_term)),
                          context: RatinField.new(placeholder: AppConfig.settings.language_string(:table_placeholder_context)),
                          meaning: RatinField.new(placeholder: AppConfig.settings.language_string(:table_placeholder_meaning)) }) do |form_data|
      term_str = form_data[:term].respond_to?(:text) ? form_data[:term].text.to_s.strip : form_data[:term].to_s.strip
      meaning_str = form_data[:meaning].respond_to?(:text) ? form_data[:meaning].text.to_s.strip : form_data[:meaning].to_s.strip
      context_str = form_data[:context].respond_to?(:text) ? form_data[:context].text.to_s.strip : form_data[:context].to_s.strip

      if term_str.empty? || meaning_str.empty?
        trigger_statusbar_message("#{AppConfig.settings.language_string(:statusbar_form_error)}: #{AppConfig.settings.language_string(:statusbar_term_meaning_required)}!")
        mark_popup_for_input_indicators
        @active_focus = :popup

        next false # 🔒 HOUDT DE POPUP STRIKT OPEN EN VOORKOMT DOORLEKKEN
      end

      allow_snapshot! if respond_to?(:allow_snapshot!)
      save_history_snapshot if respond_to?(:save_history_snapshot)
      cards_list << Card.new(term_str, context_str, meaning_str)
      @library_dirty = true
      @active_focus = :table
      @last_focus = :table
      @table_state.select(cards_list.length - 1)

      true
    end

    mark_popup_for_input_indicators
    @active_focus = :popup

    true
  end

  def clear_table_range_selection
    @selected_table_rows = []
    @selection_anchor = nil
  end

  def update_table_range_selection(anchor, target)
    @selected_table_rows ||= []

    first = [anchor, target].min
    last  = [anchor, target].max

    @selected_table_rows = (first..last).to_a
  end

  def handle_table_select_all_visible(context)
    before_state = capture_selection_state

    visible_rows =
      if context[:has_active_search] && @search_matches
        @search_matches.dup
      else
        (0...context[:number_of_rows].to_i).to_a
      end

    @selected_table_rows = visible_rows
    @selection_anchor = visible_rows.first

    unless visible_rows.empty?
      @table_state.select(visible_rows.first) if @table_state
      @current_card_idx = visible_rows.first
    end

    set_table_viewport_offset(0) if respond_to?(:set_table_viewport_offset)

    record_selection_change(before_state)
    true
  end

  def handle_table_edit_card(context)
    cards_list = context[:cards_list]
    settings = AppConfig.settings

    if cards_list.nil? || cards_list.empty?
      if respond_to?(:trigger_statusbar_message)
        error_msg = [
          settings.language_string(:statusbar_table_error),
          settings.language_string(:statusbar_deck_empty)
        ].join(': ')

        trigger_statusbar_message("#{error_msg}!", type: :warning, beep: settings.beeps)
      end
      return true # Slik de toetsaanslag in; er valt immers niets te openen
    end

    selected_card = cards_list[context[:selected_row]]
    return false unless selected_card

    fields = build_table_edit_fields(selected_card)
    # Bewaar waar de gebruiker vandaan kwam vóór het openen van de editor.
    @focus_before_card_edit = @active_focus unless @active_focus == :popup
    # Behoud het bestaande terugvalgedrag voor normale tabelbewerkingen.
    @last_focus = :table
    @selected_table_rows = []

    @popup.show(title: " #{AppConfig.settings.language_string(:table_title_edit_card)} ", type: :form,
                fields: fields) do |form_data|
      # 🎯 DE RETOUR-BRANDMUUR: apply_table_edit_form geeft nu true of false terug.
      # Als de invoer ongeldig is (false), roepen we HIER binnen het blok 'next false' aan!
      success = apply_table_edit_form(selected_card, context[:selected_row], form_data)

      next false unless success

      true
    end
    mark_popup_for_input_indicators
    @active_focus = :popup
    true
  end

  def build_table_edit_fields(selected_card)
    p_term = begin
      AppConfig.settings.language_string(:table_placeholder_term)
    rescue StandardError
      'Term'
    end

    p_context = begin
      AppConfig.settings.language_string(:table_placeholder_context)
    rescue StandardError
      'Context'
    end

    p_meaning = begin
      AppConfig.settings.language_string(:table_placeholder_meaning)
    rescue StandardError
      'Meaning'
    end

    term_field = RatinField.new(placeholder: p_term)
    context_field = RatinField.new(placeholder: p_context)
    meaning_field = RatinField.new(placeholder: p_meaning)

    term_field.text = selected_card.term.to_s + ''
    context_field.text = selected_card.context.to_s + ''
    meaning_field.text = selected_card.meaning.to_s + ''

    term_field.cursor_index = term_field.text.length
    context_field.cursor_index = context_field.text.length
    meaning_field.cursor_index = meaning_field.text.length

    { term: term_field, context: context_field, meaning: meaning_field }
  end

  def apply_table_edit_form(selected_card, selected_row, form_data)
    settings = AppConfig.settings
    edit_term_str = form_data[:term].respond_to?(:text) ? form_data[:term].text.to_s.strip : form_data[:term].to_s.strip
    edit_meaning_str = form_data[:meaning].respond_to?(:text) ? form_data[:meaning].text.to_s.strip : form_data[:meaning].to_s.strip
    edit_context_str = form_data[:context].respond_to?(:text) ? form_data[:context].text.to_s.strip : form_data[:context].to_s.strip

    term_valid = !edit_term_str.empty?
    meaning_valid = !edit_meaning_str.empty?

    if !term_valid || !meaning_valid
      trigger_statusbar_message("#{settings.language_string(:statusbar_form_error)}: #{settings.language_string(:statusbar_term_meaning_required)}!")
      @active_focus = :popup
      return false # 🔒 Vertelt het codeblok om open te blijven via next false
    end

    changes = {
      term: edit_term_str,
      context: edit_context_str,
      meaning: edit_meaning_str
    }.reject do |field, value|
      selected_card.public_send(field).to_s == value
    end

    unless changes.empty?
      allow_snapshot! if respond_to?(:allow_snapshot!)
      save_history_snapshot if respond_to?(:save_history_snapshot)

      changes.each do |field, value|
        selected_card.public_send("#{field}=", value)
      end

      @library_dirty = true
    end

    @active_focus = :table
    @last_focus = :table
    @table_state.select(selected_row)
    @active_cards_cache_node = nil if instance_variable_defined?(:@active_cards_cache_node)
    @active_cards_cache_cards = nil if instance_variable_defined?(:@active_cards_cache_cards)

    true
  end

  def handle_card_deletion(key, has_alt)
    context = build_card_deletion_context(key, has_alt)
    return false unless context
    return handle_multi_card_deletion(context) if context[:multi_select]

    handle_single_card_deletion(context)
  end

  def build_card_deletion_context(key, has_alt)
    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    unless @library.subjects[s_idx] && @library.subjects[s_idx].sources[src_idx] && @library.subjects[s_idx].sources[src_idx].decks[d_idx]
      return false
    end

    cards_list = @library.subjects[s_idx].sources[src_idx].decks[d_idx].cards
    key_str = key.to_s.strip.downcase
    return false unless ['f8', '-', 'backspace', "\x7f", '127'].include?(key_str) || key == :backspace
    return false if has_alt

    multi_select = (key == :backspace || %w[backspace \x7f
                                            127].include?(key_str)) && defined?(@selected_table_rows) && @selected_table_rows && @selected_table_rows.any?
    { cards_list: cards_list, key: key, key_str: key_str, multi_select: multi_select }
  end

  def handle_multi_card_deletion(context)
    cards_list = context[:cards_list]
    valid_indices = @selected_table_rows.select do |idx|
      idx.is_a?(Integer) && idx >= 0 && idx < cards_list.length
    end

    return false if valid_indices.empty?

    first_selected_idx = valid_indices.min
    target_cursor_idx = [first_selected_idx - 1, 0].max

    allow_snapshot! if respond_to?(:allow_snapshot!)
    save_history_snapshot if respond_to?(:save_history_snapshot)

    valid_indices.sort.reverse_each { |idx| cards_list.delete_at(idx) }

    @library_dirty = true
    @selected_table_rows = []

    if cards_list.empty?
      @table_state.select(nil)
    else
      safe_idx = [target_cursor_idx, cards_list.length - 1].min
      @table_state.select(safe_idx)
    end

    execute_search(@last_search_query) if respond_to?(:execute_search) && @last_search_query
    wipe_all_search_artifacts if respond_to?(:wipe_all_search_artifacts)
    true
  end

  def handle_single_card_deletion(context)
    row = @table_state.selected if @table_state
    return false unless row

    cards_list = context[:cards_list]
    return false unless row.is_a?(Integer) && row >= 0 && row < cards_list.length

    wipe_all_search_artifacts if respond_to?(:wipe_all_search_artifacts)

    allow_snapshot! if respond_to?(:allow_snapshot!)
    save_history_snapshot if respond_to?(:save_history_snapshot)

    cards_list.delete_at(row)
    @library_dirty = true
    new_total_rows = cards_list.length

    if new_total_rows.zero?
      @table_state.select(nil)
    elsif row >= new_total_rows
      @table_state.select(new_total_rows - 1)
    else
      @table_state.select(row)
    end

    execute_search(@last_search_query) if respond_to?(:execute_search) && @last_search_query
    true
  end
end
