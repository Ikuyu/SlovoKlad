module SearchInputHandler
  # Generates a regular expression that treats accents as optional ONLY on targeted scripts
  def build_script_insensitive_regex(query_text, case_sensitive = false, ignore_accents = false)
    return nil if query_text.to_s.empty?

    query = query_text.to_s.unicode_normalize(:nfd)
    source = +''
    previous_target = false

    query.each_char do |char|
      if char.match?(/\A\p{M}\z/)
        source << Regexp.escape(char) unless ignore_accents || previous_target
        next
      end

      is_target = target_script_char?(char)
      source << Regexp.escape(char)

      if ignore_accents || is_target
        source << '\p{M}*'
      elsif char.match?(/\A[a-zA-Z]\z/)
        source << '(?!\p{M})'
      end

      previous_target = is_target
    end

    Regexp.new(source, case_sensitive ? 0 : Regexp::IGNORECASE)
  end

  def target_script_char?(char)
    char.match?(/\A[\p{Cyrillic}\p{Han}\p{Hiragana}\p{Katakana}]\z/)
  end

  def normalize_target_scripts(text, case_sensitive = false, ignore_accents = false)
    return '' if text.nil?

    normalized = text.to_s.unicode_normalize(:nfd)
    result = +''
    previous_target = false

    normalized.each_char do |char|
      if char.match?(/\A\p{M}\z/)
        result << char unless ignore_accents || previous_target
        next
      end

      result << char
      previous_target = target_script_char?(char)
    end

    result = result.unicode_normalize(:nfc)
    case_sensitive ? result : result.downcase
  end

  # center_on_match centreert de zichtbare tekst en kort ze in (truncate)
  def center_on_match(full_text, query_text, max_width, case_sensitive = false, ignore_accents = false)
    full_str  = full_text.to_s
    query_str = query_text.to_s

    return full_str if query_str.empty? || full_str.length <= max_width

    # Determine regex mode safely
    is_regex_mode = (@table_regex_mode == true) ||
                    (defined?(@global_search_regex_mode) &&
                     @global_search_regex_mode == true)

    # Compile the search rule
    search_regex = if is_regex_mode
                     flags = case_sensitive ? 0 : Regexp::IGNORECASE
                     Regexp.new(query_str, flags)
                   else
                     build_script_insensitive_regex(query_str, case_sensitive, ignore_accents)
                   end

    # Normalize each original character separately and map every
    # resulting NFD character back to its original character index.
    nfd_parts = []
    nfd_to_original = []

    full_str.each_char.with_index do |char, original_idx|
      normalized_chars = char.unicode_normalize(:nfd).each_char.to_a
      nfd_parts.concat(normalized_chars)
      normalized_chars.each { nfd_to_original << original_idx }
    end

    if is_regex_mode
      # Regex mode: search the original text so literal composed
      # characters in the user's regex can match as entered.
      match = full_str.match(search_regex)

      return full_str[0, max_width] unless match

      match_start = match.begin(0)
      match_end   = match.end(0)
    else
      # Normal mode: search normalized text and map positions back.
      nfd_full = nfd_parts.join
      match = nfd_full.match(search_regex)

      return full_str[0, max_width] unless match
    end

    # Fall back safely if no match is found
    return full_str[0, max_width] unless match

    match_start_nfd = match.begin(0)
    match_end_nfd   = match.end(0)

    # Translate the NFD match boundaries back to original character indices.
    if match_start_nfd == match_end_nfd
      match_start = if match_start_nfd < nfd_to_original.length
                      nfd_to_original[match_start_nfd]
                    else
                      full_str.length
                    end
      match_end = match_start
    else
      match_start = nfd_to_original[match_start_nfd]
      match_end   = nfd_to_original[match_end_nfd - 1] + 1
    end

    # Center the visible segment around the actual matched text.
    match_length = match_end - match_start
    half_width = (max_width - match_length) / 2

    start_pos = match_start - half_width
    start_pos = [[start_pos, 0].max, [full_str.length - max_width, 0].max].min

    # If the match is longer than the window, start at the match.
    start_pos = [[match_start, 0].max, [full_str.length - max_width, 0].max].min if match_length > max_width

    segment = full_str[start_pos, max_width]

    # Add visual ellipses when text is clipped
    segment[0..2] = '… ' if start_pos > 0 && segment.length >= 3
    segment[-3..-1] = ' …' if start_pos + max_width < full_str.length && segment.length >= 3

    segment
  end

  # This function is called from the table, but not from the table's replace function.
  def handle_table_escape_key(key)
    key_str = key.to_s.strip.sub(/\A:/, '').downcase
    return false unless ['esc', "\e", 'escape'].include?(key_str) || key == :escape

    wipe_all_search_artifacts

    true # Consumeer het escape-event succesvol en hou de app open!
  end

  def handle_search_escape_key(key)
    key_str = key.to_s.strip.downcase
    return false unless ['esc', "\e", 'escape'].include?(key_str) || key == :escape

    # 1. CHECK FOR SPECIFICATION CONSTRAINT:
    # Are we currently in normal navigation (not searching or replacing)?
    has_active_search = defined?(@tree_search_matches) && @tree_search_matches && @tree_search_matches.any?
    is_replace_mode = (@active_focus == :replace_mode)

    unless has_active_search || is_replace_mode
      # =====================================================================
      # SUCCESS TRIGGER: This code runs on your physical ESC key press!
      # We clear out all manual folder tracking paths instantly.
      # =====================================================================
      @selected_tree_paths = []
      @selected_table_rows = [] if defined?(@selected_table_rows)

      trigger_system_beep if respond_to?(:trigger_system_beep)

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      return true # Consume event and stop further evaluation loops
    end

    # 2. Existing layout fallback pipeline (Runs only when search/replace IS active):
    @search_matches           = nil
    @search_current_match_idx = nil
    @last_search_query        = nil
    @last_replace_text        = nil
    @search_query             = '' if defined?(@search_query)
    @table_case_sensitive     = nil
    @table_ignore_accents = false
    @last_case_sensitive      = nil
    @last_regex               = nil

    @tree_search_matches      = nil
    @tree_search_current_idx  = nil
    @last_tree_search_query   = nil
    @tree_case_sensitive      = nil
    @tree_ignore_accents = false
    @selected_table_rows = [] if defined?(@selected_table_rows)

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  end

  def handle_search_page_navigation(key, has_ctrl = false, has_alt = false)
    key_str = key.to_s.strip.sub(/\A:/, '').downcase

    raw_ctrl_u = key == "\x15" || key_str == "\x15"
    raw_ctrl_d = key == "\x04" || key_str == "\x04"

    normalized_key = key_str.tr('-', '_')
    is_page_up = %w[page_up pageup ctrl_u].include?(normalized_key) ||
                 (has_ctrl && key_str == 'u') || raw_ctrl_u
    is_page_down = %w[page_down pagedown ctrl_d].include?(normalized_key) ||
                   (has_ctrl && key_str == 'd') || raw_ctrl_d
    return false unless is_page_up || is_page_down

    if @active_focus == :tree && @tree_search_matches && @tree_search_matches.any?
      navigate_tree_search_by_page(is_page_up: is_page_up)

    elsif @active_focus == :replace_mode && @last_focus == :tree &&
          @tree_search_matches && @tree_search_matches.any?
      navigate_tree_search_by_page(is_page_up: is_page_up)

    elsif @active_focus == :table &&
          @search_matches &&
          @search_matches.any?
      navigate_table_search_by_page(is_page_up: is_page_up)

    elsif @active_focus == :replace_mode &&
          @last_focus == :table &&
          @search_matches &&
          @search_matches.any?
      navigate_table_search_by_page(is_page_up: is_page_up)
    else
      false
    end
  end

  def select_table_search_match(row, match_idx = nil)
    return false unless @table_state

    row = row.to_i
    return false if row.negative?

    @search_current_match_idx = match_idx || @search_matches.index(row)
    @current_card_idx = row
    @table_state.select(row)

    @table_state.select(row) if @table_state.respond_to?(:selected) && @table_state.selected.to_i != row

    true
  end

  def table_search_page_size
    return @table_visible_height.to_i if defined?(@table_visible_height) && @table_visible_height.to_i > 0

    terminal_height = if defined?(RatatuiRuby) && RatatuiRuby.respond_to?(:terminal_size)
                        RatatuiRuby.terminal_size&.height
                      end
    [((terminal_height || 24).to_i - 10), 1].max
  end

  def navigate_tree_search_by_page(is_page_up:)
    context = build_tree_search_page_context
    return false unless context

    target = find_tree_search_page_target(context, is_page_up)
    return false unless target

    apply_tree_search_page_target(context, target)
  end

  def build_tree_search_page_context
    return false unless @tree_search_matches && @tree_search_matches.any?

    page_size = [(@tree_visible_height || 1).to_i, 1].max
    visible_nodes = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
    return false if visible_nodes.empty?

    total_count = visible_nodes.length
    current_index = @tree_state&.respond_to?(:selected) ? @tree_state.selected.to_i : 0
    current_index = [[current_index, 0].max, total_count - 1].min

    viewport_start = if defined?(@tree_page_viewport_start) && !@tree_page_viewport_start.nil?
                       @tree_page_viewport_start.to_i
                     elsif @tree_state&.respond_to?(:offset)
                       @tree_state.offset.to_i
                     else
                       (current_index / page_size) * page_size
                     end
    max_offset = [total_count - page_size, 0].max
    viewport_start = [[viewport_start, 0].max, max_offset].min
    cursor_row = [[current_index - viewport_start, 0].max, page_size - 1].min

    match_indices = @tree_search_matches.filter_map do |path|
      visible_nodes.index { |node| node[:path] == path }
    end.uniq.sort
    return false if match_indices.empty?

    { page_size: page_size, visible_nodes: visible_nodes, total_count: total_count,
      current_index: current_index, viewport_start: viewport_start, max_offset: max_offset,
      cursor_row: cursor_row, match_indices: match_indices }
  end

  def find_tree_search_page_target(context, is_page_up)
    first_match = context[:match_indices].first
    last_match = context[:match_indices].last
    direction = is_page_up ? -1 : 1
    desired_index = context[:current_index] + (direction * context[:page_size])

    target_index = if direction.negative?
                     upper_bound = [desired_index, context[:current_index] - 1].min
                     candidates = context[:match_indices].select { |idx| idx <= upper_bound }
                     candidates.last || first_match
                   else
                     lower_bound = [desired_index, context[:current_index] + 1].max
                     candidates = context[:match_indices].select { |idx| idx >= lower_bound }
                     candidates.first || last_match
                   end

    target_index = [[target_index, first_match].max, last_match].min
    target_offset = target_index - context[:cursor_row]
    target_offset = [[target_offset, 0].max, context[:max_offset]].min

    { target_index: target_index, target_offset: target_offset,
      target_path: context[:visible_nodes][target_index][:path] }
  end

  def apply_tree_search_page_target(context, target)
    target_path = target[:target_path]
    @tree_search_current_idx = @tree_search_matches.index(target_path)
    @tree_state.select(target[:target_index]) if @tree_state
    @tree_page_viewport_start = target[:target_offset]
    set_tree_page_offset(target[:target_offset]) if respond_to?(:set_tree_page_offset, true)
    @tree.selected_path = target_path

    # ➔ DE LOCK IS HIER NU VOLLEDIG GESANEERD! VEILIG EN SCHOON.

    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
    true
  end

  def navigate_table_search_by_page(is_page_up:)
    context = build_table_search_page_context
    return false unless context

    target = find_table_search_page_target(context, is_page_up)
    return false unless target

    apply_table_search_page_target(context, target)
  end

  def build_table_search_page_context
    return false unless @table_state
    return false unless @search_matches && @search_matches.any?

    s_idx = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx = @current_deck_idx || 0
    cards = begin
      @library.subjects[s_idx].sources[src_idx].decks[d_idx].cards || []
    rescue StandardError
      @active_cards || []
    end
    total_count = cards.length
    return false if total_count <= 0

    page_size = [table_search_page_size.to_i, 1].max
    matches = @search_matches.map(&:to_i).select { |i| i >= 0 && i < total_count }.uniq.sort
    return false if matches.empty?

    current_index = @table_state.selected.nil? ? 0 : @table_state.selected.to_i
    viewport_start = if defined?(@search_page_viewport_start) && !@search_page_viewport_start.nil?
                       @search_page_viewport_start.to_i
                     elsif @table_state.respond_to?(:offset)
                       @table_state.offset.to_i
                     else
                       (current_index / page_size) * page_size
                     end
    max_offset = [total_count - page_size, 0].max
    viewport_start = [[viewport_start, 0].max, max_offset].min
    cursor_row = [[current_index - viewport_start, 0].max, page_size - 1].min

    { page_size: page_size, total_count: total_count, matches: matches,
      current_index: current_index, viewport_start: viewport_start, max_offset: max_offset,
      cursor_row: cursor_row }
  end

  def find_table_search_page_target(context, is_page_up)
    target_offset = context[:viewport_start]
    target_index = nil
    direction = is_page_up ? -1 : 1

    loop do
      candidate_offset = target_offset + (direction * context[:page_size])
      candidate_offset = [[candidate_offset, 0].max, context[:max_offset]].min
      break if candidate_offset == target_offset

      page_end = [candidate_offset + context[:page_size] - 1, context[:total_count] - 1].min
      page_matches = context[:matches].select { |idx| idx >= candidate_offset && idx <= page_end }
      unless page_matches.empty?
        target_index = is_page_up ? page_matches.last : page_matches.first
        target_offset = candidate_offset
        break
      end
      target_offset = candidate_offset
    end

    return nil unless target_index

    target_offset = [[target_index - context[:cursor_row], 0].max, context[:max_offset]].min
    { target_index: target_index, target_offset: target_offset }
  end

  def apply_table_search_page_target(context, target)
    @table_state.select(target[:target_index])
    @search_page_viewport_start = target[:target_offset]
    @normal_page_viewport_start = nil if defined?(@normal_page_viewport_start)
    @current_card_idx = target[:target_index]
    @search_current_match_idx = @search_matches.index(target[:target_index]) || @search_current_match_idx
    set_table_viewport_offset(target[:target_offset]) if respond_to?(:set_table_viewport_offset, true)
    true
  end

  def state_viewport_start(state, current_index, page_size)
    if state && state.respond_to?(:offset)
      [state.offset.to_i, 0].max
    else
      (current_index / page_size) * page_size
    end
  end

  def handle_search_match_navigation(key, shift_override = false)
    # =========================================================================
    # 🌲 📊 UNIFIED CHRONOLOGICAL SEARCH DIRECTION ENGINE (Symbool-Veilig)
    # =========================================================================
    if defined?(@global_search_active) && @global_search_active && @global_search_matches && @global_search_matches.any?
      key_str = key.to_s.strip.downcase
      shift_active = (shift_override == true) || (defined?(@has_shift) && @has_shift)

      # 🎯 DE ATOMAIRE RICHTING MATRICERING:
      # We controleren zowel de key_str als het rauwe key-object (voor :up symbolen)
      is_backward = %w[k up].include?(key_str) ||
                    key == :up ||
                    key.to_s == 'up' ||
                    (key_str == 'n' && shift_active) ||
                    key_str == 'N'

      step = is_backward ? -1 : 1

      # Bereken de nieuwe pointer-index via de database modulo omloop
      new_idx = (@global_search_current_idx.to_i + step) % @global_search_matches.length

      # Perform the jump while keeping focus in the table.
      jump_to_global_search_match(new_idx)

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      return true
    end

    # Fallback voor normale stand
    navigation = build_search_match_navigation(key, shift_override)
    return false unless navigation

    if navigation[:tree_context]
      handle_tree_search_match_navigation(navigation)
    else
      handle_table_search_match_navigation(navigation)
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  end

  def execute_global_replace_all(query_text, replace_text, case_sensitive: false, regex_mode: false,
                                 ignore_accents: false)
    return if query_text.to_s.strip.empty?

    search_regex = if regex_mode
                     flags = case_sensitive ? 0 : Regexp::IGNORECASE
                     Regexp.new(query_text.to_s, flags)
                   else
                     build_script_insensitive_regex(query_text, case_sensitive, ignore_accents)
                   end

    snapshot_saved = false
    changes_made = false

    @library.subjects.each do |sub|
      sub.sources.each do |src|
        src.decks.each do |deck|
          Array(deck.cards).each do |card|
            %i[term context meaning].each do |field|
              original_text = card.public_send(field).to_s

              updated_text = if regex_mode
                               original_text.gsub(search_regex, replace_text)
                             else
                               original_text.unicode_normalize(:nfd)
                                            .gsub(search_regex, replace_text)
                                            .unicode_normalize(:nfc)
                             end

              next if updated_text == original_text

              unless snapshot_saved
                save_global_transaction_snapshot if respond_to?(:save_global_transaction_snapshot, true)
                snapshot_saved = true
              end

              card.public_send("#{field}=", updated_text)
              changes_made = true
            end
          end
        end
      end
    end

    @library_dirty = true if changes_made

    @interactively_replacing = false
    @replace_action_performed = false
    @active_focus = :table
    @last_focus = :table

    if respond_to?(:wipe_all_search_artifacts, true)
      wipe_all_search_artifacts
    else
      @global_search_active = false
      @global_search_query = nil
      @global_search_matches = []
      @global_search_matched_deck_ids = []
      @search_matches = nil
    end

    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def execute_global_replace_all_decks
    return false unless @global_search_active
    return false if @global_search_matches.nil? || @global_search_matches.empty?
    return false if @last_replace_text.nil?

    execute_global_replace_all(
      @global_search_query,
      @last_replace_text,
      case_sensitive: !!@global_search_case_sensitive,
      regex_mode: !!@global_search_regex_mode,
      ignore_accents: !!@global_search_ignore_accents
    )

    true
  end

  def build_search_match_navigation(key, shift_override)
    key_str = key.to_s.strip
    key_down = key_str.downcase
    shift_active = (shift_override == true) || (defined?(@has_shift) && @has_shift) || (defined?(has_shift) && has_shift)
    semantic_key = key_down == 'n' && shift_active ? 'N' : key_str

    is_replace = (@active_focus == :replace_mode)
    has_table_matches = @search_matches && @search_matches.any?
    has_tree_matches = @tree_search_matches && @tree_search_matches.any?
    return false unless is_replace || has_table_matches || has_tree_matches

    is_tree_context = has_tree_matches && (@active_focus == :tree || @active_focus == :popup || is_replace)
    is_first_match = (key_str == 'g') || (key_str == 'home') || (key == :home) ||
                     (!is_tree_context && key_str == 'up' && shift_active) ||
                     (!is_tree_context && key == :up && shift_active)
    is_last_match = (key_str == 'G') || (key_str == 'end') || (key == :end) ||
                    (!is_tree_context && key_str == 'down' && shift_active) ||
                    (!is_tree_context && key == :down && shift_active)

    raw_key_string = key.to_s.strip
    is_ctrl_n = raw_key_string == "\x0E" || key_down == 'ctrl_n' || (defined?(has_ctrl) && has_ctrl && key_down == 'n')
    is_ctrl_p = raw_key_string == "\x10" || key_down == 'ctrl_p' || (defined?(has_ctrl) && has_ctrl && key_down == 'p')

    is_backward = !is_first_match && !is_last_match && %w[up k].include?(key_down) && !shift_active ||
                  (!is_first_match && !is_last_match && semantic_key == 'N') ||
                  (!is_first_match && !is_last_match && key == :up && !shift_active) || is_ctrl_p
    is_forward = !is_first_match && !is_last_match && %w[down j].include?(key_down) && !shift_active ||
                 (!is_first_match && !is_last_match && semantic_key == 'n') ||
                 (!is_first_match && !is_last_match && key == :down && !shift_active) || is_ctrl_n

    { key_str: key_str, key_down: key_down, tree_context: is_tree_context, first_match: is_first_match,
      last_match: is_last_match, backward: is_backward, forward: is_forward }
  end

  def handle_tree_search_match_navigation(navigation)
    return false unless @tree_search_matches && @tree_search_matches.any?

    total_matches = @tree_search_matches.length
    if navigation[:first_match]
      @tree_search_current_idx = 0
    elsif navigation[:last_match]
      @tree_search_current_idx = total_matches - 1
    elsif navigation[:forward]
      @tree_search_current_idx = (@tree_search_current_idx.to_i + 1) % total_matches
    elsif navigation[:backward]
      @tree_search_current_idx = (@tree_search_current_idx.to_i - 1) % total_matches
    end

    target_path = @tree_search_matches[@tree_search_current_idx]
    return false unless target_path

    expand_tree_search_target(target_path)
    jump_to_absolute_tree_search_index(target_path)
    true
  end

  def handle_table_search_match_navigation(navigation)
    return false unless @search_matches && @search_matches.any?

    total_len = @search_matches.length
    @search_current_match_idx = if navigation[:first_match]
                                  0
                                elsif navigation[:last_match]
                                  total_len - 1
                                elsif navigation[:backward]
                                  (@search_current_match_idx - 1) % total_len
                                else
                                  (@search_current_match_idx + 1) % total_len
                                end

    target_row = @search_matches[@search_current_match_idx]
    if @table_state
      @table_state.select(target_row)
      @current_card_idx = target_row
    end
    true
  end

  def handle_all_interactive_replace(is_tree_mode)
    is_strict = is_tree_mode ? @tree_case_sensitive : @table_case_sensitive
    raw_query = is_tree_mode ? @last_tree_search_query : @last_search_query
    return false if raw_query.to_s.empty?

    regex_mode = is_tree_mode ? !!@tree_regex_mode : !!@table_regex_mode
    ignore_accents = is_tree_mode ? !!@tree_ignore_accents : !!@table_ignore_accents

    regex = if regex_mode
              flags = is_strict ? 0 : Regexp::IGNORECASE
              Regexp.new(raw_query.to_s, flags)
            else
              build_script_insensitive_regex(raw_query, is_strict, ignore_accents)
            end

    safe_replace_str =
      if defined?(@last_replace_text) && @last_replace_text &&
         !@last_replace_text.to_s.strip.empty?
        @last_replace_text.to_s
      else
        ''
      end

    changes_made = false

    replace_field = lambda do |object, field|
      original_text = object.public_send(field).to_s
      normalized_text = original_text.unicode_normalize(:nfd)
      updated_text = normalized_text.gsub(regex, safe_replace_str)
                                    .unicode_normalize(:nfc)

      next if updated_text == original_text

      unless changes_made
        allow_snapshot! if respond_to?(:allow_snapshot!)
        save_history_snapshot if respond_to?(:save_history_snapshot)
      end

      object.public_send("#{field}=", updated_text)
      changes_made = true
    end

    if is_tree_mode
      if @tree_search_matches && @tree_search_matches.any?
        @tree_search_matches.each do |path|
          next unless path.is_a?(Array)

          case path.length
          when 1
            obj = @library.subjects.find { |s| s.id.to_s == path[0].to_s }
            replace_field.call(obj, :name) if obj
          when 2
            sub = @library.subjects.find { |s| s.id.to_s == path[0].to_s }
            obj = sub&.sources&.find { |src| src.id.to_s == path[1].to_s }
            replace_field.call(obj, :name) if obj
          when 3
            sub = @library.subjects.find { |s| s.id.to_s == path[0].to_s }
            src = sub&.sources&.find { |src| src.id.to_s == path[1].to_s }
            obj = src&.decks&.find { |d| d.id.to_s == path[2].to_s }
            replace_field.call(obj, :name) if obj
          end
        end
      end

      @tree_search_matches = nil
      @tree_search_current_idx = nil
      @last_replace_text = nil
      @active_focus = :tree
      @last_focus = :tree

      sort_library_tree_layers! if changes_made && respond_to?(:sort_library_tree_layers!)
    else
      s_idx = @current_subject_idx || 0
      src_idx = @current_source_idx || 0
      d_idx = @current_deck_idx || 0

      target_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
      cards_list = target_deck ? target_deck.cards : []

      if @search_matches && @search_matches.any?
        @search_matches.each do |current_card_idx|
          card = cards_list[current_card_idx]
          next unless card

          %i[term context meaning].each do |field|
            replace_field.call(card, field)
          end
        end
      end

      @search_matches = nil
      @search_current_match_idx = nil
      @last_search_query = nil
      @last_replace_text = nil
      @active_focus = :table
      @last_focus = :table
    end

    @interactively_replacing = false
    @library_dirty = true if changes_made
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)

    true
  end

  def handle_interactive_replace_mode(key, has_shift, modifiers = [])
    return false unless @active_focus == :replace_mode || @interactively_replacing == true

    key_str = key.to_s.strip.downcase
    is_tree_mode = @tree_search_matches && @tree_search_matches.any?

    case key
    when 'y'
      return handle_single_interactive_replace(is_tree_mode)
    when 'a'
      return handle_all_interactive_replace(is_tree_mode)
    when 'g', 'home', :home
      return handle_interactive_replace_jump_to_top(is_tree_mode)
    when 'G', 'end', :end
      return handle_interactive_replace_jump_to_bottom(is_tree_mode)
    when 'n', 'down', :down, 'j'
      return handle_interactive_replace_forward(is_tree_mode, has_shift)
    when 'up', :up, 'N', 'k'
      return handle_interactive_replace_backward(is_tree_mode, key_str, has_shift)
    end

    true
  end

  def handle_single_interactive_replace(is_tree_mode)
    is_strict = is_tree_mode ? @tree_case_sensitive : @table_case_sensitive
    raw_query = is_tree_mode ? @last_tree_search_query : @last_search_query
    return false if raw_query.to_s.empty?

    regex_mode = is_tree_mode ? !!@tree_regex_mode : !!@table_regex_mode
    ignore_accents = is_tree_mode ? !!@tree_ignore_accents : !!@table_ignore_accents

    regex = if regex_mode
              flags = is_strict ? 0 : Regexp::IGNORECASE
              Regexp.new(raw_query.to_s, flags)
            else
              build_script_insensitive_regex(raw_query, is_strict, ignore_accents)
            end

    safe_replace_str =
      if defined?(@last_replace_text) && @last_replace_text &&
         !@last_replace_text.to_s.strip.empty?
        @last_replace_text.to_s
      else
        ''
      end

    changes_made = false

    replace_field = lambda do |object, field|
      original_text = object.public_send(field).to_s
      normalized_text = original_text.unicode_normalize(:nfd)
      updated_text = normalized_text.gsub(regex, safe_replace_str)
                                    .unicode_normalize(:nfc)

      next if updated_text == original_text

      unless changes_made
        allow_snapshot! if respond_to?(:allow_snapshot!)
        save_history_snapshot if respond_to?(:save_history_snapshot)
      end

      object.public_send("#{field}=", updated_text)
      changes_made = true
    end

    if is_tree_mode
      current_path = @tree_search_matches[@tree_search_current_idx]

      if current_path && current_path.is_a?(Array)
        case current_path.length
        when 1
          obj = @library.subjects.find { |s| s.id.to_s == current_path[0].to_s }
          replace_field.call(obj, :name) if obj
        when 2
          sub = @library.subjects.find { |s| s.id.to_s == current_path[0].to_s }
          obj = sub&.sources&.find { |src| src.id.to_s == current_path[1].to_s }
          replace_field.call(obj, :name) if obj
        when 3
          sub = @library.subjects.find { |s| s.id.to_s == current_path[0].to_s }
          src = sub&.sources&.find { |s| s.id.to_s == current_path[1].to_s }
          obj = src&.decks&.find { |d| d.id.to_s == current_path[2].to_s }
          replace_field.call(obj, :name) if obj
        end

        sort_library_tree_layers! if changes_made && respond_to?(:sort_library_tree_layers!)
      end

      @tree_search_matches.delete_at(@tree_search_current_idx)
    else
      s_idx = @current_subject_idx || 0
      src_idx = @current_source_idx || 0
      d_idx = @current_deck_idx || 0
      target_deck = @library.subjects[s_idx]&.sources&.[](src_idx)&.decks&.[](d_idx)
      cards_list = target_deck ? target_deck.cards : []

      if @search_matches && @search_matches[@search_current_match_idx]
        current_card_idx = @search_matches[@search_current_match_idx]
        card = cards_list[current_card_idx]

        if card
          %i[term context meaning].each do |field|
            replace_field.call(card, field)
          end
        end
      end

      @search_matches.delete_at(@search_current_match_idx)
    end

    @library_dirty = true if changes_made

    if is_tree_mode
      if @tree_search_matches && @tree_search_matches.any?
        @tree_search_current_idx %= @tree_search_matches.length
        next_target_path = @tree_search_matches[@tree_search_current_idx]
        @tree.selected_path = next_target_path

        if @tree.respond_to?(:expanded_paths)
          @tree.expanded_paths ||= []
          (1...next_target_path.length).each do |i|
            slice_path = next_target_path[0...i]
            @tree.expanded_paths << slice_path unless @tree.expanded_paths.include?(slice_path)
          end
        end

        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
        nodes_pool = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []

        if nodes_pool.any? && defined?(@tree_state) && @tree_state
          matched_row = nodes_pool.index { |n| n[:path] == next_target_path }

          unless matched_row
            target_name = next_target_path.last.to_s.downcase
            matched_row = nodes_pool.index do |node|
              node[:name].to_s.downcase == target_name ||
                (node[:object] && node[:object].name.to_s.downcase == target_name)
            end
          end

          jump_to_absolute_tree_search_index(matched_row || 0)
        end
      else
        @tree_search_matches = nil
        @tree_search_current_idx = nil
        @last_replace_text = nil
        @active_focus = :tree
        @last_focus = :tree
        @interactively_replacing = false
      end
    elsif @search_matches && @search_matches.any?
      @search_current_match_idx %= @search_matches.length
      @table_state.select(@search_matches[@search_current_match_idx]) if @table_state
    else
      @search_matches = nil
      @search_current_match_idx = nil
      @last_replace_text = nil
      @active_focus = :table
      @last_focus = :table
      @interactively_replacing = false
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  end

  def handle_interactive_replace_jump_to_top(is_tree_mode)
    @tree_search_current_idx = 0 if is_tree_mode
    @search_current_match_idx = 0 unless is_tree_mode

    @tree.selected_path = @tree_search_matches[@tree_search_current_idx] if is_tree_mode
    @tree.refresh_nodes if is_tree_mode && @tree.respond_to?(:refresh_nodes)

    if is_tree_mode && @tree_state
      matched_idx = @tree.visible_nodes.index { |n| n[:path] == @tree.selected_path } || 0
      # GECORRIGEERD: Spring relatief naar de top
      jump_to_absolute_tree_search_index(matched_idx)
    end
    @table_state.select(@search_matches[@search_current_match_idx]) if !is_tree_mode && @table_state
    true

    # =====================================================================
    # JUMP TO BOTTOM IN REPLACE MODE: G / END
    # =====================================================================
  end

  def handle_interactive_replace_jump_to_bottom(is_tree_mode)
    @tree_search_current_idx = @tree_search_matches.length - 1 if is_tree_mode
    @search_current_match_idx = @search_matches.length - 1 unless is_tree_mode

    @tree.selected_path = @tree_search_matches[@tree_search_current_idx] if is_tree_mode
    @tree.refresh_nodes if is_tree_mode && @tree.respond_to?(:refresh_nodes)

    if is_tree_mode && @tree_state
      matched_idx = @tree.visible_nodes.index { |n| n[:path] == @tree.selected_path } || 0
      # GECORRIGEERD: Spring relatief naar de bodem
      jump_to_absolute_tree_search_index(matched_idx)
    end
    @table_state.select(@search_matches[@search_current_match_idx]) if !is_tree_mode && @table_state
    true

    # =====================================================================
    # FORWARD NAV IN REPLACE MODE: n / down / j
    # =====================================================================
    # =====================================================================
    # FORWARD NAV IN REPLACE MODE: n / down / j (SHIFT NEGEERD IN TREE)
    # =====================================================================
  end

  def handle_interactive_replace_forward(is_tree_mode, has_shift)
    if is_tree_mode
      if @tree_search_matches && @tree_search_matches.any?
        @tree_search_current_idx = (@tree_search_current_idx.to_i + 1) % @tree_search_matches.length
      end
    else
      # 👉 REPARATIE: Harde guard ingebouwd ter voorkoming van NoMethodErrors op nil
      if @search_matches && @search_matches.any?
        @search_current_match_idx = if has_shift
                                      @search_matches.length - 1
                                    else
                                      (@search_current_match_idx.to_i + 1) % @search_matches.length
                                    end
      end
    end

    if is_tree_mode && @tree_search_matches
      @tree.selected_path = @tree_search_matches[@tree_search_current_idx] if @tree
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      if defined?(@tree_state) && @tree_state
        matched_idx = @tree.visible_nodes.index { |n| n[:path] == @tree.selected_path } || 0
        jump_to_absolute_tree_search_index(matched_idx)
      end
    elsif !is_tree_mode && @search_matches && @table_state
      @table_state.select(@search_matches[@search_current_match_idx])
    end

    true
  end

  # =====================================================================
  # BACKWARD NAV IN REPLACE MODE: N / up / k
  # =====================================================================
  def handle_interactive_replace_backward(is_tree_mode, key_str, has_shift)
    if is_tree_mode
      if @tree_search_matches && @tree_search_matches.any?
        @tree_search_current_idx = (@tree_search_current_idx.to_i - 1) % @tree_search_matches.length
      end
    else
      # 👉 REPARATIE: Harde guard ingebouwd ter voorkoming van NoMethodErrors op nil
      if @search_matches && @search_matches.any?
        @search_current_match_idx = if key_str == 'up' && has_shift
                                      0
                                    else
                                      (@search_current_match_idx.to_i - 1) % @search_matches.length
                                    end
      end
    end

    if is_tree_mode && @tree_search_matches
      @tree.selected_path = @tree_search_matches[@tree_search_current_idx] if @tree
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      if defined?(@tree_state) && @tree_state
        matched_idx = @tree.visible_nodes.index { |n| n[:path] == @tree.selected_path } || 0
        jump_to_absolute_tree_search_index(matched_idx)
      end
    elsif !is_tree_mode && @search_matches && @table_state
      @table_state.select(@search_matches[@search_current_match_idx])
    end

    true
  end

  def execute_tree_search(query_text)
    return if query_text.to_s.strip.empty?

    initialize_tree_search(query_text)
    collect_tree_search_matches(query_text)

    if @tree_search_matches.any?
      finalize_tree_search_matches
    else
      @tree_search_matches = nil
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def initialize_tree_search(query_text)
    @tree_search_matches = []
    @tree_search_current_idx = 0
    @last_tree_search_query = query_text.to_s
  end

  def collect_tree_search_matches(query_text)
    is_strict = (@tree_case_sensitive == true)

    query = query_text.to_s.strip
    return if query.empty?

    # Selectieve normalisatie op de zoekopdracht
    ignore_accents = (@tree_ignore_accents == true)
    visual_query = normalize_target_scripts(query, is_strict, ignore_accents)

    nodes_to_search =
      if @tree.respond_to?(:all_nodes)
        @tree.all_nodes
      elsif @tree.respond_to?(:visible_nodes)
        @tree.visible_nodes
      else
        []
      end

    @tree_search_matches = []

    nodes_to_search.each do |node|
      name = node[:name].to_s
      # Selectieve normalisatie op de boom-node namen
      norm_name = normalize_target_scripts(name, is_strict, ignore_accents)

      matched = norm_name.include?(visual_query) &&
                !norm_name.include?(",#{visual_query.delete_suffix(';')}")

      @tree_search_matches << node[:path] if matched
    end
  end

  def finalize_tree_search_matches
    @tree_search_matches.each { |path| expand_tree_search_target(path) }
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    first_match_path = @tree_search_matches.first
    jump_to_absolute_tree_search_index(first_match_path)
  end

  def expand_tree_search_target(path)
    return unless path.is_a?(Array)
    return if @tree.nil?

    # 1. Probeer de officiële framework-ancestor utility aan te roepen mocht die er zijn
    @tree.expand_ancestors(path) if @tree.respond_to?(:expand_ancestors)

    # 2. Manually walk through all parent levels.
    # Bijvoorbeeld bij ['Talen', 'Frans', 'Grammatica'] openen we eerst ['Talen'] en dan ['Talen', 'Frans']
    (1...path.length).each do |depth|
      ancestor_path = path[0...depth]

      # ROUTE A: De tree heeft een directe, native expand-methode
      @tree.expand(ancestor_path) if @tree.respond_to?(:expand)

      # ROUTE B: De tree beheert de statussen via een interne expanded_paths array/set
      if @tree.respond_to?(:expanded_paths) && @tree.expanded_paths
        if @tree.expanded_paths.respond_to?(:add) # Als het een Set is
          @tree.expanded_paths.add(ancestor_path)
        elsif @tree.expanded_paths.is_a?(Array)   # Als het een gewone Array is
          @tree.expanded_paths << ancestor_path unless @tree.expanded_paths.include?(ancestor_path)
        end
      end

      # ROUTE C: Extra vangnet via eventuele globale app expanded_paths cache
      if defined?(@tree_state) && @tree_state && @tree_state.respond_to?(:expanded_paths) && @tree_state.expanded_paths.is_a?(Array) && !@tree_state.expanded_paths.include?(ancestor_path)
        @tree_state.expanded_paths << ancestor_path
      end
    end

    # 3. Dwing de model-nodes direct tot een algehele herberekening van de zichtbare rijen!
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  private

  def jump_to_absolute_tree_search_index(target)
    return if target.nil?

    prepare_absolute_tree_search_target(target)
    visible_nodes = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
    return if visible_nodes.empty?

    target_index = absolute_tree_search_target_index(target, visible_nodes)
    return if target_index.nil?

    position_absolute_tree_search_target(target_index, visible_nodes)
  end

  def prepare_absolute_tree_search_target(target)
    return unless target.is_a?(Array)

    if defined?(@tree_search_matches) && @tree_search_matches
      idx = @tree_search_matches.index { |path| path == target }
      @tree_search_current_idx = idx unless idx.nil?
    end
    expand_tree_search_target(target)
  end

  def absolute_tree_search_target_index(target, visible_nodes)
    if target.is_a?(Array)
      visible_nodes.index { |node| node[:path] == target }
    else
      target.to_i
    end
  end

  def position_absolute_tree_search_target(target_index, visible_nodes)
    page_size = [(@tree_visible_height || 1).to_i, 1].max
    max_offset = [visible_nodes.length - page_size, 0].max
    current_offset = if defined?(@tree_page_viewport_start) && !@tree_page_viewport_start.nil?
                       @tree_page_viewport_start.to_i
                     elsif @tree_state&.respond_to?(:offset)
                       @tree_state.offset.to_i
                     else
                       0
                     end

    # Search/replace navigatie met gewone up/down-toetsen mag de view niet
    # jump to a completely new page on every update. Keep the
    # existing viewport as long as the target remains visible, and scroll only
    # zover als nodig om het doel in beeld te brengen.
    target_offset = if target_index < current_offset
                      target_index
                    elsif target_index >= current_offset + page_size
                      target_index - page_size + 1
                    else
                      current_offset
                    end
    target_offset = [[target_offset, 0].max, max_offset].min

    @tree_state.select(target_index) if defined?(@tree_state) && @tree_state
    set_tree_page_offset(target_offset)
    @tree_page_viewport_start = target_offset
    @search_page_viewport_start = target_offset
    @tree.selected_path = visible_nodes[target_index][:path]
    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
  end

  def perform_global_search(query_text, case_sensitive: false, regex_mode: false, ignore_accents: false)
    @global_search_active = true
    @global_search_query = query_text.to_s.strip
    @global_search_matches = []
    @global_search_matched_deck_ids = []
    @global_search_current_idx = 0

    # Normaliseer de query selectief
    search_regex = if regex_mode
                     Regexp.new(
                       query_text.to_s,
                       case_sensitive ? 0 : Regexp::IGNORECASE
                     )
                   else
                     build_script_insensitive_regex(
                       query_text,
                       case_sensitive,
                       ignore_accents
                     )
                   end

    # We scannen uitsluitend alle flitskaarten over alle decks heen
    @library.subjects.each_with_index do |sub, sub_i|
      sub.sources.each_with_index do |src, src_i|
        src.decks.each_with_index do |deck, deck_i|
          deck_has_match = false

          # Binnen de lus van perform_global_search:
          Array(deck.cards).each_with_index do |card, card_i|
            # Zet de velden om naar NFD voor de regex-check
            nfd_term    = card.term.to_s.unicode_normalize(:nfd)
            nfd_context = card.context.to_s.unicode_normalize(:nfd)
            nfd_meaning = card.meaning.to_s.unicode_normalize(:nfd)

            next unless nfd_term =~ search_regex ||
                        nfd_context =~ search_regex ||
                        nfd_meaning =~ search_regex

            @global_search_matches << {
              subject_idx: sub_i, source_idx: src_i, deck_idx: deck_i, card_idx: card_i,
              deck_id: deck.id.to_s, card_obj: card
            }
            deck_has_match = true
          end

          # Sterretje in de kantlijn van de Tree als het deck kaartmatches bevat!
          @global_search_matched_deck_ids << [sub.id.to_s, src.id.to_s, deck.id.to_s].to_s if deck_has_match
        end
      end
    end

    if @global_search_matches.any?
      jump_to_global_search_match(0)
    else
      trigger_statusbar_message(
        "#{AppConfig.settings.language_string(:statusbar_search_error)}: #{AppConfig.settings.language_string(:statusbar_no_results_found)}!"
      )
      @global_search_active = false
    end
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  # =========================================================================
  # 🔗 MULTI-COMPONENT COORDINATOR
  # 👉 Synchronizes Table rows and shifts the Tree sidebar cursor to follow decks!
  # =========================================================================
  def jump_to_global_search_match(match_index)
    return if @global_search_matches.nil? || @global_search_matches.empty?

    # Oneindige wiskundige modulo wrap-around loop over alle kaarten!
    @global_search_current_idx = match_index % @global_search_matches.length
    match = @global_search_matches[@global_search_current_idx]

    # 🚨 GUARANTEE: Keep focus in the table and leave the tree dimmed.
    @active_focus = :table
    @last_focus   = :table

    @current_subject_idx = match[:subject_idx]
    @current_source_idx  = match[:source_idx]
    @current_deck_idx    = match[:deck_idx]

    # Laad de kaarten van dit deck direct in de actieve tabel-cache
    sub_obj = @library.subjects[@current_subject_idx]
    src_obj = sub_obj&.sources&.[](@current_source_idx)
    deck_obj = src_obj&.decks&.[](@current_deck_idx)
    @active_cards = deck_obj ? deck_obj.cards : []

    # Smeed de lokale @search_matches highlight-cache live om voor dit specifieke deck
    current_deck_id = match[:deck_id]
    @search_matches = @global_search_matches.select do |m|
      m[:deck_id] == current_deck_id
    end.map { |m| m[:card_idx] }.uniq.sort
    @search_current_match_idx = @search_matches.index(match[:card_idx]) || 0
    @last_search_query = @global_search_query

    # Selecteer de rij in de tabel state
    if defined?(@table_state) && @table_state
      @table_state.select(match[:card_idx])
      @current_card_idx = match[:card_idx]
    end

    # 🌲 SYNC THE TREE CURSOR (Op de achtergrond!)
    return unless sub_obj && src_obj && deck_obj

    target_path = [sub_obj.id.to_s, src_obj.id.to_s, deck_obj.id.to_s]
    @tree.selected_path = target_path

    expand_tree_search_target(target_path) if respond_to?(:expand_tree_search_target)
    return unless @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && @tree_state

    row_idx = @tree.visible_nodes.index { |node| node[:path] == target_path }
    @tree_state.select(row_idx) if row_idx
  end
end
