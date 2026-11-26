class RatatuiRubyApp
  # =========================================================================
  # HELPER: BUILD INDIVIDUAL TREE ROWS WITH RIGHT-SIDE HIGHLIGHTING
  # =========================================================================
  def build_tree_spans(node, is_selected, is_tree_visually_active, panel_width = nil)
    @selected_tree_paths ||= []

    prefix_string = build_tree_prefix_string(node)
    is_node_marked = @selected_tree_paths.include?(node[:path])
    effective_panel_width = panel_width ? [panel_width.to_i, 1].max : 30

    base_style = build_tree_base_style(
      is_selected,
      is_tree_visually_active
    )

    # Meet de prefix in echte terminalcellen.
    direction_marks = /[\u200E\u200F\u202A-\u202E\u2066-\u2069]/

    clean_prefix = prefix_string.gsub(direction_marks, '')
    prefix_width = Unicode::DisplayWidth.of(clean_prefix)

    rtl_name = tree_text_rtl?(node[:name])

    # Reserveer één cel tussen de naam en de rechterrand.
    name_indent = prefix_width + 1

    @tree_highlight_original_name = node[:name].to_s

    name_string = truncate_node_name(
      node[:name],
      name_indent,
      effective_panel_width
    )

    highlight_style = build_tree_highlight_style(base_style)

    prefix_spans = build_tree_prefix_spans(
      node,
      is_selected,
      is_tree_visually_active,
      is_node_marked,
      base_style
    )

    name_spans, visual_name_string = build_tree_name_spans(
      name_string,
      base_style,
      highlight_style,
      is_selected
    )

    # Bereken ook de naam in terminalcellen, niet in graphemes.
    clean_visual_name = visual_name_string.gsub(direction_marks, '')
    name_width = Unicode::DisplayWidth.of(clean_visual_name)

    remaining_spaces = [
      effective_panel_width - prefix_width - name_width,
      0
    ].max

    if rtl_name
      # RTL: verdeel de vrije ruimte vóór de naam en na de naam.
      # Always reserve one cell on the right.
      if remaining_spaces.positive?
        left_padding = remaining_spaces - 1

        if left_padding.positive?
          name_spans.unshift(
            RatatuiRuby::Text::Span.new(
              content: "\u00A0" * left_padding,
              style: base_style
            )
          )
        end

        name_spans << RatatuiRuby::Text::Span.new(
          content: "\u00A0",
          style: base_style
        )
      end
    elsif remaining_spaces.positive?
      # LTR: preserve the existing left-aligned name.
      name_spans << RatatuiRuby::Text::Span.new(
        content: "\u00A0" * remaining_spaces,
        style: base_style
      )
    end

    # Build the row with the existing padding first.
    all_spans = prefix_spans + name_spans
    tree_line = RatatuiRuby::Text::Line.new(spans: all_spans)

    if rtl_name
      # Gebruik dezelfde breedtemeting als de tree-renderer.
      measured_width = tree_line.width.to_i
      missing_width = [
        effective_panel_width - measured_width,
        0
      ].max

      if missing_width.positive?
        # Corrigeer alleen de ruimte vóór de RTL-naam.
        # Preserve the prefix, icons, and existing right margin.
        correction_span = RatatuiRuby::Text::Span.new(
          content: "\u00A0" * missing_width,
          style: base_style
        )

        tree_line = RatatuiRuby::Text::Line.new(
          spans: prefix_spans + [correction_span] + name_spans
        )
      end
    end

    tree_line
  end

  private

  def tree_text_rtl?(text)
    first_letter = text.to_s.each_char.find do |char|
      char.match?(/\p{L}/)
    end

    return false unless first_letter

    first_letter.match?(/\p{Hebrew}/) ||
      first_letter.match?(/\p{Arabic}/)
  end

  def truncate_node_name(name, current_indent, panel_width)
    name_str = name.to_s
    max_width = panel_width - current_indent

    @tree_visible_layout = []
    @tree_visible_prefix_text = ''
    @tree_visible_suffix_text = ''

    return '' if max_width <= 0

    tmp_field = RatinField.new
    tmp_field.text = name_str
    layout = tmp_field.visual_layout
    visual_text = layout.map { |item| item[:char] }.join

    if Unicode::DisplayWidth.of(visual_text) <= max_width
      @tree_visible_layout = layout
      return "\u2066#{visual_text}\u2069"
    end

    is_rtl = tree_text_rtl?(name_str)
    target_space = [max_width - 1, 0].max
    clusters = layout

    query = defined?(@last_tree_search_query) ? @last_tree_search_query.to_s : ''
    search_active = !query.strip.empty? &&
                    defined?(@tree_search_matches) &&
                    @tree_search_matches &&
                    !@tree_search_matches.empty?

    match_positions = []

    if search_active
      strict = defined?(@tree_case_sensitive) &&
               (@tree_case_sensitive == true ||
                @tree_case_sensitive.to_s.strip.downcase == 'true')

      begin
        regex = Regexp.new(
          Regexp.escape(query),
          strict ? 0 : Regexp::IGNORECASE
        )

        name_str.to_enum(:scan, regex).each do
          match = Regexp.last_match
          start_cp = name_str[0...match.begin(0)].to_s.codepoints.length
          end_cp = start_cp + match[0].codepoints.length

          clusters.each_with_index do |item, index|
            indices = item[:logical_indices] || []
            match_positions << index if indices.any? { |cp| cp >= start_cp && cp < end_cp }
          end

          break unless match_positions.empty?
        end
      rescue RegexpError
        match_positions = []
      end
    end

    retained_layout = []
    prefix_text = ''
    suffix_text = ''

    unless match_positions.empty? || target_space <= 0
      left = match_positions.min
      right = match_positions.max

      match_width = clusters[left..right].sum do |item|
        Unicode::DisplayWidth.of(item[:char])
      end

      if match_width <= target_space
        budget = target_space
        current_width = match_width
        expand_left = true

        while true
          left_width = if left.positive?
                         Unicode::DisplayWidth.of(clusters[left - 1][:char])
                       else
                         Float::INFINITY
                       end

          right_width = if right < clusters.length - 1
                          Unicode::DisplayWidth.of(clusters[right + 1][:char])
                        else
                          Float::INFINITY
                        end

          break if !left_width.finite? && !right_width.finite?

          added = false

          if expand_left
            if left_width.finite? && current_width + left_width <= budget
              left -= 1
              current_width += left_width
              added = true
            elsif right_width.finite? && current_width + right_width <= budget
              right += 1
              current_width += right_width
              added = true
            end
          elsif right_width.finite? && current_width + right_width <= budget
            right += 1
            current_width += right_width
            added = true
          elsif left_width.finite? && current_width + left_width <= budget
            left -= 1
            current_width += left_width
            added = true
          end

          break unless added

          expand_left = !expand_left
        end

        retained_layout = clusters[left..right]
        prefix_text = left.positive? ? '…' : ''
        suffix_text = right < clusters.length - 1 ? '…' : ''
      end
    end

    if retained_layout.empty?
      current_width = 0

      if is_rtl
        clusters.reverse_each do |item|
          width = Unicode::DisplayWidth.of(item[:char])
          break if current_width + width > target_space

          retained_layout.unshift(item)
          current_width += width
        end

        prefix_text = ' ' * (target_space - current_width) + '…'
      else
        clusters.each do |item|
          width = Unicode::DisplayWidth.of(item[:char])
          break if current_width + width > target_space

          retained_layout << item
          current_width += width
        end

        suffix_text = ' ' * (target_space - current_width) + '…'
      end
    end

    @tree_visible_layout = retained_layout
    @tree_visible_prefix_text = prefix_text
    @tree_visible_suffix_text = suffix_text

    visible_text = prefix_text +
                   retained_layout.map { |item| item[:char] }.join +
                   suffix_text

    "\u2066#{visible_text}\u2069"
  end

  def build_tree_prefix_string(node)
    is_global_match = defined?(@global_search_active) && @global_search_active &&
                      node[:type] == :deck &&
                      defined?(@global_search_matched_deck_ids) &&
                      @global_search_matched_deck_ids.include?(node[:path].to_s)

    mark_indicator = if is_global_match
                       '*'
                     else
                       @selected_tree_paths.include?(node[:path]) ? '▍' : ' '
                     end

    indentation = ' ' * node[:depth]
    indentation += ' ' if node[:type] == :source
    indentation += '  ' if node[:type] == :deck
    icon = build_tree_icon(node)

    # 🎯 FIX: Geen rondslingerende \u200E marker meer aan het einde,
    # name isolation handles the bidi boundary from this point onward.
    "\u00A0#{mark_indicator}#{indentation}#{icon}"
  end

  def build_tree_icon(node)
    case node[:type]
    when :subject then @tree.expanded_paths.include?(node[:path]) ? '▼ ' : '▶ '
    when :source  then @tree.expanded_paths.include?(node[:path]) ? '▽ ' : '▷ '
    when :deck    then '■ '
    else ''
    end
  end

  def build_tree_base_style(is_selected, is_tree_visually_active)
    settings = AppConfig.settings

    fg = settings.theme_item(:selected_row_foreground)
    bg = settings.theme_item(:selected_row_background)
    background = settings.theme_item(:background)
    foreground = settings.theme_item(:foreground)

    has_active_error_alert =
      defined?(@status_message) && !@status_message.nil?

    popup_is_active =
      (defined?(@popup) && @popup &&
        @popup.respond_to?(:active?) && @popup.active?) ||
      (defined?(@active_focus) && @active_focus.to_s == 'popup')

    is_tree_focused =
      !has_active_error_alert &&
      !popup_is_active &&
      (
        is_tree_visually_active ||
        @active_focus == :tree ||
        (@active_focus == :replace_mode && @last_focus == :tree)
      )

    active_popup_type = begin
      @popup.active_popup[:type].to_sym
    rescue StandardError
      nil
    end

    is_overlay_active =
      has_active_error_alert ||
      popup_is_active ||
      %i[popup menu command_mode].include?(@active_focus) ||
      %i[help about form].include?(active_popup_type)

    came_from_tree =
      (defined?(@focus_before_help) && @focus_before_help == :tree) ||
      (defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor == :tree) ||
      (defined?(@last_focus) && @last_focus == :tree)

    came_from_table =
      (defined?(@focus_before_help) && @focus_before_help == :table) ||
      (defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor == :table) ||
      (defined?(@menu_origin_focus) && @menu_origin_focus == :table) ||
      (defined?(@last_focus) && @last_focus == :table)

    return { fg: foreground, bg: background, modifiers: [:dim] } if is_overlay_active && came_from_table

    if is_overlay_active && came_from_tree
      return is_selected ? { fg: fg, bg: bg, modifiers: [:dim] } : { fg: foreground, bg: background, modifiers: [:dim] }
    end

    if is_tree_focused
      return is_selected ? { fg: fg, bg: bg } : { fg: foreground, bg: background }
    end

    { fg: foreground, bg: background, modifiers: [:dim] }
  end

  def build_tree_highlight_style(base_style)
    settings = AppConfig.settings

    {
      fg: settings.theme_item(:background),
      bg: settings.theme_item(:search_results_background),
      modifiers: []
    }
  end

  def build_tree_prefix_span(prefix_string, base_style, is_selected, is_tree_visually_active)
    prefix_style = base_style.dup
    settings = AppConfig.settings

    unless is_selected
      if is_tree_visually_active
        # 🌟 VENSTER IS ACTIEF: Alle tekens en verbindingslijnen branden
        # always use the bright cyberpunk accent color.
        prefix_style[:fg] = settings.theme_item(:tree_symbol)
        prefix_style[:modifiers] = []
      else
        # 💤 VENSTER IS INACTIEF: Zodra je de Tree verlaat, dimmen alle
        # tekens direct viltstrak mee naar de achtergrond-stand!
        prefix_style[:fg] = settings.theme_item(:tree_symbol)
        prefix_style[:modifiers] = [:dim]
      end
    end

    RatatuiRuby::Text::Span.new(content: prefix_string, style: prefix_style)
  end

  def build_tree_prefix_spans(node, is_selected, is_tree_visually_active, is_node_marked, row_style)
    settings = AppConfig.settings
    row_style ||= build_tree_base_style(is_selected, is_tree_visually_active)
    row_bg = row_style[:bg] || settings.theme_item(:background)
    spans = []

    is_global_match = defined?(@global_search_active) && @global_search_active &&
                      node[:type] == :deck &&
                      defined?(@global_search_matched_deck_ids) &&
                      @global_search_matched_deck_ids.include?(node[:path].to_s)

    # Left padding preserves the row background, including under the cursor.
    spans << build_tree_prefix_span(
      "\u00A0", row_style, is_selected, is_tree_visually_active
    )

    spans << if is_global_match
               # 🎯 THE DIM CONDITIONAL DISPATCHER:
               # Setup base styling colors for your system-wide lookup indicators
               asterisk_style = {
                 fg: settings.theme_item(is_selected ? :selected_row_foreground : :window_shortcut_section),
                 bg: row_bg,
                 modifiers: []
               }

               # Append structural modifiers dynamically based on structural visibility states
               asterisk_style = {
                 fg: settings.theme_item(is_selected ? :selected_row_foreground : :window_shortcut_section),
                 bg: row_bg,
                 modifiers: is_tree_visually_active ? [] : [:dim]
               }

               RatatuiRuby::Text::Span.new(content: '*', style: asterisk_style)
             elsif is_node_marked
               indicator_style = {
                 fg: settings.theme_item(
                   is_selected ? :selected_row_foreground : :selected_row_background
                 ),
                 bg: row_bg
               }
               indicator_style[:modifiers] = [:dim] unless is_selected

               RatatuiRuby::Text::Span.new(content: '▍', style: indicator_style)
             else
               build_tree_prefix_span(' ', row_style, is_selected, is_tree_visually_active)
             end

    indentation = ' ' * node[:depth]
    indentation += ' ' if node[:type] == :source
    indentation += '  ' if node[:type] == :deck
    icon = build_tree_icon(node)

    spans << build_tree_prefix_span(
      "#{indentation}#{icon}\u200E",
      row_style,
      is_selected,
      is_tree_visually_active
    )

    spans
  end

  def build_tree_name_spans(name_string, base_style, highlight_style, is_selected = false)
    clean_name = name_string.gsub(/[\u2066\u2069]/, '')

    # Zoekposities komen uit de oorspronkelijke logische tekst.
    original_name = @tree_highlight_original_name.to_s
    highlight_map = build_tree_highlight_map(clean_name, original_name)

    active_lang = AppConfig.settings.language
    is_handwritten = AppConfig.settings.handwritten?(active_lang)

    name_spans = build_tree_visual_name_spans(
      clean_name,
      highlight_map,
      base_style,
      highlight_style,
      is_selected,
      is_handwritten
    )

    protected_spans = [
      RatatuiRuby::Text::Span.new(content: "\u2066", style: base_style)
    ] + name_spans + [
      RatatuiRuby::Text::Span.new(content: "\u2069", style: base_style)
    ]

    [protected_spans, clean_name]
  end

  def build_tree_highlight_map(visual_name_string, original_name = nil)
    highlight_map = Array.new(visual_name_string.length, false)

    query = defined?(@last_tree_search_query) ? @last_tree_search_query.to_s : ''
    active = !query.strip.empty? &&
             defined?(@tree_search_matches) &&
             @tree_search_matches &&
             !@tree_search_matches.empty?

    return highlight_map unless active

    strict = defined?(@tree_case_sensitive) &&
             (@tree_case_sensitive == true ||
              @tree_case_sensitive.to_s.strip.downcase == 'true')

    folding = defined?(@tree_folding) && @tree_folding == true
    regex_mode = defined?(@tree_regex_mode) && @tree_regex_mode == true

    begin
      regex = if regex_mode
                flags = strict ? 0 : Regexp::IGNORECASE
                Regexp.new(query, flags)
              else
                build_script_insensitive_regex(query, strict, folding)
              end
    rescue RegexpError
      return highlight_map
    end

    raw = (original_name || visual_name_string).to_s
    matched_indices = {}

    if regex_mode
      raw.to_enum(:scan, regex).each do
        match = Regexp.last_match
        start_cp = raw[0...match.begin(0)].to_s.codepoints.length
        end_cp = start_cp + match[0].codepoints.length
        (start_cp...end_cp).each { |index| matched_indices[index] = true }
      end
    else
      nfd_chars = []
      nfd_to_raw = []

      raw.each_char.with_index do |char, raw_index|
        char.unicode_normalize(:nfd).each_char do |nfd_char|
          nfd_chars << nfd_char
          nfd_to_raw << raw_index
        end
      end

      nfd_text = nfd_chars.join

      nfd_text.to_enum(:scan, regex).each do
        match = Regexp.last_match
        (match.begin(0)...match.end(0)).each do |nfd_index|
          raw_index = nfd_to_raw[nfd_index]
          matched_indices[raw_index] = true if raw_index
        end
      end
    end

    return highlight_map if matched_indices.empty?

    visible_layout = @tree_visible_layout || []
    prefix_text = @tree_visible_prefix_text.to_s
    suffix_text = @tree_visible_suffix_text.to_s

    # Keep the prefix, such as an ellipsis or padding spaces, unhighlighted.
    offset = prefix_text.length

    visible_layout.each do |item|
      cluster = item[:char].to_s

      indices = item[:logical_indices] ||
                (item[:logical_index]...item[:logical_end]).to_a

      matched = indices.any? { |index| matched_indices[index] }

      cluster.length.times do |i|
        highlight_map[offset + i] = matched
      end

      offset += cluster.length
    end

    # Keep the suffix, such as an ellipsis, unhighlighted.
    offset += suffix_text.length

    highlight_map
  end

  def build_tree_visual_name_spans(visual_name_string, highlight_map, base_style, highlight_style, is_selected = false,
                                   is_handwritten = false)
    return [] if visual_name_string.empty?

    spans = []
    segment = +''
    highlighted = nil

    # 🎯 STEP 2: FINE-GRAINED CHARACTER CHARACTER CLASSIFICATION
    # To prevent numbers and western structural keywords from tilting across ANY language,
    # we break the text string into clean structural character segments.
    is_latin_or_common = lambda do |char|
      char =~ /\A[\p{Latin}0-9\s[:punct:]]\z/
    end

    visual_name_string.chars.each_with_index do |char, idx|
      current_highlight = highlight_map[idx]

      # Group the text segments by combining highlight status AND character script type
      char_type_changed = !segment.empty? && (is_latin_or_common.call(segment[-1]) != is_latin_or_common.call(char))

      if highlighted.nil?
        highlighted = current_highlight
        segment << char
      elsif highlighted == current_highlight && !char_type_changed
        segment << char
      else
        # Process the accumulated segment cluster string cleanly
        apply_hw = is_handwritten && !is_latin_or_common.call(segment[-1])
        spans << build_tree_name_span(segment, highlighted, base_style, highlight_style, is_selected, apply_hw)

        segment = +'' << char
        highlighted = current_highlight
      end
    end

    unless segment.empty?
      apply_hw = is_handwritten && !is_latin_or_common.call(segment[-1])
      spans << build_tree_name_span(segment, highlighted, base_style, highlight_style, is_selected, apply_hw)
    end
    spans
  end

  def build_tree_name_span(content, highlighted, base_style, highlight_style, is_selected = false,
                           apply_italic = false)
    settings = AppConfig.settings

    # Prepare standard styles using our verified universal script-gate boolean
    final_base = base_style.dup
    final_base[:modifiers] = Array(final_base[:modifiers]) | [:italic] if apply_italic

    final_highlight = highlight_style.dup
    final_highlight[:modifiers] = Array(final_highlight[:modifiers]) | [:italic] if apply_italic

    if highlighted && is_selected
      begin
        theme_fg = settings.theme_item(:background)
        theme_bg = settings.theme_item(:search_results_background)

        custom_combination_style = {
          fg: theme_fg,
          bg: theme_bg,
          modifiers: [:underlined]
        }
        custom_combination_style[:modifiers] << :italic if apply_italic

        return RatatuiRuby::Text::Span.new(content: content, style: custom_combination_style)
      rescue StandardError
        nil
      end
    end

    RatatuiRuby::Text::Span.new(content: content, style: highlighted ? final_highlight : final_base)
  end

  def append_tree_name_padding(name_spans, visual_name_string, prefix_string, panel_width, base_style)
    total_content_length = prefix_string.gsub(/[\u200E\u00A0]/, '').length + 1 + visual_name_string.length
    remaining_spaces = [panel_width - total_content_length, 0].max
    return unless remaining_spaces > 0

    name_spans << RatatuiRuby::Text::Span.new(
      content: "\u200E" + ("\u00A0" * remaining_spaces),
      style: base_style
    )
  end

  public

  # =========================================================================
  # RTL FIX: Sorteert lagen alfabetisch, rekening houdend met Unicode (RTL) structuren
  # =========================================================================
  def sort_library_tree_layers!
    return unless @library && @library.subjects

    # =========================================================================
    # 🎯 NATUURLIJKE EN UNICODE-GENORMALISEERDE SORTEER-SLEUTEL (NIEUW)
    # 👉 Splitst de namen op in letters en cijferreeksen.
    # Convert numbers to integers; normalize letters to NFC and lowercase them.
    # Dit lost de '1, 10, 2' sorteerfout voor de volle 100% numeriek op!
    # =========================================================================
    natural_sort_key = lambda do |name_str|
      name_str.to_s.scan(/[^\d]+|\d+/).map do |chunk|
        chunk =~ /\d+/ ? chunk.to_i : chunk.to_s.unicode_normalize(:nfc).downcase
      end
    end

    # 1. Sorteer de parent Subjects
    @library.subjects.sort_by! { |sub| natural_sort_key.call(sub.name) }

    @library.subjects.each do |sub|
      next unless sub.sources

      # 2. Sorteer Sources binnen elk Subject
      sub.sources.sort_by! { |src| natural_sort_key.call(src.name) }

      sub.sources.each do |src|
        next unless src.decks

        # 3. Sort decks within each source (Imported 2 now correctly comes before Imported 10).
        src.decks.sort_by! { |deck| natural_sort_key.call(deck.name) }
      end
    end

    # Ververs de boomstructuur cache direct voor directe TUI-weergave
    @tree.refresh_nodes if defined?(@tree) && @tree&.respond_to?(:refresh_nodes)
  end

  # =========================================================================
  # CORE VIEW ROUTER: DRAW MIDDLE LEFT REGION (LIBRARY TREE) WITH BORDER FIX
  # =========================================================================
  def draw_middle_left_region(tui, frame, region)
    nodes = @tree.visible_nodes
    list_items = []

    panel_width = region.respond_to?(:width) ? region.width : region.area.width

    popup_is_displayed = (defined?(@active_focus) && @active_focus.to_s == 'popup') ||
                         (defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?)

    # The sidebar has focus only when :tree is selected and no popup is open.
    is_statusbar_search = defined?(@search_replace_origin_mode) && @search_replace_origin_mode == :command_mode

    is_tree_visually_active = (@active_focus == :tree || (@active_focus == :replace_mode && @last_focus == :tree)) &&
                              !popup_is_displayed && !is_statusbar_search

    # 1. Iterate through all visible folders and decks using the stable build_tree_spans.
    nodes.each_with_index do |node, index|
      current_cursor_row = defined?(@tree_state) && @tree_state ? @tree_state.selected : 0

      # De Tree-cursor is alleen zichtbaar wanneer de Tree daadwerkelijk focus heeft.
      # Bij F10 blijft de selectiepositie behouden, maar verdwijnt de highlight.

      hide_tree_cursor = %i[menu popup].include?(@active_focus) || popup_is_displayed
      is_selected = !hide_tree_cursor && (index == current_cursor_row)

      line = build_tree_spans(
        node,
        is_selected,
        is_tree_visually_active,
        panel_width - 2
      )

      list_items << RatatuiRuby::Widgets::ListItem.new(content: line)
    end

    settings = AppConfig.settings

    bg_color = settings.theme_item(:background)

    # =========================================================================
    # STEP 1: DRAW A FULLY ISOLATED WINDOW BORDER (THE OUTER BLOCK)
    # =========================================================================
    # Dit blok tekent puur de buitenlijnen. Omdat hier GEEN bidi-tekst in staat,
    # so the terminal can never reorder these borders or pull them to the right.

    popup_from_menu = defined?(@active_focus) && @active_focus == :popup &&
                      defined?(@menu_origin_focus) && !@menu_origin_focus.nil?

    border_style = if popup_from_menu
                     { fg: settings.theme_item(:foreground), modifiers: [:dim] }
                   elsif is_tree_visually_active
                     { fg: settings.theme_item(:window_border) }
                   else
                     { fg: settings.theme_item(:foreground), modifiers: [:dim] }
                   end

    tree_block = tui.block(
      title: nil,
      title_style: { fg: settings.theme_item(is_tree_visually_active && !popup_from_menu ? :window_title : :foreground),
                     modifiers: popup_from_menu ? [:dim] : [] },
      border_style: border_style,
      style: { bg: settings.theme_item(:background) },
      borders: [:all],
      border_type: settings.corner
    )
    frame.render_widget(tree_block, region)

    # Calculate the exact region on top of the upper border (y = region.y).
    title_area = RatatuiRuby::Layout::Rect.new(
      region.x + 2,
      region.y,
      [region.width - 4, 1].max,
      1
    )

    # =========================================================================
    # 🎨 STAP 3: REAL-TIME REVERSED ACCENT PIPELINE
    # - Focus is in :menu or :table -> Always highlight the brackets brightly. [14]
    # - Focus is in the tree itself -> Show the brackets in plain white foreground.
    # =========================================================================
    accent_style = if %w[menu table].include?(@active_focus.to_s)
                     tui.style(fg: settings.theme_item(:window_shortcut_section), modifiers: [:bold])
                   else
                     # 🚨 Ruststand
                     tui.style(fg: settings.theme_item(:window_shortcut_section), modifiers: [:bold])
                   end

    # Het hoofdwoord "Library" dimt mee zodra de haken oplichten
    text_style = if popup_from_menu || %w[menu table].include?(@active_focus.to_s)
                   tui.style(fg: settings.theme_item(:window_title), modifiers: [:dim])
                 else
                   tui.style(fg: settings.theme_item(:window_title))
                 end

    # Smeed de spans handmatig samen tot de definitieve titellijn
    label, key = AppConfig.settings.language_string(:tree_title).split(/\s+/, 2)

    title_spans = [
      tui.span(" #{label} ", text_style), # Fel gekleurd bij Menu/Table, helder wit bij de rest!
      tui.span("#{key} ", accent_style)
    ]

    # We renderen de spans als een Paragraph widget. Dit omzeilt de focus-gijzeling van Ratatui compleet! [14]
    formatted_tree_title = RatatuiRuby::Text::Line.new(spans: title_spans)
    frame.render_widget(RatatuiRuby::Widgets::Paragraph.new(text: formatted_tree_title, alignment: :left), title_area)

    # =========================================================================
    # STAP 2: BEREKEN EEN IMMUTABLE BINNENREGIO (INNER AREA FIX)
    # =========================================================================
    # Haal de basiscoördinaten op uit de binnenkomende regio (of regio.area)
    orig_rect = region.respond_to?(:area) && region.area.is_a?(RatatuiRuby::Layout::Rect) ? region.area : region

    # Maak een gloednieuw onveranderlijk Rect-object aan met gecorrigeerde marges.
    # Offset x and y by one cell, and reduce the width and height by two cells.
    inner_region = RatatuiRuby::Layout::Rect.new(
      [orig_rect.x + 1, 0].max,
      [orig_rect.y + 1, 0].max,
      [orig_rect.width - 2, 1].max,
      [orig_rect.height - 2, 1].max
    )

    # =========================================================================
    # STEP 3: RENDER THE LIST WIDGET INSIDE THE BORDER (WITHOUT ITS OWN BORDERS)
    # =========================================================================
    tree_widget = tui.list(
      items: list_items,
      highlight_symbol: '',
      # We laten het list-widget GEEN eigen block/borders tekenen.
      # De lijst leeft nu 100% veilig in zijn eigen geïsoleerde binnenwereld.
      style: tui.style(bg: bg_color)
    )

    # Tijdens Search/Replace mag Ratatui de ListState-viewport NIET zelf
    # bepalen. Een stateful List rendert anders automatisch naar de selectie
    # which could still scroll a deliberately preserved cursor row above or below
    # eindigen. Render daarom exact de gewenste pagina als een gewone List.
    is_tree_search_active = @tree_search_matches && @tree_search_matches.any? &&
                            (@active_focus == :tree ||
                             (@active_focus == :replace_mode && @last_focus == :tree))

    tree_viewport_render_lock = if defined?(@tree_viewport_render_lock) && !@tree_viewport_render_lock.nil?
                                  @tree_viewport_render_lock.to_i
                                end

    is_tree_page_navigation_active = defined?(@tree_page_navigation_active) && @tree_page_navigation_active

    if is_tree_search_active || is_tree_page_navigation_active || !tree_viewport_render_lock.nil?
      visible_height = [inner_region.height.to_i, 1].max
      max_offset = [list_items.length - visible_height, 0].max

      retained_cursor_row = if defined?(@tree_search_last_target_index) &&
                               @tree_search_last_target_index.to_i == @tree_state.selected.to_i &&
                               defined?(@tree_search_cursor_row) && !@tree_search_cursor_row.nil?
                              @tree_search_cursor_row.to_i
                            end

      viewport_start = if !tree_viewport_render_lock.nil?
                         tree_viewport_render_lock
                       elsif retained_cursor_row
                         @tree_state.selected.to_i - retained_cursor_row
                       elsif defined?(@search_page_viewport_start) && !@search_page_viewport_start.nil?
                         @search_page_viewport_start.to_i
                       elsif defined?(@tree_page_viewport_start) && !@tree_page_viewport_start.nil?
                         @tree_page_viewport_start.to_i
                       elsif @tree_state&.respond_to?(:offset)
                         @tree_state.offset.to_i
                       else
                         0
                       end

      viewport_start = [[viewport_start, 0].max, max_offset].min
      visible_items = list_items[viewport_start, visible_height] || []

      search_tree_widget = tui.list(
        items: visible_items,
        highlight_symbol: '',
        style: tui.style(bg: bg_color)
      )
      frame.render_widget(search_tree_widget, inner_region)
      @tree_page_viewport_start = viewport_start
      @search_page_viewport_start = nil
      @tree_viewport_render_lock = nil unless tree_viewport_render_lock.nil?
    else
      frame.render_stateful_widget(tree_widget, inner_region, @tree_state)
    end

    # =========================================================================
    # SCROLLBAR LAYOUT (stays flush against the right edge)
    # =========================================================================
    usable_height = region.respond_to?(:height) ? region.height : region.area.height
    content_height = usable_height - 2
    @tree_visible_height = [content_height, 1].max

    return unless nodes.length > content_height

    scrollbar_style =
      if @active_focus == :tree
        {
          fg: settings.theme_item(:window_border)
        }
      else
        {
          fg: settings.theme_item(:foreground),
          modifiers: [:dim]
        }
      end

    scrollbar_widget = tui.scrollbar(
      content_length: nodes.length,
      position: (defined?(@tree_state) && @tree_state ? @tree_state.selected : 0) || 0,
      orientation: :vertical_right,
      thumb_symbol: '┆',
      track_symbol: '│',
      # begin_symbol: '╮',
      begin_symbol: settings.corner == :rounded ? '╮' : '┐',
      end_symbol: settings.corner == :rounded ? '╯' : '┘',
      thumb_style: tui.style(
        fg: scrollbar_style
      ),
      track_style: tui.style(
        fg: scrollbar_style
      )
    )

    frame.render_widget(scrollbar_widget, region)
  end
end
