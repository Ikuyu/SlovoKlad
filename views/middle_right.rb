def draw_middle_right_region(tui, frame, region)
  settings = AppConfig.settings

  popup_is_displayed = (defined?(@active_focus) && @active_focus.to_s == 'popup') ||
                       (defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?)
  is_statusbar_search = defined?(@search_replace_origin_mode) && @search_replace_origin_mode == :command_mode
  is_command_mode     = (defined?(@active_focus) && @active_focus.to_s == 'command_mode') || defined?(@command_mode_visible) && @command_mode_visible
  has_active_error_alert = defined?(@status_message) && !@status_message.nil?
  table_has_actual_focus = ((@active_focus.to_s == 'table') ||
                             (@active_focus.to_s == 'replace_mode' && @last_focus.to_s == 'table')) &&
                           !is_statusbar_search && !popup_is_displayed && !is_command_mode && !has_active_error_alert

  menu_is_active = table_has_actual_focus && !popup_is_displayed

  colors = table_colors(menu_is_active)
  block = build_table_block(tui, colors)
  frame.render_widget(block, region)

  # =========================================================================
  # 🎯 COUPLING FIX: HANDMATIGE TITEL MASKING BOVENOP DE BORDER
  # =========================================================================
  # Bereken de exacte celcoördinaten op de bovenrand van de actieve regio (y = region.y)
  # We schuiven 2 cellen op naar rechts (x + 2) voor de strakke padding look
  title_area = RatatuiRuby::Layout::Rect.new(
    region.x + 2,
    region.y,
    [region.width - 4, 1].max,
    1
  )

  accent_style = if %w[menu tree].include?(@active_focus.to_s)
                   tui.style(fg: settings.theme_item(:window_shortcut_section), modifiers: [:bold])
                 else
                   # 🚨 Ruststand
                   tui.style(fg: settings.theme_item(:window_shortcut_section), modifiers: [:bold])
                 end

  # Het hoofdwoord "Cards" dimt mee zodra de haken oplichten
  text_style = if %w[menu tree].include?(@active_focus.to_s)
                 tui.style(fg: settings.theme_item(:window_title), modifiers: [:dim])
               else
                 tui.style(fg: settings.theme_item(:window_title))
               end

  # Smeed de spans handmatig samen tot de definitieve titellijn
  label, key = AppConfig.settings.language_string(:table_title).split(/\s+/, 2)

  title_spans = [
    tui.span(" #{label} ", text_style), # Fel gekleurd bij Menu/Table, helder wit bij de rest!
    tui.span("#{key} ", accent_style)
  ]

  # Render de spans als een Paragraph widget bovenop de rand
  formatted_title = RatatuiRuby::Text::Line.new(spans: title_spans)
  frame.render_widget(RatatuiRuby::Widgets::Paragraph.new(text: formatted_title, alignment: :left), title_area)
  # =========================================================================

  # Keep the rest of the original table layout and data rendering unchanged from here on.
  header_region, divider_region, data_region = table_regions(tui, block.inner(region))
  widths = table_column_widths(data_region)
  render_table_header(tui, frame, header_region, widths, colors, settings)
  render_table_divider(tui, frame, divider_region,
                       table_has_actual_focus ? settings.theme_item(:window_border) : settings.theme_item(:foreground))

  render_permanent_table_dividers(tui, frame, data_region, widths) if @show_table_dividers == true

  render_table_data(
    tui,
    frame,
    data_region,
    widths,
    colors,
    settings,
    region
  )

  bg_color = settings.theme_item(:background)
  style_junction = if popup_is_displayed || is_command_mode || has_active_error_alert
                     { fg: settings.theme_item(:foreground), bg: bg_color, modifiers: [:dim] }
                   else
                     { fg: table_has_actual_focus ? settings.theme_item(:window_border) : settings.theme_item(:foreground), bg: bg_color,
                       modifiers: table_has_actual_focus ? [] : [:dim] }
                   end

  header_divider_y = data_region.y - 1
  frame.render_widget(tui.paragraph(text: '├', style: style_junction),
                      RatatuiRuby::Layout::Rect.new(region.x, header_divider_y, 1, 1))
  frame.render_widget(tui.paragraph(text: '┤', style: style_junction),
                      RatatuiRuby::Layout::Rect.new(region.x + region.width - 1, header_divider_y, 1, 1))

  return unless @show_table_dividers == true

  # 🎯 DYNAMIC ANKER TRACKING: Bereken exact waar de lijnen kruisen op basis van de echte kolomgrootte!
  sep1_x = data_region.x + 1 + widths[:checkbox] + 1
  sep2_x = sep1_x + widths[:term] + 3
  sep3_x = sep2_x + widths[:context] + 3

  top_divider_positions = [sep2_x, sep3_x]
  all_divider_positions = [sep1_x, sep2_x, sep3_x]

  top_divider_positions.each do |div_x|
    frame.render_widget(tui.paragraph(text: '┬', style: style_junction),
                        RatatuiRuby::Layout::Rect.new(div_x, region.y, 1, 1))
  end

  all_divider_positions.each do |div_x|
    frame.render_widget(tui.paragraph(text: '┼', style: style_junction),
                        RatatuiRuby::Layout::Rect.new(div_x, header_divider_y, 1, 1))

    frame.render_widget(tui.paragraph(text: '┴', style: style_junction),
                        RatatuiRuby::Layout::Rect.new(div_x, region.y + region.height - 1, 1, 1))
  end
end

def render_permanent_table_dividers(tui, frame, data_region, widths)
  is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?
  has_active_error_alert = defined?(@status_message) && !@status_message.nil?
  is_command_mode = (defined?(@active_focus) && @active_focus.to_s == 'command_mode') || defined?(@command_mode_visible) && @command_mode_visible
  table_has_focus = ((@active_focus.to_s == 'table') ||
                        (@active_focus.to_s == 'replace_mode' && @last_focus.to_s == 'table')) &&
                    !has_active_error_alert && !is_popup_active && !is_command_mode

  border_color = AppConfig.settings.theme_item(table_has_focus ? :window_border : :foreground)

  divider_style = {
    fg: border_color,
    modifiers: table_has_focus ? [] : [:dim]
  }
  # Bereken de exacte X-as ankers op basis van de kolomwiskunde + column_spacing (3)
  # We houden exact rekening met de highlight_spacing (:always) die 1 startmarge pakt.
  cursor_margin = 1

  sep1_x = data_region.x + cursor_margin + widths[:checkbox] + 1
  sep2_x = sep1_x + widths[:term] + 3
  sep3_x = sep2_x + widths[:context] + 3

  (0...data_region.height.to_i).each do |line_offset|
    line_y = data_region.y + line_offset

    # Draw the three dividers from top to bottom across the entire region.
    frame.render_widget(tui.paragraph(text: '│', style: divider_style),
                        RatatuiRuby::Layout::Rect.new(sep1_x, line_y, 1, 1))
    frame.render_widget(tui.paragraph(text: '│', style: divider_style),
                        RatatuiRuby::Layout::Rect.new(sep2_x, line_y, 1, 1))
    frame.render_widget(tui.paragraph(text: '│', style: divider_style),
                        RatatuiRuby::Layout::Rect.new(sep3_x, line_y, 1, 1))
  end
end

def table_colors(active_table)
  settings = AppConfig.settings

  {
    active_table: active_table,
    active_border: settings.theme_item(:window_border),
    active_title: settings.theme_item(:window_title),
    foreground: settings.theme_item(:foreground),
    background: settings.theme_item(:background),
    selected_fg: settings.theme_item(:selected_row_foreground),
    selected_bg: settings.theme_item(:selected_row_background),
    search_fg: settings.theme_item(:background),
    search_bg: settings.theme_item(:search_results_background),
    header: settings.theme_item(:studysessions_answer)
  }
end

def build_table_block(tui, colors)
  settings = AppConfig.settings

  popup_from_menu = defined?(@active_focus) && @active_focus == :popup &&
                    defined?(@menu_origin_focus) && !@menu_origin_focus.nil?

  border_style = if popup_from_menu
                   { fg: settings.theme_item(:foreground), modifiers: [:dim] }
                 elsif colors[:active_table]
                   { fg: colors[:active_border] }
                 else
                   { fg: settings.theme_item(:foreground), modifiers: [:dim] }
                 end

  tui.block(title: nil, border_style: border_style, style: { bg: settings.theme_item(:background) }, borders: [:all],
            border_type: settings.corner)
end

def table_regions(tui, interior)
  tui.layout_split(
    interior,
    direction: :vertical,
    constraints: [
      tui.constraint(:length, 1),
      tui.constraint(:length, 1),
      tui.constraint(:min, 1)
    ]
  )
end

def table_column_widths(data_region)
  checkbox = 5
  div_w = 3

  # 1. Bereken de exacte totale binnenruimte die we overhouden voor data
  # We trekken de checkbox (5) en de 3 dividers (3 * 3 = 9) af van de breedte van de regio
  total_net = data_region.width - checkbox - (div_w * 3)

  # 2. Verdeel de ruimte exact over de 3 kolommen via integer-divisie
  equal_width = (total_net / 3).floor

  # 3. Bereken het wiskundige restant (0, 1 of 2 cellen)
  remainder = total_net % 3

  # 4. Pas de evenredige breedte toe met een veilige ondergrens van 12
  term    = [equal_width, 12].max
  context = [equal_width, 12].max

  # De meaning-kolom krijgt de basisbreedte + het eventuele restant
  meaning = [equal_width + remainder, 12].max

  {
    checkbox: checkbox,
    term: term,
    context: context,
    meaning: meaning,
    divider: div_w
  }
end

def render_table_header(tui, frame, region, widths, colors, settings)
  headers = [
    settings.language_string(:table_header_field1).to_s, # Study (Index 0)
    settings.language_string(:table_header_field2).to_s, # Term (Index 1)
    settings.language_string(:table_header_field3).to_s, # Context (Index 2)
    settings.language_string(:table_header_field4).to_s  # Meaning (Index 3)
  ]
  triangle = @current_sort_dir == :asc ? '╿' : '╽'
  dividers_on = (@show_table_dividers == true)

  is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?
  is_command_mode   = (defined?(@active_focus) && @active_focus.to_s == 'command_mode') || defined?(@command_mode_visible) && @command_mode_visible
  has_error_alert   = defined?(@status_message) && !@status_message.nil?

  table_has_actual_focus = ((@active_focus.to_s == 'table') ||
                           (@active_focus.to_s == 'replace_mode' && @last_focus.to_s == 'table')) &&
                           !is_popup_active && !is_command_mode && !has_error_alert
  divider_style = tui.style(
    fg: table_has_actual_focus ? settings.theme_item(:window_border) : settings.theme_item(:foreground),
    modifiers: []
  )

  cells = headers.each_with_index.map do |header, index|
    sort_keys = %i[study term context meaning]

    is_sorted_col =
      @sort_indicator_visible == true &&
      @current_sort_col == sort_keys[index]

    make_cell = lambda do |prefix, header_text, suffix = ''|
      spans = []

      unless prefix.empty?
        prefix_is_dimmed =
          ['│', '┆'].include?(prefix) ||
          prefix == triangle

        spans << tui.text_span(
          content: prefix,
          style: prefix_is_dimmed ? divider_style : nil
        )

        spans << tui.text_span(
          content: ' '
        )
      end

      spans << tui.text_span(
        content: header_text
      )

      unless suffix.empty?
        # 🎯 CHIRURGISCHE UITLIJNINGS-LINK
        # If the suffix contains manual padding (starts with a space),
        # slaan we de standaard enkele spatie-padding over om layout clipping te vermijden!
        unless suffix.start_with?(' ')
          spans << tui.text_span(
            content: ' '
          )
        end

        suffix_is_dimmed =
          suffix.include?('┆') ||
          suffix.include?(triangle)

        spans << tui.text_span(
          content: suffix,
          style: suffix_is_dimmed ? divider_style : nil
        )
      end

      tui.table_cell(
        content: tui.text_line(spans: spans)
      )
    end

    if dividers_on
      sort_visible = @sort_indicator_visible == true

      prefix =
        if index.positive?
          if index == 1 && sort_visible && @current_sort_col == :study then triangle
          elsif index == 2 && sort_visible && @current_sort_col == :term then triangle
          elsif index == 3 && sort_visible && @current_sort_col == :context then triangle
          else '│'
          end
        else
          ''
        end

      header_text = header
      suffix = ''

      make_cell.call(
        prefix,
        index == 0 ? " #{header_text}" : header_text,
        suffix
      )
    else
      make_cell.call(
        '',
        " #{header}",
        is_sorted_col ? triangle : ''
      )
    end
  end

  title_style =
    if colors[:active_table]
      {
        fg: settings.theme_item(:table_header_text),
        modifiers: []
      }
    else
      {
        fg: settings.theme_item(:table_header_text),
        modifiers: %i[dim]
      }
    end

  study_width = widths[:checkbox] + (dividers_on ? 2 : 3)

  table = tui.table(
    rows: [tui.row(cells: cells, style: title_style)],
    widths: [
      tui.constraint(:length, study_width),
      tui.constraint(:length, widths[:term] + 3),
      tui.constraint(:length, widths[:context] + 3),
      tui.constraint(:length, widths[:meaning] + 3) # 🎯 FIX: Spacing pariteit voor Meaning!
    ],
    column_spacing: 0,
    highlight_symbol: '',
    highlight_spacing: :never
  )
  frame.render_widget(table, region)

  return unless dividers_on && @sort_indicator_visible == true && @current_sort_col == :meaning

  # Bereken de exacte x-coördinaat van de absolute rechtervensterrand
  rechter_border_x = region.x + region.width

  # We ankeren de y-as strak op de header-regel (region.y)
  indicator_area = RatatuiRuby::Layout::Rect.new(rechter_border_x, region.y, 1, 1)

  # Gebruik de actieve divider_style (fg van de actieve/gedimde border)
  indicator_widget = tui.paragraph(text: triangle, style: divider_style)

  # Draw the character over the border with the highest priority.
  frame.render_widget(indicator_widget, indicator_area)
end

def render_table_divider(tui, frame, region, color)
  is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?
  has_active_error_alert = defined?(@status_message) && !@status_message.nil?

  table_has_focus = ((@active_focus.to_s == 'table') ||
                      (@active_focus.to_s == 'replace_mode' && @last_focus.to_s == 'table')) &&
                    !has_active_error_alert && !is_popup_active

  divider_modifiers = table_has_focus ? [] : [:dim]

  frame.render_widget(
    tui.paragraph(text: '─' * region.width, style: { fg: color, modifiers: divider_modifiers }),
    region
  )
end

def render_table_data(tui, frame, data_region, widths, colors, settings, outer_region)
  cards = active_cards_for_table
  has_search = @search_matches && @search_matches.any?
  table_popup_active = defined?(@popup) && @popup &&
                       @popup.respond_to?(:active?) && @popup.active?
  visually_active = !table_popup_active &&
                    (@active_focus == :table ||
                     (@active_focus == :replace_mode && @last_focus == :table))
  search_regex = table_search_regex(has_search)
  viewport = table_viewport(cards.length, data_region.height.to_i, has_search)

  visible_cards = cards[viewport[:offset], viewport[:page_size]] || []

  table_rows = build_table_rows(
    tui,
    visible_cards,
    viewport[:offset],
    widths,
    colors,
    settings,
    search_regex,
    visually_active
  )

  if settings.alternate_rows_enabled && alternate_table_rows_allowed?
    missing_rows = viewport[:page_size] - visible_cards.length

    missing_rows.times do |index|
      absolute_index = viewport[:offset] + visible_cards.length + index

      alternate_background = (if absolute_index.odd?
                                alternate_table_row_background(colors[:background],
                                                               colors[:foreground])
                              end)

      row_style = alternate_background ? { bg: alternate_background } : {}
      divider = @show_table_dividers == true ? ' │ ' : '   '

      cells = [
        widths[:checkbox],
        widths[:divider],
        widths[:term],
        widths[:divider],
        widths[:context],
        widths[:divider],
        widths[:meaning] + 3
      ].each_with_index.map do |width, cell_index|
        content = cell_index.odd? ? divider : ' ' * width.to_i
        RatatuiRuby::Widgets::Cell.new(content: content)
      end

      table_rows << tui.row(cells: cells, style: row_style)
    end
  end

  table_region, scrollbar_region =
    split_table_content_region(data_region, outer_region)

  render_table_widget(tui, frame, table_region, widths, table_rows)

  render_table_scrollbar(
    tui,
    frame,
    scrollbar_region,
    cards.length,
    colors,
    visually_active
  )
end

def split_table_content_region(data_region, outer_region)
  scrollbar_region = RatatuiRuby::Layout::Rect.new(
    outer_region.x,
    data_region.y - 1,
    outer_region.width,
    data_region.height + 2
  )

  [data_region, scrollbar_region]
end

def active_cards_for_table
  return active_cards if respond_to?(:active_cards, true)

  nodes = @tree&.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
  node = nodes[@tree_state&.selected || 0]
  node && node[:type] == :deck && node[:object] ? (node[:object].cards || []) : []
end

def alternate_table_rows_allowed?
  nodes = @tree&.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
  selected_node = nodes[@tree_state&.selected || 0]

  selected_node&.dig(:type) == :deck
end

def table_search_regex(has_search)
  query = @last_search_query.to_s
  return reset_table_search_regex unless has_search && !query.empty?

  folding = @table_folding == true

  signature = [
    @last_search_query,
    @last_case_sensitive == true,
    @last_regex == true,
    folding
  ]

  return @table_search_regex_cache if @table_search_regex_signature == signature

  @table_search_regex_signature = signature
  @table_search_regex_cache = build_table_search_regex(query, folding)
end

def build_table_search_regex(query, folding = false)
  flags = @last_case_sensitive ? 0 : Regexp::IGNORECASE

  pattern = if @last_regex
              query
            else
              build_script_insensitive_regex(query, @last_case_sensitive == true, folding)
            end

  Regexp.new("(#{pattern})", flags)
rescue RegexpError
  nil
end

def reset_table_search_regex
  @table_search_regex_signature = nil
  @table_search_regex_cache = nil
end

def table_viewport(total_rows, page_size, has_search)
  page_size = [page_size.to_i, 1].max
  max_offset = [total_rows - page_size, 0].max
  selected = @table_state&.respond_to?(:selected) ? (@table_state.selected || 0).to_i : 0
  selected = [[selected, 0].max, [total_rows - 1, 0].max].min if total_rows.positive?

  offset = current_table_viewport_offset(has_search)
  offset = [[offset, 0].max, max_offset].min
  offset = keep_table_cursor_visible(selected, offset, page_size, max_offset) if total_rows.positive?

  @table_viewport_offset = offset
  @normal_page_viewport_start = offset unless has_search
  @search_page_viewport_start = offset if has_search
  @table_visible_height = page_size

  { offset: offset, page_size: page_size, selected: selected }
end

def current_table_viewport_offset(has_search)
  return @table_viewport_offset.to_i if defined?(@table_viewport_offset) && !@table_viewport_offset.nil?
  if has_search && defined?(@search_page_viewport_start) && !@search_page_viewport_start.nil?
    return @search_page_viewport_start.to_i
  end
  if !has_search && defined?(@normal_page_viewport_start) && !@normal_page_viewport_start.nil?
    return @normal_page_viewport_start.to_i
  end

  @table_state&.respond_to?(:offset) ? @table_state.offset.to_i : 0
end

def keep_table_cursor_visible(selected, offset, page_size, max_offset)
  offset = selected if selected < offset
  offset = selected - page_size + 1 if selected >= offset + page_size
  [[offset, 0].max, max_offset].min
end

def build_table_rows(tui, cards, offset, widths, colors, settings, search_regex, visually_active)
  selected = if @table_state&.respond_to?(:selected)
               (@table_state.selected || 0).to_i
             else
               0
             end

  selected_rows = @selected_table_rows || []

  lookup =
    if selected_rows.length > 16
      selected_rows.each_with_object({}) do |row, result|
        result[row] = true
      end
    end

  # 🎯 UNIVERSELE MEMORY GATEWAY:
  # Vraag live de handgeschreven status op van de actieve taal-omgeving.
  active_lang = AppConfig.settings.language || :ru
  is_handwritten = AppConfig.settings.handwritten?(active_lang)

  cards.each_with_index.map do |card, screen_index|
    absolute_index = offset + screen_index
    hide_table_cursor = %i[menu popup].include?(@active_focus) ||
                        (defined?(@popup) && @popup&.active?)
    selected_row = !hide_table_cursor && selected == absolute_index

    marked_row = lookup ? lookup.key?(absolute_index) : selected_rows.include?(absolute_index)
    alternate_background = if settings.alternate_rows_enabled &&
                              alternate_table_rows_allowed? &&
                              absolute_index.odd?
                             alternate_table_row_background(colors[:background], colors[:foreground])
                           end

    row_style = table_row_style(selected_row, visually_active, colors, alternate_background)

    is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?
    is_command_mode = defined?(@active_focus) && @active_focus == :command_mode
    is_statusbar_search = defined?(@search_replace_origin_mode) && @search_replace_origin_mode == :command_mode

    is_overlay_from_here = (is_popup_active || is_command_mode || is_statusbar_search) &&
                           ((defined?(@focus_before_help) && @focus_before_help == :table) ||
                            (defined?(@last_focus) && @last_focus == :table) ||
                            (defined?(@menu_origin_focus) && @menu_origin_focus == :table))

    cell_style =
      if selected_row && is_overlay_from_here
        { fg: colors[:selected_row_foreground], modifiers: visually_active ? [] : [:dim] }
      elsif visually_active && selected_row
        { fg: colors[:selected_fg], modifiers: [] }
      elsif visually_active
        { fg: colors[:foreground], modifiers: [] }
      else
        { fg: colors[:foreground], modifiers: [:dim] }
      end

    if defined?(@status_message) && !@status_message.nil?
      cell_style = cell_style.dup
      cell_style[:modifiers] = Array(cell_style[:modifiers]) | [:dim]
    end

    highlight_style = { fg: colors[:search_fg], bg: colors[:search_bg], modifiers: [] }

    # Sluis de universele boolean 3x door voor alle kolommen!
    cells = build_table_cells(
      card, widths, cell_style, highlight_style, search_regex, marked_row, settings, selected_row,
      is_handwritten, is_handwritten, is_handwritten # 🟢 RECHTSTREEKSE SCHONE REEKS!
    )

    tui.row(cells: cells, style: row_style)
  end
end

def build_table_cells(card, widths, row_style, highlight_style, search_regex, marked_row, settings, selected_row,
                      term_hw, context_hw, meaning_hw)
  indicator = marked_row ? '▍' : ' '
  active_marker_config = settings.marker_symbol
  pure_symbol = active_marker_config.is_a?(Hash) ? active_marker_config[:symbol] : active_marker_config

  checkbox = "[#{card.study ? pure_symbol : ' '}]"

  is_popup_active   = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?
  is_command_mode   = (defined?(@active_focus) && @active_focus.to_s == 'command_mode') || defined?(@command_mode_visible) && @command_mode_visible
  has_error_alert   = defined?(@status_message) && !@status_message.nil?

  table_has_focus = ((@active_focus.to_s == 'table') ||
                    (@active_focus.to_s == 'replace_mode' && @last_focus.to_s == 'table')) &&
                    !is_popup_active && !is_command_mode && !has_error_alert

  make_divider_line = lambda do
    if @show_table_dividers == true
      bar_modifiers = selected_row || table_has_focus ? [] : [:dim]
      bar_fg = table_has_focus ? settings.theme_item(:window_border) : settings.theme_item(:foreground)

      RatatuiRuby::Text::Line.new(spans: [
                                    RatatuiRuby::Text::Span.new(content: ' ', style: row_style),
                                    RatatuiRuby::Text::Span.new(content: '│',
                                                                style: {
                                                                  fg: bar_fg, bg: row_style[:bg], modifiers: bar_modifiers
                                                                }),
                                    RatatuiRuby::Text::Span.new(content: ' ', style: row_style)
                                  ])
    else
      RatatuiRuby::Text::Line.new(spans: [RatatuiRuby::Text::Span.new(content: '   ', style: row_style)])
    end
  end

  total_col_width = widths[:checkbox].to_i
  raw_content_str = "#{indicator}#{checkbox}"

  padding_total = [total_col_width - raw_content_str.length, 0].max
  left_padding  = padding_total / 2
  right_padding = padding_total - left_padding

  indicator_fg = if selected_row
                   row_style[:bg]
                 else
                   (marked_row ? settings.theme_item(:selected_row_background) : row_style[:fg])
                 end
  indicator_bg = if selected_row
                   row_style[:bg]
                 else
                   (marked_row ? settings.theme_item(:background) : row_style[:bg])
                 end

  indicator_style = { fg: indicator_fg, bg: indicator_bg }
  indicator_style[:modifiers] = [:dim] unless selected_row

  checkbox_line = RatatuiRuby::Text::Line.new(spans: [
                                                RatatuiRuby::Text::Span.new(content: ' ' * left_padding,
                                                                            style: row_style),
                                                RatatuiRuby::Text::Span.new(content: indicator, style: indicator_style),
                                                RatatuiRuby::Text::Span.new(content: checkbox, style: row_style),
                                                RatatuiRuby::Text::Span.new(content: ' ' * right_padding,
                                                                            style: row_style)
                                              ])

  safe_meaning_width = [widths[:meaning] - 2, 12].max

  cells = []
  cells << RatatuiRuby::Widgets::Cell.new(content: checkbox_line)
  cells << RatatuiRuby::Widgets::Cell.new(content: make_divider_line.call)

  # 🟢 DOORGEGEVEN: Nu sturen we de pure handgeschreven boolean mee naar de cel!
  cells << highlighted_table_cell(card.term, widths[:term], row_style, highlight_style, search_regex, selected_row,
                                  term_hw)
  cells << RatatuiRuby::Widgets::Cell.new(content: make_divider_line.call)

  cells << highlighted_table_cell(card.context, widths[:context], row_style, highlight_style, search_regex,
                                  selected_row, context_hw)
  cells << RatatuiRuby::Widgets::Cell.new(content: make_divider_line.call)

  cells << highlighted_table_cell(card.meaning, safe_meaning_width, row_style, highlight_style, search_regex,
                                  selected_row, meaning_hw)

  cells
end

def table_cell_rtl?(text)
  first_letter = text.to_s.each_char.find do |char|
    char.match?(/\p{L}/)
  end

  return false unless first_letter

  cp = first_letter.ord

  (0x0590..0x08FF).cover?(cp) ||
    (0xFB1D..0xFDFF).cover?(cp) ||
    (0xFE70..0xFEFF).cover?(cp)
end

def highlighted_table_cell(raw_text, max_width, base_style, highlight_style, search_regex, is_row_selected = false,
                           is_handwritten = false)
  raw_value = raw_text.to_s
  visual_field = RatinField.new
  visual_field.text = raw_value
  is_rtl = visual_field.direction == :rtl
  max_width = [max_width.to_i, 1].max

  layout_cache = (@table_visual_layout_cache ||= {})
  layout = layout_cache[raw_value]

  unless layout
    visual_field = RatinField.new
    visual_field.text = raw_value
    layout = visual_field.visual_layout

    layout_cache.clear if layout_cache.length >= 4096
    layout_cache[raw_value] = layout
  end

  visual_text = layout.map { |item| item[:char] }.join

  visible_layout = layout.dup
  prefix_text = +''
  suffix_text = +''

  if Unicode::DisplayWidth.of(visual_text) > max_width
    target_space = [max_width - 1, 0].max
    retained_layout = []
    current_width = 0

    # Zoek eerst de eerste match in de oorspronkelijke logische tekst.
    match_positions = []
    if search_regex
      first_match = raw_value.match(search_regex)

      if first_match
        match_start = raw_value[0...first_match.begin(0)].to_s.codepoints.length
        match_end = match_start + first_match[0].codepoints.length

        match_positions = layout.each_index.select do |i|
          indices = layout[i][:logical_indices] || []
          indices.any? { |index| index >= match_start && index < match_end }
        end
      end
    end

    if !match_positions.empty? && max_width >= 3
      # Maak een venster rond de gevonden match in de visuele layout.
      first_pos = match_positions.min
      last_pos = match_positions.max

      window_width = lambda do |first, last|
        layout[first..last].sum do |item|
          Unicode::DisplayWidth.of(item[:char])
        end
      end

      left = first_pos
      right = last_pos
      current_width = window_width.call(left, right)

      # Reserveer ruimte voor de ellipsen aan beide kanten.
      budget = [max_width - 2, 1].max

      if current_width <= budget
        expand_left = true

        while true
          candidate_left = left - 1
          candidate_right = right + 1

          left_width = if candidate_left >= 0
                         Unicode::DisplayWidth.of(layout[candidate_left][:char])
                       else
                         Float::INFINITY
                       end
          right_width = if candidate_right < layout.length
                          Unicode::DisplayWidth.of(layout[candidate_right][:char])
                        else
                          Float::INFINITY
                        end

          break if left_width == Float::INFINITY && right_width == Float::INFINITY

          added = false

          # Alternate left and right to show context around the match.
          if expand_left
            if left_width.finite? && current_width + left_width <= budget
              left = candidate_left
              current_width += left_width
              added = true
            elsif right_width.finite? && current_width + right_width <= budget
              right = candidate_right
              current_width += right_width
              added = true
            end
          elsif right_width.finite? && current_width + right_width <= budget
            right = candidate_right
            current_width += right_width
            added = true
          elsif left_width.finite? && current_width + left_width <= budget
            left = candidate_left
            current_width += left_width
            added = true
          end

          break unless added

          expand_left = !expand_left
        end

        retained_layout = layout[left..right]
        prefix_text = left.positive? ? '…' : ''
        suffix_text = right < layout.length - 1 ? '…' : ''
      end
    end

    # Geen bruikbare match, of de match past niet in het venster:
    # behoud het bestaande gedrag voor inkorten.
    if retained_layout.empty?
      current_width = 0

      if is_rtl
        layout.reverse_each do |item|
          width = Unicode::DisplayWidth.of(item[:char])
          break if current_width + width > target_space

          retained_layout.unshift(item)
          current_width += width
        end

        padding_needed = target_space - current_width
        prefix_text = ' ' * padding_needed + '…'
        suffix_text = ''
      else
        layout.each do |item|
          width = Unicode::DisplayWidth.of(item[:char])
          break if current_width + width > target_space

          retained_layout << item
          current_width += width
        end

        padding_needed = target_space - current_width
        suffix_text = ' ' * padding_needed + '…'
        prefix_text = ''
      end
    end

    visible_layout = retained_layout
    visual_text = prefix_text +
                  visible_layout.map { |item| item[:char] }.join +
                  suffix_text
  end

  spans = highlighted_table_cell_spans(
    raw_value, visual_text, base_style, highlight_style, search_regex,
    is_row_selected, is_handwritten,
    visible_layout, prefix_text, suffix_text
  )

  if spans.empty?
    final_base = base_style.dup
    final_base[:modifiers] = Array(final_base[:modifiers]) | [:italic] if is_handwritten
    spans << RatatuiRuby::Text::Span.new(content: ' ', style: final_base)
  end

  # Right-align RTL cells by adding leading spaces.
  # Keep the text in its existing visual order.
  if table_cell_rtl?(raw_value)
    visible_width = Unicode::DisplayWidth.of(visual_text)
    leading_padding = [max_width - visible_width, 0].max

    if leading_padding.positive?
      spans.unshift(
        RatatuiRuby::Text::Span.new(
          content: ' ' * leading_padding,
          style: base_style
        )
      )
    end
  end

  protected_spans = [
    RatatuiRuby::Text::Span.new(
      content: "\u2066",
      style: base_style
    )
  ] + spans + [
    RatatuiRuby::Text::Span.new(
      content: "\u2069",
      style: base_style
    )
  ]

  line = RatatuiRuby::Text::Line.new(
    spans: protected_spans
  )

  RatatuiRuby::Widgets::Cell.new(content: line)
end

# 🟢 DE ABSOLUTE DOORBRAAK: Voegt :italic rechtstreeks samen op het diepste Span-niveau!
def highlighted_spans(text, base_style, highlight_style, regex, is_row_selected = false, is_handwritten = false)
  settings = AppConfig.settings

  # Definieer de waterdichte Latijn/ASCII filter-grendel
  is_latin_or_common = lambda do |char|
    char =~ /\A[\p{Latin}0-9\s[:punct:]]\z/
  end

  # Hulpmethode om modifiers veilig en taalspecifiek te versmelten
  build_span_style = lambda do |raw_style, content_str|
    style_copy = raw_style.dup
    # We activeren :italic ALLEEN als de i-toets aan staat ÉN het segment non-Latijns is!
    if is_handwritten && !is_latin_or_common.call(content_str[0])
      style_copy[:modifiers] = Array(style_copy[:modifiers]) | [:italic]
    end
    style_copy
  end

  # Construeer de highlight-stijl voor actieve zoekacties op de cursorbalk
  effective_highlight = highlight_style.dup
  if is_row_selected && AppConfig.settings.respond_to?(:theme_item)
    begin
      effective_highlight = {
        fg: settings.theme_item(:background),
        bg: settings.theme_item(:search_results_background),
        modifiers: [:underlined]
      }
    rescue StandardError
      effective_highlight = highlight_style.dup
    end
  end

  # KORTE ROUTE: Als er geen actieve zoekterm/regex match is, splitsen we puur op script-type
  unless regex && text =~ regex
    spans = []
    segment = +''

    # 🎯 GRAPHEME CLUSTER PARSER: splitst zuiver op visuele letters incl. klinkers via grapheme_clusters
    text.grapheme_clusters.each do |grapheme|
      # Kijk naar het eerste basiskarakter van het cluster voor de ASCII-check
      first_char = grapheme.chars.first

      if segment.empty?
        segment << grapheme
      elsif is_latin_or_common.call(segment.chars.first) == is_latin_or_common.call(first_char)
        segment << grapheme
      else
        spans << RatatuiRuby::Text::Span.new(content: segment, style: build_span_style.call(base_style, segment))
        segment = +'' << grapheme
      end
    end
    unless segment.empty?
      spans << RatatuiRuby::Text::Span.new(content: segment, style: build_span_style.call(base_style, segment))
    end
    return spans
  end

  # LANGE ROUTE: Er is een actieve zoek-highlight! We splitsen de regex-matches op én filteren op taal
  spans = []
  current_pos = 0

  text.to_enum(:scan, regex).each do
    match_text = Regexp.last_match[0]
    match_index = Regexp.last_match.begin(0)

    # 1. Verwerk het voorlopende tekstsegment (vòòr de match)
    if match_index > current_pos
      pre_text = text[current_pos...match_index]
      pre_text.chars.each do |c|
        spans << RatatuiRuby::Text::Span.new(content: c, style: build_span_style.call(base_style, c))
      end
    end

    # 2. Verwerk de zoek-highlight match zelf op karakterniveau
    match_text.chars.each do |c|
      spans << RatatuiRuby::Text::Span.new(content: c, style: build_span_style.call(effective_highlight, c))
    end

    current_pos = match_index + match_text.length
  end

  # 3. Verwerk het resterende tekstsegment (na de laatste match)
  if current_pos < text.length
    post_text = text[current_pos..]
    post_text.chars.each do |c|
      spans << RatatuiRuby::Text::Span.new(content: c, style: build_span_style.call(base_style, c))
    end
  end

  spans
end

def highlighted_table_cell_spans(raw_text, visual_text, base_style, highlight_style, regex,
                                 is_row_selected = false, is_handwritten = false,
                                 visible_layout = nil, prefix_text = '', suffix_text = '')
  unless regex
    return highlighted_spans(
      visual_text, base_style, highlight_style, regex,
      is_row_selected, is_handwritten
    )
  end

  raw = raw_text.to_s
  field = RatinField.new
  field.text = raw
  layout = visible_layout || field.visual_layout

  matched_indices = {}

  if @last_regex == true
    # Regexmodus: zoek in de oorspronkelijke tekst.
    raw.to_enum(:scan, regex).each do
      match = Regexp.last_match
      start_cp = raw[0...match.begin(0)].to_s.codepoints.length
      end_cp = start_cp + match[0].codepoints.length
      (start_cp...end_cp).each { |index| matched_indices[index] = true }
    end
  else
    # Normale zoekmodus: normaliseer naar NFD en onthoud
    # bij welk oorspronkelijk teken ieder teken hoort.
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

  effective_highlight = highlight_style.dup
  settings = AppConfig.settings

  if is_row_selected && settings.respond_to?(:theme_item)
    begin
      effective_highlight = {
        fg: settings.theme_item(:background),
        bg: settings.theme_item(:search_results_background),
        modifiers: [:underlined]
      }
    rescue StandardError
      effective_highlight = highlight_style.dup
    end
  end

  is_latin_or_common = lambda do |char|
    char && char.match?(/\A[\p{Latin}0-9\s[:punct:]]\z/)
  end

  build_style = lambda do |style, text|
    result = style.dup
    first_char = text.each_char.find { |c| !c.match?(/\p{M}/) } || text[0]

    if is_handwritten && first_char && !is_latin_or_common.call(first_char)
      result[:modifiers] = Array(result[:modifiers]) | [:italic]
    end

    result
  end

  spans = []
  current_type = nil
  buffer = +''

  flush = lambda do
    unless buffer.empty?
      style = current_type == :highlight ? effective_highlight : base_style
      spans << RatatuiRuby::Text::Span.new(
        content: buffer.dup,
        style: build_style.call(style, buffer)
      )
      buffer.clear
    end
  end

  # Kunstmatige opvulling en ellipsis zijn nooit zoekresultaten.
  unless prefix_text.empty?
    current_type = :base
    buffer << prefix_text
  end

  layout.each do |item|
    cluster = item[:char]
    next unless cluster

    indices = item[:logical_indices] ||
              (item[:logical_index]...item[:logical_end]).to_a

    type = indices.any? { |index| matched_indices[index] } ? :highlight : :base

    flush.call if !buffer.empty? && current_type != type

    current_type = type
    buffer << cluster
  end

  unless suffix_text.empty?
    flush.call if !buffer.empty? && current_type != :base

    current_type = :base
    buffer << suffix_text
  end

  flush.call

  # Veiligheidscontrole: geef bij onverwachte verschillen de bestaande
  # renderer voorrang, zodat er geen tekst uit de cel verdwijnt.
  if spans.map(&:content).join != visual_text.to_s
    return highlighted_spans(
      visual_text, base_style, highlight_style, regex,
      is_row_selected, is_handwritten
    )
  end

  spans
end

def alternate_table_row_background(background, foreground)
  return nil unless background.is_a?(String) && background.match?(/\A#(?:[0-9a-fA-F]{6})\z/)
  return nil unless foreground.is_a?(String) && foreground.match?(/\A#(?:[0-9a-fA-F]{6})\z/)

  rgb = background[1..].scan(/../).map { |value| value.to_i(16) }
  target = foreground[1..].scan(/../).map { |value| value.to_i(16) }

  adjusted = rgb.zip(target).map { |value, tone| (value + (tone - value) * 0.15).round }

  format('#%02X%02X%02X', *adjusted)
end

def table_row_style(selected, visually_active, colors, alternate_background = nil)
  return { bg: alternate_background } if !selected && alternate_background
  return {} unless selected

  # =========================================================================
  # 🎯 TABELRIJ IS GEGARANDEERD GESELECTEERD:
  # =========================================================================
  is_table_focused = visually_active || (@active_focus == :table || (@active_focus == :replace_mode && @last_focus == :table))

  active_popup_type = begin
    @popup.active_popup[:type].to_sym
  rescue StandardError
    nil
  end

  is_overlay_active = %i[popup menu command_mode].include?(@active_focus) ||
                      (defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?) ||
                      %i[help about form].include?(active_popup_type)

  # 🎯 COUPLING TRACE-BRANDMUUR:
  # Inspecteer alle mogelijke historische registers om te bepalen of de Table
  # the absolute starting point of the current action chain.
  came_from_table =
    (defined?(@focus_before_help) && @focus_before_help == :table) ||
    (defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor == :table)

  if is_table_focused
    # 1. Actieve stand: Table heeft focus ➔ Felle cursorbalk!
    { fg: colors[:selected_fg], bg: colors[:selected_bg] }
  elsif is_overlay_active && came_from_table
    # 2. Popup/Menu/Command-mode actief EN table was de diepe herkomst ➔ Gedimd vasthouden!
    { fg: colors[:selected_fg], bg: colors[:selected_bg], modifiers: [:dim] }
  else
    # 3. Ruststand: Focus ligt bij de Tree ➔ Verberg de balk,
    # maar behoud de alternate row background.
    style = { fg: colors[:foreground], modifiers: [:dim] }
    style[:bg] = alternate_background if alternate_background
    style
  end
end

def render_table_widget(tui, frame, region, widths, rows)
  constraints = []
  constraints << tui.constraint(:length, widths[:checkbox])
  constraints << tui.constraint(:length, widths[:divider])
  constraints << tui.constraint(:length, widths[:term])
  constraints << tui.constraint(:length, widths[:divider])
  constraints << tui.constraint(:length, widths[:context])
  constraints << tui.constraint(:length, widths[:divider])
  constraints << tui.constraint(:length, widths[:meaning] + 3) # 🎯 FIX: Spacing pariteit voor Meaning!

  table = tui.table(
    rows: rows,
    widths: constraints,
    column_spacing: 0,
    highlight_symbol: ' ',
    highlight_spacing: :always
  )
  frame.render_widget(table, region)
end

def render_table_scrollbar(tui, frame, region, total_rows, colors, visually_active)
  return unless total_rows > region.height.to_i

  settings = AppConfig.settings

  position =
    if @table_state&.respond_to?(:selected)
      (@table_state.selected || 0).to_i
    else
      0
    end

  thumb_style =
    if visually_active
      {
        fg: colors[:active_border]
      }
    else
      {
        fg: settings.theme_item(
          :foreground
        ),
        modifiers: [:dim]
      }
    end

  scrollbar_widget = tui.scrollbar(
    content_length: total_rows,
    position: position,
    orientation: :vertical_right,
    thumb_symbol: '┆',
    track_symbol: '│',
    begin_symbol: '│',
    end_symbol: settings.corner == :rounded ? '╯' : '┘',
    thumb_style: tui.style(
      fg: thumb_style
    ),
    track_style: tui.style(
      fg: thumb_style
    )
  )

  frame.render_widget(scrollbar_widget, region)
end
