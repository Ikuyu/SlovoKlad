# frozen_string_literal: true

require_relative 'test'

class RatatuiRubyApp
  include TestView

  private

  def render_drill_view(tui, frame, region)
    settings = AppConfig.settings

    @cards_to_test ||= respond_to?(:active_cards) ? active_cards : []
    @test_current_idx ||= 0
    @test_show_meaning = false if @test_show_meaning.nil?
    bg_color = settings.theme_item(:background)
    render_drill_view_background(frame, region, bg_color)
    return if render_drill_completion_state(tui, frame, region, settings)

    @test_drill_total_lines = @cards_to_test.length
    @test_drill_scroll_y ||= 0

    geometry = drill_view_geometry(region, @test_drill_total_lines)
    max_visible_rows = geometry[:max_visible_rows]

    is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    styles = drill_view_styles(settings, bg_color, is_popup_active)
    style_header = styles[:header]
    style_bracket = styles[:bracket]
    style_dimmed = styles[:dimmed]
    style_normal = styles[:normal]
    style_cursor = styles[:cursor]

    render_drill_view_header(
      tui, frame, region, geometry,
      style_header, style_bracket, style_dimmed
    )

    update_drill_viewport(max_visible_rows)

    render_drill_table_body(
      tui, frame, settings, region, geometry,
      style_normal, style_cursor, style_dimmed, bg_color
    )

    render_drill_view_borders(tui, frame, region, settings, geometry, style_dimmed)

    render_drill_context_panel(
      tui, frame, settings, region, geometry,
      bg_color, style_dimmed, is_popup_active
    )

    # Scrollbar
    return unless respond_to?(:render_drill_scrollbar, true)

    render_drill_scrollbar(
      tui, frame, region, @test_drill_total_lines.to_i,
      @test_current_idx.to_i, geometry[:max_visible_rows]
    )
  end

  def render_drill_view_background(frame, region, bg_color)
    return unless defined?(RatatuiRuby::Widgets::Clear)

    frame.render_widget(RatatuiRuby::Widgets::Clear.new, region)
    background = RatatuiRuby::Widgets::Block.new(style: { bg: bg_color }, borders: [:none])
    frame.render_widget(background, region)
  end

  # Returns true when the completion screen replaces the drill table.
  def render_drill_completion_state(tui, frame, region, settings)
    drill_active = defined?(@current_study_mode) && @current_study_mode == :drill
    finished = defined?(@test_finished_waiting) && @test_finished_waiting == true
    return false unless drill_active && (finished || @cards_to_test.empty?)

    lines = [
      settings.language_string(:study_status_screen_drill),
      "#{settings.language_string(:study_status_screen_exercise_completed)}.",
      settings.language_string(:study_status_screen_finished)
    ]
    render_test_status_screen(tui, frame, region, '✓', lines)
    true
  end

  def render_drill_table_body(tui, frame, settings, region, geometry,
                              style_normal, style_cursor, style_dimmed, bg_color)
    base_data_y = geometry[:base_data_y]
    table_height = geometry[:actual_table_height]
    middle_sep_x = geometry[:middle_sep_x]

    if @show_table_dividers == true
      table_height.times do |line_offset|
        line_y = base_data_y + line_offset
        cursor_line = line_offset == (@test_current_idx - @drill_viewport_start)
        separator_style = cursor_line ? style_cursor : style_dimmed
        frame.render_widget(
          tui.paragraph(text: '│', style: separator_style),
          RatatuiRuby::Layout::Rect.new(middle_sep_x, line_y, 1, 1)
        )
      end
    end

    render_drill_card_rows(
      tui, frame, settings, region,
      geometry[:base_data_y], geometry[:hard_boundary_y], geometry[:max_visible_rows],
      geometry[:start_x], geometry[:text_start_x], geometry[:left_col_w], geometry[:right_col_w],
      geometry[:middle_sep_x], geometry[:right_col_x], style_normal, style_cursor, bg_color
    )
  end

  # Keep row counts, boundaries, and column widths derived from one geometry calculation.
  def drill_view_geometry(region, total_lines)
    base_data_y = region.y + 2
    max_visible_rows = @test_show_context ? region.height - 4 : region.height - 2
    max_visible_rows = [max_visible_rows, 1].max
    @test_drill_visible_rows = max_visible_rows

    hard_boundary_y = @test_show_context ? region.y + region.height - 2 : region.y + region.height
    actual_table_height = hard_boundary_y - base_data_y
    scrollbar_visible = drill_scrollbar_needed?(total_lines, max_visible_rows)

    start_x = region.x
    # Keep the column split stable when the context toggles; reserve scrollbar
    # space only from the right column below.
    full_table_w = [region.width - 1, 1].max
    padding_side = 1
    text_start_x = start_x + padding_side
    available_w = full_table_w - (padding_side * 2) - 1
    left_col_w = (available_w / 2).floor
    middle_sep_x = text_start_x + left_col_w
    right_col_x = middle_sep_x + 1
    right_col_w = (start_x + full_table_w - padding_side) - right_col_x
    right_col_w = [right_col_w - 1, 1].max if scrollbar_visible

    {
      base_data_y: base_data_y,
      max_visible_rows: max_visible_rows,
      hard_boundary_y: hard_boundary_y,
      actual_table_height: actual_table_height,
      scrollbar_visible: scrollbar_visible,
      start_x: start_x,
      padding_side: padding_side,
      text_start_x: text_start_x,
      left_col_w: left_col_w,
      middle_sep_x: middle_sep_x,
      right_col_x: right_col_x,
      right_col_w: right_col_w
    }
  end

  # Clamp the scroll offset and keep the active card inside the visible viewport.
  def update_drill_viewport(max_visible_rows)
    @test_current_idx = @test_current_idx.to_i
    @test_drill_scroll_y ||= 0

    if @test_current_idx >= @test_drill_scroll_y + max_visible_rows
      @test_drill_scroll_y = @test_current_idx - max_visible_rows + 1
    elsif @test_current_idx < @test_drill_scroll_y
      @test_drill_scroll_y = @test_current_idx
    end

    max_offset = [@test_drill_total_lines - max_visible_rows, 0].max
    @test_drill_scroll_y = [[@test_drill_scroll_y, 0].max, max_offset].min
    @drill_viewport_start = @test_drill_scroll_y
    @drill_inner_height = max_visible_rows
  end

  def render_drill_view_header(tui, frame, region, geometry,
                               style_header, style_bracket, style_dimmed)
    start_x = geometry[:start_x]
    text_start_x = geometry[:text_start_x]
    middle_sep_x = geometry[:middle_sep_x]
    term_spans = [tui.span('[', style_bracket), tui.span('Term', style_header), tui.span(']', style_bracket)]
    frame.render_widget(
      tui.paragraph(text: RatatuiRuby::Text::Line.new(spans: term_spans)),
      RatatuiRuby::Layout::Rect.new(text_start_x, region.y, 12, 1)
    )

    mean_label = '[Meaning]'
    mean_spans = [tui.span('[', style_bracket), tui.span('Meaning', style_header), tui.span(']', style_bracket)]
    mean_widget_x = start_x + region.width - mean_label.length - 1
    frame.render_widget(
      tui.paragraph(text: RatatuiRuby::Text::Line.new(spans: mean_spans)),
      RatatuiRuby::Layout::Rect.new(mean_widget_x, region.y, mean_label.length, 1)
    )

    header_sep_char = @show_table_dividers ? '│' : ' '
    frame.render_widget(tui.paragraph(text: header_sep_char, style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(middle_sep_x, region.y, 1, 1))
    frame.render_widget(tui.paragraph(text: '─' * region.width, style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x, region.y + 1, region.width, 1))
  end

  def render_drill_view_borders(tui, frame, region, settings, geometry, style_dimmed)
    middle_sep_x = geometry[:middle_sep_x]
    header_divider_y = region.y + 1
    end_junction_y = @test_show_context ? region.y + region.height - 2 : region.y + region.height

    frame.render_widget(tui.paragraph(text: '├', style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x - 1, header_divider_y, 1, 1))
    frame.render_widget(tui.paragraph(text: '┤', style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x + region.width, header_divider_y, 1, 1))

    left_marker = if @test_show_context
                    '├'
                  else
                    settings.corner == :rounded ? '╰' : '└'
                  end
    right_marker = if @test_show_context
                     '┤'
                   else
                     settings.corner == :rounded ? '╯' : '┘'
                   end
    frame.render_widget(tui.paragraph(text: left_marker, style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x - 1, end_junction_y, 1, 1))
    frame.render_widget(tui.paragraph(text: right_marker, style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x + region.width, end_junction_y, 1, 1))

    top_char, header_char, bottom_char = if @show_table_dividers == true
                                           ['┬', '┼', '┴']
                                         else
                                           ['─', '─', '─']
                                         end
    [[top_char, region.y - 1], [header_char, region.y + 1], [bottom_char, end_junction_y]].each do |char, y|
      frame.render_widget(tui.paragraph(text: char, style: style_dimmed),
                          RatatuiRuby::Layout::Rect.new(middle_sep_x, y, 1, 1))
    end
  end

  def drill_visual_text_with_truncation(value, max_width)
    raw = value.to_s
    return '' if raw.empty?

    field = RatinField.new
    field.text = raw

    # Eerst FriBidi toepassen, zoals in de form-popup.
    visual_text = field.visual_layout.map { |item| item[:char] }.join
    clusters = visual_text.grapheme_clusters

    width = [max_width.to_i, 1].max
    return visual_text if clusters.length <= width

    # Zelfde RTL-detectie en afkaprichting als de form-popup.
    is_rtl = field.direction == :rtl
    available = [width - 1, 0].max

    if is_rtl
      "…#{clusters.last(available).join}"
    else
      "#{clusters.first(available).join}…"
    end
  end

  def render_drill_context_panel(tui, frame, settings, region, geometry,
                                 bg_color, style_dimmed, is_popup_active)
    return unless @test_show_context

    text_start_x = geometry[:text_start_x]
    padding_side = geometry[:padding_side]
    middle_sep_x = geometry[:middle_sep_x]

    bottom_divider_y = region.y + region.height - 2
    context_text_y = bottom_divider_y + 1

    clean_width = ('─' * region.width).gsub(/[\u200E\u200F\u2068\u2069\u2066\u2067]/, '').length
    frame.render_widget(
      tui.paragraph(text: '─' * clean_width, style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(region.x, bottom_divider_y, clean_width, 1)
    )

    frame.render_widget(
      tui.paragraph(text: @show_table_dividers ? '┴' : '─', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(middle_sep_x, bottom_divider_y, 1, 1)
    )

    active_card = @cards_to_test[@test_current_idx]
    context_raw = active_card ? active_card.context.to_s : ''

    context_style = {
      fg: settings.theme_item(:studysessions_context),
      bg: bg_color,
      modifiers: is_popup_active ? [:dim] : []
    }

    label_text = settings.language_string(:study_context).to_s
    total_width = [region.width - (padding_side * 2), 1].max
    label_width = [Unicode::DisplayWidth.of(label_text), total_width - 1].min
    value_width = [total_width - label_width, 1].max

    label_line = RatatuiRuby::Text::Line.new(spans: [
                                               RatatuiRuby::Text::Span.new(content: label_text, style: context_style)
                                             ])

    if label_width.positive?
      frame.render_widget(
        tui.paragraph(text: label_line, alignment: :left, wrap: false),
        RatatuiRuby::Layout::Rect.new(text_start_x, context_text_y, label_width, 1)
      )
    end

    value_alignment = :left

    if context_raw.strip.empty?
      context_value = settings.language_string(:study_context_not_available).to_s
      value_style = {
        fg: settings.theme_item(:studysessions_context),
        bg: bg_color,
        modifiers: is_popup_active ? %i[italic dim] : [:italic]
      }
    else
      context_field = RatinField.new
      context_field.text = context_raw
      visual_clusters = context_field.visual_layout.map { |item| item[:char] }
      visual_width = Unicode::DisplayWidth.of(visual_clusters.join)
      is_rtl = context_field.direction == :rtl
      value_alignment = is_rtl ? :right : :left

      if visual_width > value_width
        target_space = [value_width - 1, 0].max
        retained_clusters = []
        current_width = 0

        if is_rtl
          visual_clusters.reverse_each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_space

            retained_clusters.unshift(cluster)
            current_width += cluster_width
          end
          context_value = "…#{retained_clusters.join}"
        else
          visual_clusters.each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_space

            retained_clusters << cluster
            current_width += cluster_width
          end
          context_value = "#{retained_clusters.join}…"
        end
      else
        context_value = visual_clusters.join
      end

      value_style = {
        fg: settings.theme_item(:studysessions_context),
        bg: bg_color,
        modifiers: is_popup_active ? %i[italic dim] : [:italic]
      }
    end

    value_span = RatatuiRuby::Text::Span.new(
      content: "\u2066#{context_value}\u2069",
      style: value_style
    )
    value_line = RatatuiRuby::Text::Line.new(spans: [value_span])

    return unless context_text_y < region.y + region.height

    frame.render_widget(
      tui.paragraph(text: value_line, alignment: value_alignment, wrap: false),
      RatatuiRuby::Layout::Rect.new(
        text_start_x + label_width, context_text_y, value_width, 1
      )
    )
  end

  def render_drill_card_rows(tui, frame, settings, region,
                             base_data_y, hard_boundary_y, max_visible_rows,
                             start_x, text_start_x, left_col_w, right_col_w,
                             middle_sep_x, right_col_x, style_normal, style_cursor, bg_color)
    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)

    is_latin_or_common = lambda do |char|
      char =~ /\A[\p{Latin}0-9\s[:punct:]]\z/
    end

    @cards_to_test.each_with_index do |card, idx|
      next if idx < @drill_viewport_start

      rendered_row_idx = idx - @drill_viewport_start
      current_row_y = base_data_y + rendered_row_idx
      break if rendered_row_idx >= max_visible_rows
      break if current_row_y >= hard_boundary_y

      # De formatteringsfuncties voeren zelf de FriBidi-layout uit.
      term_str = card.term.to_s
      mean_str = card.meaning.to_s

      card_direction = drill_card_direction(card, idx, settings.study_strategy)
      is_question_a_term = card_direction == :front
      is_active_row = idx == @test_current_idx
      row_style = is_active_row ? style_cursor : style_normal

      left_cell_text = ''
      right_cell_text = ''
      if is_question_a_term
        left_cell_text = term_str
        right_cell_text = mean_str if is_active_row && @test_show_meaning
      else
        right_cell_text = mean_str
        left_cell_text = term_str if is_active_row && @test_show_meaning
      end

      final_left_str = format_drill_left_cell(left_cell_text, left_col_w)
      right_text_max_w = [right_col_w, 1].max
      final_right_str = format_drill_right_cell(right_cell_text, right_text_max_w)

      # Teken de actieve cursorbalk op de achtergrond
      if is_active_row
        background_bar = ' ' * region.width
        frame.render_widget(
          tui.paragraph(text: background_bar, style: style_cursor),
          RatatuiRuby::Layout::Rect.new(start_x, current_row_y, region.width, 1)
        )
      end

      # =========================================================================
      # 🌲 LINKERKOLOM: SOLID PARAGRAPH RENDERING (POPUP & TABLE PARITY)
      # =========================================================================
      # Send the string to the terminal in one operation within its Rect bounds.
      left_line = RatatuiRuby::Text::Line.new(spans: [
                                                RatatuiRuby::Text::Span.new(content: final_left_str, style: row_style)
                                              ])

      if is_handwritten && final_left_str.chars.any? { |c| !is_latin_or_common.call(c) }
        left_line.spans.first.style[:modifiers] = Array(left_line.spans.first.style[:modifiers]) | [:italic]
      end

      frame.render_widget(
        RatatuiRuby::Widgets::Paragraph.new(text: left_line, alignment: :right,
                                            wrap: false),
        RatatuiRuby::Layout::Rect.new(text_start_x, current_row_y, left_col_w, 1)
      )

      # Draw the column divider, keeping it perfectly aligned.
      if is_active_row && @show_table_dividers == true
        frame.render_widget(
          tui.paragraph(text: '│', style: { fg: settings.theme_item(:window_border), bg: style_cursor[:bg] }),
          RatatuiRuby::Layout::Rect.new(middle_sep_x, current_row_y, 1, 1)
        )
      end

      # =========================================================================
      # 🌲 RECHTERKOLOM: SOLID PARAGRAPH RENDERING (POPUP & TABLE PARITY)
      # =========================================================================
      right_line = RatatuiRuby::Text::Line.new(spans: [
                                                 RatatuiRuby::Text::Span.new(content: final_right_str,
                                                                             style: row_style)
                                               ])

      if is_handwritten && final_right_str.chars.any? { |c| !is_latin_or_common.call(c) }
        right_line.spans.first.style[:modifiers] = Array(right_line.spans.first.style[:modifiers]) | [:italic]
      end

      frame.render_widget(
        RatatuiRuby::Widgets::Paragraph.new(text: right_line, alignment: :left,
                                            wrap: false),
        RatatuiRuby::Layout::Rect.new(right_col_x + 1, current_row_y, right_text_max_w, 1)
      )
    end
  end

  # Build all row/header styles in one place so popup dimming stays consistent.
  def drill_view_styles(settings, bg_color, is_popup_active)
    popup_modifiers = is_popup_active ? { modifiers: [:dim] } : {}

    {
      header: { fg: settings.theme_item(:table_header_text), bg: bg_color }.merge(popup_modifiers),
      bracket: { fg: settings.theme_item(:table_header_text), bg: bg_color }.merge(popup_modifiers),
      dimmed: {
        fg: settings.theme_item(:window_border),
        bg: bg_color,
        modifiers: is_popup_active ? [:dim] : []
      },
      normal: { fg: settings.theme_item(:foreground), bg: bg_color }.merge(popup_modifiers),
      cursor: {
        fg: settings.theme_item(:selected_row_foreground),
        bg: settings.theme_item(:selected_row_background)
      }.merge(popup_modifiers)
    }
  end

  def drill_card_direction(card, index, strategy)
    case strategy || :fronts_random
    when :backs_random
      :back
    when :alternately_fronts_and_backs_random
      index.even? ? :front : :back
    when :everything_random
      card.respond_to?(:id) && card.id.to_i.odd? ? :back : :front
    else
      :front
    end
  end

  def format_drill_left_cell(value, column_width)
    safe_width = [column_width.to_i - 1, 0].max
    raw = value.to_s.gsub(/[\u2066\u2069]/, '')
    return ' ' * [column_width.to_i, 0].max if raw.empty?

    field = RatinField.new
    field.text = raw
    visual_clusters = field.visual_layout.map { |item| item[:char] }
    visual_width = Unicode::DisplayWidth.of(visual_clusters.join)
    is_rtl = field.direction == :rtl

    if visual_width > safe_width
      target_space = [safe_width - 1, 0].max
      retained_clusters = []
      current_width = 0

      if is_rtl
        visual_clusters.reverse_each do |cluster|
          cluster_width = Unicode::DisplayWidth.of(cluster)
          break if current_width + cluster_width > target_space

          retained_clusters.unshift(cluster)
          current_width += cluster_width
        end
        display_text = "…#{retained_clusters.join}"
      else
        visual_clusters.each do |cluster|
          cluster_width = Unicode::DisplayWidth.of(cluster)
          break if current_width + cluster_width > target_space

          retained_clusters << cluster
          current_width += cluster_width
        end
        display_text = "#{retained_clusters.join}…"
      end
    else
      display_text = visual_clusters.join
    end

    display_text = '' if safe_width.zero?
    "\u2066#{display_text}\u2069 "
  end

  def format_drill_right_cell(value, width)
    raw = value.to_s.gsub(/[\u2066\u2069]/, '')
    target_width = [width.to_i, 0].max
    return '' if target_width.zero? || raw.empty?

    field = RatinField.new
    field.text = raw
    visual_clusters = field.visual_layout.map { |item| item[:char] }
    visual_width = Unicode::DisplayWidth.of(visual_clusters.join)
    is_rtl = field.direction == :rtl

    if visual_width > target_width
      target_space = [target_width - 1, 0].max
      retained_clusters = []
      current_width = 0

      if is_rtl
        visual_clusters.reverse_each do |cluster|
          cluster_width = Unicode::DisplayWidth.of(cluster)
          break if current_width + cluster_width > target_space

          retained_clusters.unshift(cluster)
          current_width += cluster_width
        end
        display_text = "…#{retained_clusters.join}"
      else
        visual_clusters.each do |cluster|
          cluster_width = Unicode::DisplayWidth.of(cluster)
          break if current_width + cluster_width > target_space

          retained_clusters << cluster
          current_width += cluster_width
        end
        display_text = "#{retained_clusters.join}…"
      end
    else
      display_text = visual_clusters.join
    end

    "\u2066#{display_text}\u2069"
  end

  # A scrollbar is useful only when the card list exceeds the visible viewport.
  def drill_scrollbar_needed?(total_lines_count, visible_rows)
    total_lines_count.to_i > visible_rows.to_i
  end

  # Render the scrollbar using the same viewport geometry as the card list.
  # position is the viewport scroll offset, not the selected card index.
  def render_drill_scrollbar(
    tui,
    frame,
    outer_region,
    total_lines_count,
    current_cursor_index,
    visible_rows,
    position: nil,
    hard_boundary_y: nil,
    visible_height: nil
  )
    settings = AppConfig.settings

    local_base_data_y = outer_region.y + 2

    local_hard_boundary_y = hard_boundary_y || (
      if @test_show_context
        outer_region.y + outer_region.height - 2
      else
        outer_region.y + outer_region.height
      end
    )

    physical_height = local_hard_boundary_y - local_base_data_y

    visible_height ||= physical_height
    return if visible_height <= 0

    visible_rows = visible_rows.to_i
    visible_rows = visible_height if visible_rows <= 0
    visible_rows = [visible_rows, 1].max

    return unless drill_scrollbar_needed?(
      total_lines_count,
      visible_rows
    )

    visually_active = @active_focus == :study_focus_mode ||
                      @active_focus == :drill ||
                      @active_focus == :two_of_a_kind

    border_color = settings.theme_item(
      visually_active ? :window_border : :foreground
    )

    scrollbar_style = {
      fg: border_color,
      modifiers: visually_active ? [] : [:dim]
    }

    position = position.nil? ? current_cursor_index : position

    position = [
      [position.to_i, 0].max,
      total_lines_count.to_i - 1
    ].min

    scrollbar_state = RatatuiRuby::ScrollbarState.new(total_lines_count)
    scrollbar_state.viewport_content_length = visible_rows
    scrollbar_state.position = position

    scrollbar_widget = tui.scrollbar(
      content_length: total_lines_count,
      position: position,
      orientation: :vertical_right,
      thumb_symbol: '┆',
      track_symbol: '│',
      begin_symbol: position.zero? ? '┆' : '│',
      end_symbol: position == total_lines_count - 1 ? '┆' : '│',
      thumb_style: tui.style(scrollbar_style),
      track_style: tui.style(scrollbar_style)
    )

    scrollbar_region = RatatuiRuby::Layout::Rect.new(
      outer_region.x,
      local_base_data_y,
      outer_region.width + 1,
      visible_height
    )

    frame.render_stateful_widget(
      scrollbar_widget,
      scrollbar_region,
      scrollbar_state
    )
  end

  def drill_text_alignment(value)
    raw = value.to_s.gsub(/[\u2066\u2069]/, '')
    return :left if raw.empty?

    field = RatinField.new
    field.text = raw
    field.direction == :rtl ? :right : :left
  end
end
