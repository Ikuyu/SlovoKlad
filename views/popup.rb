require_relative '../lib/ratin_field'

class PopupView
  def self.draw(frame, popup_data, tui = nil)
    return if popup_data.nil?

    if popup_data[:type] == :form
      draw_form_popup(frame, popup_data)
    else
      draw_text_popup(frame, popup_data, tui)
    end
  end

  def self.wrap_popup_row(row, width, allow_ellipsis: true)
    row = row.to_s.gsub(/[\u2066\u2069]/, '')
    width = [width.to_i, 1].max

    return [''] if row.empty?

    clean_row = row.strip.gsub(/[\u200E\u200F\u2068\u2069]/, '')
    first_alpha = clean_row.chars.find { |c| c =~ /[[:alpha:]]/ }
    is_rtl_row = false
    if first_alpha
      cp = first_alpha.ord
      is_rtl_row = (0x0590..0x05FF).include?(cp) || (0x0600..0x06FF).include?(cp)
    end

    clusters = row.grapheme_clusters

    if Unicode::DisplayWidth.of(row) <= width
      tmp_field = RatinField.new
      tmp_field.text = row
      visual_text = tmp_field.visual_layout.map { |item| item[:char] }.join
      return ["\u2066#{visual_text}\u2069"]
    end

    colon_position = row.rindex(':')
    indent = colon_position ? colon_position + 2 : 0

    result = []
    remaining_clusters = clusters
    first_line = true

    while remaining_clusters.length > 0
      prefix_spaces = first_line ? '' : (' ' * indent)
      available_width = [width - prefix_spaces.length, 1].max

      current_width = 0
      take_count = 0
      remaining_clusters.each do |cluster|
        w = Unicode::DisplayWidth.of(cluster)
        break if current_width + w > available_width

        current_width += w
        take_count += 1
      end

      if take_count.zero?
        if width == 1
          result << (allow_ellipsis ? '…' : '')
          break
        end
        take_count = 1
      end

      if take_count >= remaining_clusters.length
        logische_regel = remaining_clusters.join
        tmp_field = RatinField.new
        tmp_field.text = logische_regel
        visual_text = tmp_field.visual_layout.map { |item| item[:char] }.join
        result << "#{prefix_spaces}\u2066#{visual_text}\u2069"
        break
      end

      target_space = [available_width - 1, 0].max
      candidate_clusters = remaining_clusters[0, take_count]
      break_position = candidate_clusters.rindex { |c| c =~ /\s/ }

      cut_position = if break_position && break_position.positive?
                       break_position + 1
                     else
                       take_count
                     end

      current_line_clusters = remaining_clusters[0, cut_position]

      line_width = 0
      final_clusters = []
      current_line_clusters.each do |cluster|
        w = Unicode::DisplayWidth.of(cluster)
        break if line_width + w > target_space

        final_clusters << cluster
        line_width += w
      end

      padding_needed = target_space - line_width

      # 🎯 GEÜPDATE: Plaats de '…' alleen als allow_ellipsis true is!
      ellipsis_char = allow_ellipsis ? '…' : ''

      logische_regel = if is_rtl_row
                         ' ' * padding_needed + ellipsis_char + final_clusters.join
                       else
                         final_clusters.join + ' ' * padding_needed + ellipsis_char
                       end

      tmp_field = RatinField.new
      tmp_field.text = logische_regel
      visual_text = tmp_field.visual_layout.map { |item| item[:char] }.join
      result << "#{prefix_spaces}\u2066#{visual_text}\u2069"

      remaining_clusters = remaining_clusters[cut_position..] || []
      first_line = false
    end

    result
  end

  # Bepaal de uitlijning aan de hand van de eerste sterke letter.
  def self.input_field_alignment(field_obj)
    text = field_obj.respond_to?(:text) ? field_obj.text.to_s : ''

    return :left if text.empty?

    direction =
      if field_obj.respond_to?(:direction)
        field_obj.direction.to_s.downcase.to_sym
      else
        :ltr
      end

    %i[rtl right_to_left].include?(direction) ? :right : :left
  end

  def self.draw_text_popup(frame, popup_data, tui)
    footer_key =
      popup_data[:footer_key] ||
      case popup_data[:type]
      when :confirm
        :alert_cancel_ok
      else
        :alert_ok
      end

    footer = AppConfig.settings.language_string(footer_key)

    cleaned_message = popup_data[:message].to_s
    alignment = popup_data[:alignment] || :center

    # ============================================================
    # HELP POPUP
    # ============================================================
    if popup_data[:type] == :help
      message_rows = cleaned_message.split("\n")
      message_rows = [''] if message_rows.empty?
      footer_rows = [footer]

      layout = calculate_help_scroll_layout(
        frame,
        popup_data,
        message_rows,
        footer_rows
      )

      dimensions = layout[:dimensions]
      message_visual_rows = layout[:message_visual_rows]
      scrollable_height = layout[:scrollable_height]
      max_scroll = layout[:max_scroll]
      show_scrollbar = layout[:show_scrollbar]
      show_more = layout[:show_more]

      scroll_y = [
        [popup_data[:scroll_y].to_i, 0].max,
        max_scroll
      ].min

      popup_data[:scroll_y] = scroll_y

      box_height = dimensions[:full_height].to_i

      popup_area = calculate_centered_rect(
        frame.area,
        dimensions[:full_width],
        box_height
      )

      contents_block = build_text_popup_block(popup_data)

      frame.render_widget(
        RatatuiRuby::Widgets::Clear.new,
        popup_area
      )

      frame.render_widget(
        contents_block,
        popup_area
      )

      inner_area = contents_block.inner(popup_area)
      scrollbar_width = show_scrollbar ? 1 : 0

      text_area = RatatuiRuby::Layout::Rect.new(
        inner_area.x,
        inner_area.y,
        [inner_area.width - scrollbar_width, 1].max,
        inner_area.height
      )

      footer_visual_rows = footer_rows.map do |line|
        {
          text: line,
          footer: true
        }
      end

      render_text_popup_content(
        frame,
        text_area,
        message_visual_rows,
        alignment,
        scroll_y,
        popup_data,
        footer_visual_rows,
        scrollable_height,
        max_scroll,
        show_more
      )

      render_text_popup_scrollbar(
        frame,
        popup_area,
        scrollable_height,
        message_visual_rows.length,
        show_scrollbar,
        scroll_y,
        max_scroll
      )

      return
    end

    # ============================================================
    # NIET-HELP POPUPS
    # ============================================================
    message_rows = cleaned_message.split("\n", -1)
    rows = message_rows + [footer]

    dimensions = calculate_text_popup_dimensions(
      frame,
      popup_data,
      rows,
      reserve_scrollbar: false
    )

    visual_rows = build_text_popup_visual_rows(
      rows,
      dimensions[:text_width]
    )

    visible_height_inside = dimensions[:visible_height_inside]

    popup_area = calculate_centered_rect(
      frame.area,
      dimensions[:full_width],
      dimensions[:full_height]
    )

    contents_block = build_form_popup_block(popup_data)

    frame.render_widget(
      RatatuiRuby::Widgets::Clear.new,
      popup_area
    )

    frame.render_widget(
      contents_block,
      popup_area
    )

    inner_area = contents_block.inner(popup_area)

    text_area = RatatuiRuby::Layout::Rect.new(
      inner_area.x,
      inner_area.y,
      inner_area.width,
      inner_area.height
    )

    message_visual_rows = visual_rows.reject { |row| row[:footer] }
    footer_visual_rows  = visual_rows.select { |row| row[:footer] }

    render_text_popup_content(
      frame,
      text_area,
      message_visual_rows,
      alignment,
      0,
      popup_data,
      footer_visual_rows,
      visible_height_inside,
      0,
      false
    )
  end

  def self.calculate_text_popup_dimensions(
    frame,
    popup_data,
    rows,
    reserve_scrollbar: false
  )
    longest_line_length = rows.map do |row|
      Unicode::DisplayWidth.of(row.to_s.gsub(/[\u200E\u200F\u2066-\u2069]/, ''))
    end.max || 1

    required_width = longest_line_length + 4

    full_width = [
      required_width,
      66,
      frame.area.width - 2
    ].min

    scrollbar_width = reserve_scrollbar ? 1 : 0

    text_width = [
      full_width - 4 - scrollbar_width,
      1
    ].max

    total_visual_lines = rows.sum do |row|
      wrap_popup_row(row, text_width).length
    end

    needed_box_height = total_visual_lines + 2

    max_terminal_box_height = [
      frame.area.height - 4,
      5
    ].max

    full_height =
      if popup_data[:type] == :help
        [
          [needed_box_height, max_terminal_box_height].min,
          5
        ].max
      else
        [needed_box_height, 5].max
      end

    visible_height_inside = [
      full_height - 2,
      1
    ].max

    {
      full_width: full_width,
      full_height: full_height,
      text_width: text_width,
      visible_height_inside: visible_height_inside,
      scrollbar_width: scrollbar_width
    }
  end

  def self.build_text_popup_visual_rows(rows, text_width)
    visual_rows = []

    rows.each_with_index do |row, index|
      wrapped_rows = wrap_popup_row(row, text_width, allow_ellipsis: false)

      wrapped_rows.each do |wrapped_row|
        visual_rows << {
          text: wrapped_row,
          footer: index == rows.length - 1
        }
      end
    end

    visual_rows
  end

  def self.build_text_popup_block(popup_data)
    RatatuiRuby::Widgets::Block.new(
      title: popup_data[:title],
      title_style: {
        fg: AppConfig.settings.theme_item(:window_title),
        bg: AppConfig.settings.theme_item(:background)
      },
      border_style: {
        fg: AppConfig.settings.theme_item(:window_border),
        bg: AppConfig.settings.theme_item(:background)
      },
      style: {
        bg: AppConfig.settings.theme_item(:background)
      },
      borders: [:all],
      border_type: AppConfig.settings.corner
    )
  end

  def self.calculate_help_scroll_layout(frame, popup_data, message_rows, footer_rows)
    footer_height = footer_rows.length

    # Include the blank line between the content and footer
    # mee in de berekening van de benodigde popuphoogte.
    layout_rows = message_rows + [''] + footer_rows

    # First determine the available space without a scrollbar.
    dimensions = calculate_text_popup_dimensions(
      frame,
      popup_data,
      layout_rows,
      reserve_scrollbar: false
    )

    message_visual_rows = build_text_popup_visual_rows(
      message_rows,
      dimensions[:text_width]
    )

    visible_height_inside = dimensions[:visible_height_inside]

    # Non-scrollable help screens keep one blank line
    # tussen de inhoud en de vaste footer.
    height_without_more = [
      visible_height_inside - footer_height - 1,
      1
    ].max

    needs_scroll = message_visual_rows.length > height_without_more
    show_more = needs_scroll

    if needs_scroll
      # The scrollbar narrows the text area, so wrap the text again.
      dimensions = calculate_text_popup_dimensions(
        frame,
        popup_data,
        layout_rows,
        reserve_scrollbar: true
      )

      message_visual_rows = build_text_popup_visual_rows(
        message_rows,
        dimensions[:text_width]
      )

      visible_height_inside = dimensions[:visible_height_inside]

    # Text rows + indicator + one blank line + fixed footer.
      scrollable_height = [
        visible_height_inside - footer_height - 2,
        1
      ].max
    else
      scrollable_height = height_without_more
    end

    # max_scroll gebruikt uitsluitend echte tekstregels.
    max_scroll = [
      message_visual_rows.length - scrollable_height,
      0
    ].max

    {
      dimensions: dimensions,
      message_visual_rows: message_visual_rows,
      visible_height_inside: visible_height_inside,
      footer_height: footer_height,
      scrollable_height: scrollable_height,
      max_scroll: max_scroll,
      show_scrollbar: max_scroll.positive?,
      show_more: show_more && max_scroll.positive?
    }
  end

  def self.render_text_popup_content(
    frame,
    text_area,
    visual_rows,
    alignment,
    scroll_y,
    popup_data = nil,
    footer_visual_rows = [],
    scrollable_height = nil,
    max_scroll = 0,
    show_more = false
  )
    settings_lines = popup_data && popup_data[:settings_lines]

    lines = visual_rows.map do |visual_row|
      # 🎯 FIX: Niet meer opnieuw door visual_text halen, dat is al gebeurd in wrap_popup_row!
      row = visual_row[:text]

      if row.empty?
        RatatuiRuby::Text::Line.new(spans: [])
      else
        span = RatatuiRuby::Text::Span.new(
          content: row,
          style: {
            fg: AppConfig.settings.theme_item(:foreground),
            bg: AppConfig.settings.theme_item(:background)
          }
        )

        RatatuiRuby::Text::Line.new(
          spans: [span]
        )
      end
    end

    footer_lines = footer_visual_rows.map do |visual_row|
      row = visual_row[:text].to_s

      span = RatatuiRuby::Text::Span.new(
        content: row,
        style: {
          fg: AppConfig.settings.theme_item(:foreground),
          bg: AppConfig.settings.theme_item(:background),
          modifiers: [:dim]
        }
      )

      RatatuiRuby::Text::Line.new(
        spans: [span]
      )
    end

    content_width = [text_area.width - 2, 1].max

    block_width = 26
    left_padding =
      if settings_lines
        [(content_width - block_width) / 2, 0].max
      else
        0
      end

    text_x = text_area.x + 1 + left_padding

    text_width = [
      text_area.width - 2 - left_padding,
      1
    ].max

    # ============================================================
    # HELP
    # ============================================================
    if popup_data && popup_data[:type] == :help
      actual_scrollable_height = [scrollable_height.to_i, 1].max

      scrollable_region = RatatuiRuby::Layout::Rect.new(
        text_x,
        text_area.y,
        text_width,
        actual_scrollable_height
      )

      paragraph = RatatuiRuby::Widgets::Paragraph.new(
        text: lines,
        alignment: settings_lines ? :left : alignment,
        wrap: false,
        scroll: [scroll_y.to_i, 0]
      )

      frame.render_widget(paragraph, scrollable_region)

      status_y = text_area.y + actual_scrollable_height

      if show_more && max_scroll.to_i.positive?
        percentage = if scroll_y.to_i >= max_scroll.to_i
                       100
                     else
                       ((scroll_y.to_f / max_scroll.to_f) * 100).round
                     end

        percentage = [[percentage, 0].max, 100].min
        more_text = "   --More--(#{percentage}%)"

        more_span = RatatuiRuby::Text::Span.new(
          content: more_text,
          style: {
            fg: AppConfig.settings.theme_item(:foreground),
            bg: AppConfig.settings.theme_item(:background)
          }
        )

        more_line = RatatuiRuby::Text::Line.new(spans: [more_span])

        more_region = RatatuiRuby::Layout::Rect.new(text_x, status_y, text_width, 1)
        frame.render_widget(RatatuiRuby::Widgets::Paragraph.new(text: [more_line], alignment: :left, wrap: false),
                            more_region)
      end

      fixed_footer_y = text_area.bottom - footer_lines.length

      footer_region = RatatuiRuby::Layout::Rect.new(
        text_x,
        fixed_footer_y,
        text_width,
        footer_lines.length
      )

      footer_paragraph = RatatuiRuby::Widgets::Paragraph.new(text: footer_lines, alignment: :center, wrap: false)
      frame.render_widget(footer_paragraph, footer_region)
      return
    end

    # ============================================================
    # NIET-HELP POPUPS
    # ============================================================
    paragraph = RatatuiRuby::Widgets::Paragraph.new(
      text: lines,
      alignment: settings_lines ? :left : alignment,
      wrap: false,
      scroll: [0, 0]
    )

    frame.render_widget(
      paragraph,
      text_area
    )

    if footer_lines.any?
      footer_region = RatatuiRuby::Layout::Rect.new(
        text_x,
        text_area.y + text_area.height - footer_lines.length,
        text_width,
        footer_lines.length
      )

      footer_paragraph = RatatuiRuby::Widgets::Paragraph.new(
        text: footer_lines,
        alignment: :center,
        wrap: false
      )

      frame.render_widget(
        footer_paragraph,
        footer_region
      )
    end

    nil
  end

  def self.calculate_help_scroll_metrics(
    frame,
    popup_data,
    rows,
    reserve_scrollbar: nil
  )
    terminal_width = frame.area.width
    terminal_height = frame.area.height

    longest_line_length = rows.map do |row|
      Unicode::DisplayWidth.of(row.to_s.gsub(/[\u200E\u200F\u2066-\u2069]/, ''))
    end.max || 1

    required_width = longest_line_length + 4

    full_width = [
      required_width,
      66,
      terminal_width - 2
    ].min

    # First determine whether scrolling is needed at all, without a scrollbar.
    scrollbar_width = 0

    text_width = [
      full_width - 4 - scrollbar_width,
      1
    ].max

    visual_rows = build_text_popup_visual_rows(
      rows,
      text_width
    )

    footer_visual_rows =
      if popup_data[:type] == :help
        visual_rows.select { |row| row[:footer] }
      else
        []
      end

    scrollable_visual_rows =
      if popup_data[:type] == :help
        visual_rows.reject { |row| row[:footer] }
      else
        visual_rows
      end

    needed_box_height =
      visual_rows.length + 2

    max_terminal_box_height = [
      terminal_height - 4,
      5
    ].max

    full_height =
      if popup_data[:type] == :help
        calculated =
          if needed_box_height <= max_terminal_box_height
            needed_box_height
          else
            max_terminal_box_height
          end

        [calculated, 5].max
      else
        [needed_box_height, 5].max
      end

    visible_height_inside = [
      full_height - 2,
      1
    ].max

    footer_height =
      if popup_data[:type] == :help
        footer_visual_rows.length
      else
        0
      end

    more_height =
      if popup_data[:type] == :help &&
         scrollable_visual_rows.length > 0
        2
      else
        0
      end

    scrollable_height = [
      visible_height_inside -
        footer_height -
        more_height,
      1
    ].max

    max_scroll = [
      scrollable_visual_rows.length -
        scrollable_height,
      0
    ].max

    show_scrollbar =
      popup_data[:type] == :help &&
      max_scroll > 0

    # If a scrollbar is needed, the text column becomes one
    # character narrower, which may change wrapping.
    if show_scrollbar
      scrollbar_width = 1

      text_width = [
        full_width - 4 - scrollbar_width,
        1
      ].max

      visual_rows = build_text_popup_visual_rows(
        rows,
        text_width
      )

      footer_visual_rows =
        visual_rows.select { |row| row[:footer] }

      scrollable_visual_rows =
        visual_rows.reject { |row| row[:footer] }

      needed_box_height =
        visual_rows.length + 2

      full_height =
        if popup_data[:type] == :help
          calculated =
            if needed_box_height <= max_terminal_box_height
              needed_box_height
            else
              max_terminal_box_height
            end

          [calculated, 5].max
        else
          [needed_box_height, 5].max
        end

      visible_height_inside = [
        full_height - 2,
        1
      ].max

      footer_height =
        footer_visual_rows.length

      scrollable_height = [
        visible_height_inside -
          footer_height -
          2,
        1
      ].max

      max_scroll = [
        scrollable_visual_rows.length -
          scrollable_height,
        0
      ].max
    end

    {
      full_width: full_width,
      full_height: full_height,
      text_width: text_width,
      visible_height_inside: visible_height_inside,
      scrollbar_width: scrollbar_width,
      visual_rows: visual_rows,
      footer_visual_rows: footer_visual_rows,
      scrollable_visual_rows: scrollable_visual_rows,
      footer_height: footer_height,
      scrollable_height: scrollable_height,
      max_scroll: max_scroll,
      show_scrollbar: show_scrollbar
    }
  end

  def self.render_text_popup_scrollbar(
    frame,
    popup_area,
    visible_height_inside,
    total_visual_lines,
    show_scrollbar,
    scroll_y,
    max_scroll
  )
    return unless show_scrollbar
    return if total_visual_lines <= visible_height_inside

    active_border_color =
      AppConfig.settings.theme_item(:window_border)

    background_color =
      AppConfig.settings.theme_item(:background)

    full_height = popup_area.height.to_i
    rail_height = [full_height - 2, 1].max

    # De thumb kan nooit hoger zijn dan de rail zelf.
    calculated_thumb_height = (
      (visible_height_inside.to_f / total_visual_lines) * rail_height
    ).round

    thumb_height = [
      [calculated_thumb_height, 1].max,
      rail_height
    ].min

    scroll_ratio =
      if max_scroll.to_i.positive?
        scroll_y.to_f / max_scroll.to_f
      else
        0.0
      end

    available_track_space = [
      rail_height - thumb_height,
      0
    ].max

    thumb_start_y = (
      scroll_ratio * available_track_space
    ).round

    scrollbar_lines = rail_height.times.map do |current_line_idx|
      thumb =
        current_line_idx >= thumb_start_y &&
        current_line_idx < thumb_start_y + thumb_height

      symbol = thumb ? '┆' : '│'

      span = RatatuiRuby::Text::Span.new(
        content: symbol,
        style: {
          fg: active_border_color,
          bg: background_color
        }
      )

      RatatuiRuby::Text::Line.new(spans: [span])
    end

    # BELANGRIJK:
    # popup_area.x + popup_area.width - 1 is de buitenste rechterborder.
    # Therefore, place the scrollbar one column to the left, inside the border.
    scrollbar_region = RatatuiRuby::Layout::Rect.new(
      popup_area.x + popup_area.width - 1,
      popup_area.y + 1,
      1,
      rail_height
    )

    scrollbar_paragraph = RatatuiRuby::Widgets::Paragraph.new(
      text: scrollbar_lines,
      alignment: :left
    )

    frame.render_widget(
      scrollbar_paragraph,
      scrollbar_region
    )
  end

  def self.draw_form_popup(frame, popup_data)
    settings = AppConfig.settings
    fields = popup_data[:fields] || {}
    field_keys = fields.keys

    if field_keys.include?(:query)
      is_replace = field_keys.include?(:replace)
      has_all_checkbox = field_keys.include?(:global) # Gecreëerd door de tabel-focus

      popup_data[:title] = if has_all_checkbox
                             is_replace ? settings.language_string(:search_and_replace_title_table) : settings.language_string(:search_title_table)
                           else
                             is_replace ? settings.language_string(:search_and_replace_title_tree) : settings.language_string(:search_title_tree)
                           end # settings.language_string(:search_and_replace_title_tree)
    end

    focus = popup_data[:form_focus] || field_keys.first

    is_search_or_replace = field_keys.include?(:query)
    has_replace          = field_keys.include?(:replace)
    has_name_field       = field_keys.include?(:name)

    popup_height = calculate_form_popup_height(field_keys, is_search_or_replace, has_replace, has_name_field)
    popup_area = calculate_centered_rect(frame.area, 70, popup_height)
    contents_block = build_form_popup_block(popup_data)

    frame.render_widget(RatatuiRuby::Widgets::Clear.new, popup_area)
    frame.render_widget(contents_block, popup_area)

    inner_area = contents_block.inner(popup_area)
    content_area = calculate_form_popup_content_area(inner_area)
    active_text = settings.theme_item(:foreground)

    hint_chunk =
      if is_search_or_replace
        render_search_replace_form(frame, content_area, fields, focus, has_replace, active_text)
      else
        render_standard_form(frame, content_area, fields, field_keys, focus, active_text)
      end
    render_form_popup_hint(frame, hint_chunk)
  end

  def self.calculate_form_popup_height(field_keys, is_search_or_replace, has_replace, has_name_field)
    if is_search_or_replace
      has_replace ? 8 : 7
    elsif has_name_field
      [field_keys.length + 3, 5].max
    else
      [field_keys.length + 3, 7].max
    end
  end

  def self.build_form_popup_block(popup_data)
    RatatuiRuby::Widgets::Block.new(
      title: " #{popup_data[:title]} ",
      title_style: { fg: AppConfig.settings.theme_item(:window_title),
                     bg: AppConfig.settings.theme_item(:background) },
      border_style: { fg: AppConfig.settings.theme_item(:window_border),
                      bg: AppConfig.settings.theme_item(:background) },
      style: { bg: AppConfig.settings.theme_item(:background) },
      borders: [:all],
      border_type: AppConfig.settings.corner
    )
  end

  def self.calculate_form_popup_content_area(inner_area)
    padded_chunks = RatatuiRuby::Layout::Layout.split(
      inner_area, direction: :horizontal,
                  constraints: [
                    RatatuiRuby::Layout::Constraint.length(1),
                    RatatuiRuby::Layout::Constraint.min(1),
                    RatatuiRuby::Layout::Constraint.length(1)
                  ]
    )
    padded_chunks[1]
  end

  def self.render_search_replace_form(frame, content_area, fields, focus, has_replace, active_text)
    constraints = []
    constraints << RatatuiRuby::Layout::Constraint.length(1) # Query veld
    constraints << RatatuiRuby::Layout::Constraint.length(1) if has_replace # Replace veld
    constraints << RatatuiRuby::Layout::Constraint.length(1) # Lege regel witruimte
    constraints << RatatuiRuby::Layout::Constraint.length(1) # Checkboxes rij
    constraints << RatatuiRuby::Layout::Constraint.length(1) # Witruimte voor de hint
    constraints << RatatuiRuby::Layout::Constraint.length(1) # Hint tekstregel

    form_chunks = RatatuiRuby::Layout::Layout.split(content_area, direction: :vertical, constraints: constraints)
    current_chunk_idx = 0

    render_single_input_field(frame, form_chunks[current_chunk_idx], fields[:query], :query == focus)
    current_chunk_idx += 1

    if has_replace
      render_single_input_field(frame, form_chunks[current_chunk_idx], fields[:replace], :replace == focus)
      current_chunk_idx += 1
    end

    current_chunk_idx += 1

    if fields.key?(:case_sensitive) || fields.key?(:regex) || fields.key?(:global)
      current_chunk_idx = render_search_replace_checkboxes(frame, form_chunks, current_chunk_idx, fields, focus,
                                                           active_text)
    end

    current_chunk_idx += 1
    form_chunks[current_chunk_idx]
  end

  def self.render_search_replace_checkboxes(frame, form_chunks, current_chunk_idx, fields, focus, active_text)
    settings = AppConfig.settings

    lang_case   = settings.language_string(:search_case_sensitive)
    lang_regex  = settings.language_string(:search_regex)
    lang_global = settings.language_string(:search_all)

    horizontal_chunks = RatatuiRuby::Layout::Layout.split(
      form_chunks[current_chunk_idx], direction: :horizontal,
                                      constraints: [
                                        RatatuiRuby::Layout::Constraint.length(4 + lang_case.length),
                                        RatatuiRuby::Layout::Constraint.length(2), # Spacertje 1
                                        RatatuiRuby::Layout::Constraint.length(4 + lang_regex.length),
                                        RatatuiRuby::Layout::Constraint.length(2), # Spacertje 2
                                        RatatuiRuby::Layout::Constraint.length(4 + lang_global.length),
                                        RatatuiRuby::Layout::Constraint.min(1)     # Restant opvulling
                                      ]
    )
    current_chunk_idx += 1

    checkbox_definitions = {
      case_sensitive: { idx: 0, label: lang_case },
      regex: { idx: 2, label: lang_regex },
      global: { idx: 4, label: lang_global } # <-- DE NIEUWE KOLOM-LINK!
    }

    checkbox_definitions.each do |f_key, info|
      next unless (field_obj = fields[f_key])

      is_focused  = (f_key == focus)
      char_inside = field_obj.checked ? 'x' : ' '
      spans       = []

      if is_focused
        # Selected state (blinking dashboard cursor colors).
        spans << RatatuiRuby::Text::Span.new(content: "[#{char_inside}]",
                                             style: { fg: settings.theme_item(:cursor_text),
                                                      bg: settings.theme_item(:cursor_color),
                                                      modifiers: [] })
        spans << RatatuiRuby::Text::Span.new(content: " #{info[:label]}",
                                             style: { fg: active_text,
                                                      bg: settings.theme_item(:background),
                                                      modifiers: [] })
      else
        # Ruststand
        spans << RatatuiRuby::Text::Span.new(content: "[#{char_inside}] #{info[:label]}",
                                             style: { fg: active_text,
                                                      bg: settings.theme_item(:background) })
      end

      frame.render_widget(
        RatatuiRuby::Widgets::Paragraph.new(text: RatatuiRuby::Text::Line.new(spans: spans),
                                            alignment: :left), horizontal_chunks[info[:idx]]
      )
    end

    current_chunk_idx
  end

  def self.render_standard_form(frame, content_area, fields, field_keys, focus, active_text)
    constraints = field_keys.map { RatatuiRuby::Layout::Constraint.length(1) }
    constraints << RatatuiRuby::Layout::Constraint.length(1)
    constraints << RatatuiRuby::Layout::Constraint.length(1)

    form_chunks = RatatuiRuby::Layout::Layout.split(content_area, direction: :vertical, constraints: constraints)
    field_keys.each_with_index do |field_key, index|
      render_single_input_field(frame, form_chunks[index], fields[field_key], field_key == focus)
    end
    form_chunks.last
  end

  def self.render_form_popup_hint(frame, hint_chunk)
    hint_p = RatatuiRuby::Widgets::Paragraph.new(
      text: @active_focus == :table ? AppConfig.settings.language_string(:hint) : AppConfig.settings.language_string(:alert_cancel_ok),
      alignment: :center, style: { fg: AppConfig.settings.theme_item(:foreground),
                                   bg: AppConfig.settings.theme_item(:background), modifiers: [:dim] }
    )
    frame.render_widget(hint_p, hint_chunk)
  end

  def self.render_single_input_field(frame, chunk, field_obj, is_focused)
    return unless field_obj

    field_block = RatatuiRuby::Widgets::Block.new(
      title: '',
      title_style: {},
      borders: [:none]
    )

    frame.render_widget(field_block, chunk)
    field_inner_area = field_block.inner(chunk)

    field_obj.set_editor_focus(is_focused)

    field_obj.render_to_frame(
      frame,
      field_inner_area,
      alignment: input_field_alignment(field_obj)
    )
  end

  def self.render_inactive_input_field(frame, field_inner_area, field_obj, has_text)
    display_text = if has_text
                     field_obj.visual_layout.map { |item| item[:char] }.join
                   else
                     (field_obj.placeholder || '').to_s
                   end

    text_modifiers = has_text ? [] : [:dim]

    max_width = [field_inner_area.width.to_i, 1].max
    clusters = display_text.gsub(/[\u2066\u2069]/, '').grapheme_clusters

    # 🎯 FIX: Gebruik Unicode::DisplayWidth voor het inactieve invoerveld
    if Unicode::DisplayWidth.of(display_text) > max_width
      is_rtl = field_obj.direction == :rtl
      target_space = [max_width - 1, 0].max

      if is_rtl
        # ◄── RTL: Restant opvullen
        retained_clusters = []
        current_width = 0
        clusters.reverse_each do |cluster|
          w = Unicode::DisplayWidth.of(cluster)
          break if current_width + w > target_space

          retained_clusters.unshift(cluster)
          current_width += w
        end
        padding_needed = target_space - current_width
        display_text = ' ' * padding_needed + "…#{retained_clusters.join}"
      else
        # ──► LTR: Restant opvullen vóór de '…'
        retained_clusters = []
        current_width = 0
        clusters.each do |cluster|
          w = Unicode::DisplayWidth.of(cluster)
          break if current_width + w > target_space

          retained_clusters << cluster
          current_width += w
        end
        padding_needed = target_space - current_width
        display_text = "#{retained_clusters.join}" + ' ' * padding_needed + '…'
      end
    end

    content_string =
      if has_text
        "\u2066#{display_text}\u2069"
      else
        "\u200E#{display_text}"
      end

    line = RatatuiRuby::Text::Line.new(
      spans: [
        RatatuiRuby::Text::Span.new(
          content: content_string,
          style: {
            fg: AppConfig.settings.theme_item(:foreground),
            bg: AppConfig.settings.theme_item(:background),
            modifiers: text_modifiers
          }
        )
      ]
    )

    frame.render_widget(
      RatatuiRuby::Widgets::Paragraph.new(text: line, alignment: input_field_alignment(field_obj)),
      field_inner_area
    )
  end

  def self.render_empty_active_input_field(frame, field_inner_area, field_obj)
    settings = AppConfig.settings

    placeholder_text = field_obj.placeholder.to_s
    placeholder_chars = placeholder_text.chars

    # If the placeholder is accidentally empty, use a space for the cursor.
    first_char = placeholder_chars.shift || ' '
    rest_of_placeholder = placeholder_chars.join

    cursor_span = RatatuiRuby::Text::Span.new(
      content: first_char,
      style: {
        bg: settings.theme_item(:cursor_color).to_s,
        fg: settings.theme_item(:cursor_text).to_s,
        modifiers: []
      }
    )

    text_span = RatatuiRuby::Text::Span.new(
      content: rest_of_placeholder,
      style: { fg: settings.theme_item(:foreground),
               bg: settings.theme_item(:background), modifiers: [:dim] }
    )

    line = RatatuiRuby::Text::Line.new(spans: [cursor_span, text_span])
    frame.render_widget(RatatuiRuby::Widgets::Paragraph.new(text: line, alignment: input_field_alignment(field_obj)),
                        field_inner_area)

    # 🎯 FIX: The hardware cursor call has been removed here.
    # De software-cursor (cursor_span) doet al al het werk viltstrak binnenshuis.
  end

  # render_active_input_field_with_text rendert die clusters met een LRM-prefix.
  # The actual search term is currently read from get_text, which returns the logical buffer.

  def self.render_active_input_field_with_text(frame, field_inner_area, field_obj)
    settings = AppConfig.settings
    width = [field_inner_area.width.to_i, 1].max

    cursor_visible = App.software_cursor.visible || field_obj.editor_cursor_visible?

    force_cursor_visible =
      !!field_obj.instance_variable_get(:@popup_force_cursor_visible)

    if force_cursor_visible
      cursor_visible = true

      field_obj.instance_variable_set(:@popup_force_cursor_visible, false) if App.software_cursor.visible
    end

    field_obj.instance_variable_set(:@popup_force_cursor_visible, false) if App.software_cursor.visible

    # Gebruik exact dezelfde visuele layout en cursorindex als display_value.
    layout = field_obj.editor_visual_layout
    cursor_index = field_obj.text.empty? ? 0 : field_obj.visual_cursor_item_index

    ranges = if field_obj.respond_to?(:selection_ranges)
               field_obj.selection_ranges
             else
               legacy_range = field_obj.selection_range
               legacy_range ? [legacy_range] : []
             end

    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)

    is_latin_or_common = lambda do |cluster|
      cluster.to_s.match?(/\A[\p{Latin}0-9\s[:punct:]]+\z/)
    end

    cells = layout.each_with_index.map do |item, idx|
      logical_index = item[:logical_index]
      logical_end = item[:logical_end]
      cluster = item[:char].to_s

      style = {
        fg: settings.theme_item(:foreground),
        bg: settings.theme_item(:background)
      }

      # Dezelfde selectiecontrole als RatinField#display_value.
      item_selected =
        !logical_index.nil? &&
        !logical_end.nil? &&
        ranges.any? do |selected_range|
          logical_index < selected_range[1] &&
            logical_end > selected_range[0]
        end

      if item_selected
        style[:bg] = settings.theme_item(:selection_background).to_s
        style[:fg] = settings.theme_item(:foreground).to_s
      end

      # Place the cursor directly on the visual text cluster.
      if idx == cursor_index && cursor_visible
        style[:bg] = settings.theme_item(:cursor_color).to_s
        style[:fg] = settings.theme_item(:cursor_text).to_s
        style[:modifiers] = []
      end

      style[:modifiers] = Array(style[:modifiers]) | [:italic] if is_handwritten && !is_latin_or_common.call(cluster)

      {
        char: cluster,
        style: style,
        logical_index: logical_index,
        width: item[:cell_width] || [Unicode::DisplayWidth.of(cluster), 1].max
      }
    end

    # Empty field: show the placeholder with the cursor on the first cluster.
    if field_obj.text.to_s.empty?
      placeholder_clusters = field_obj.placeholder.to_s.grapheme_clusters
      first_cluster = placeholder_clusters.shift || ' '

      cursor_style =
        if cursor_visible
          {
            fg: settings.theme_item(:cursor_text).to_s,
            bg: settings.theme_item(:cursor_color).to_s,
            modifiers: []
          }
        else
          {
            fg: settings.theme_item(:foreground).to_s,
            bg: settings.theme_item(:background).to_s,
            modifiers: [:dim]
          }
        end

      placeholder_style = {
        fg: settings.theme_item(:foreground).to_s,
        bg: settings.theme_item(:background).to_s,
        modifiers: [:dim]
      }

      cells = [{
        char: first_cluster,
        style: cursor_style,
        logical_index: nil,
        width: [Unicode::DisplayWidth.of(first_cluster), 1].max
      }]

      placeholder_clusters.each do |cluster|
        cells << {
          char: cluster,
          style: placeholder_style,
          logical_index: nil,
          width: [Unicode::DisplayWidth.of(cluster), 1].max
        }
      end

      cursor_index = 0
    end

    # Defensieve fallback.
    if cells.empty?
      fallback_style =
        if cursor_visible
          {
            fg: settings.theme_item(:cursor_text).to_s,
            bg: settings.theme_item(:cursor_color).to_s,
            modifiers: []
          }
        else
          {
            fg: settings.theme_item(:foreground).to_s,
            bg: settings.theme_item(:background).to_s
          }
        end

      cells = [{
        char: ' ',
        style: fallback_style,
        logical_index: nil,
        width: 1
      }]

      cursor_index = 0
    end

    # As in display_value, add an empty cursor cell only when the cursor
    # is actually past the last text cluster.
    if !field_obj.text.to_s.empty? && cursor_index >= cells.length
      cursor_style =
        if cursor_visible
          {
            fg: settings.theme_item(:cursor_text).to_s,
            bg: settings.theme_item(:cursor_color).to_s,
            modifiers: []
          }
        else
          {
            fg: settings.theme_item(:foreground).to_s,
            bg: settings.theme_item(:background).to_s
          }
        end

      cells << {
        char: ' ',
        style: cursor_style,
        logical_index: field_obj.text.length,
        width: 1
      }

      cursor_index = cells.length - 1
    end

    # Cursorindex begrenzen.
    cursor_index = [[cursor_index, 0].max, cells.length - 1].min

  # Calculate the viewport in terminal cells to keep the cursor visible.
    start_index = cursor_index
    used_width = cells[cursor_index][:width]

    while start_index.positive?
      previous_width = cells[start_index - 1][:width]
      break if used_width + previous_width > width

      start_index -= 1
      used_width += previous_width
    end

    visible_cells = []
    visible_width = 0

    cells[start_index..].to_a.each do |cell|
      break if visible_width + cell[:width] > width

      visible_cells << cell
      visible_width += cell[:width]
    end

    if visible_cells.empty?
      visible_cells = [{
        char: ' ',
        style: {
          fg: settings.theme_item(:foreground).to_s,
          bg: settings.theme_item(:background).to_s
        },
        width: 1
      }]
    end

    # Stabiele LTR-basislijn voor de reeds visueel gerangschikte clusters.
    spans = [
      RatatuiRuby::Text::Span.new(content: "\u200E", style: {})
    ]

    visible_cells.each do |cell|
      spans << RatatuiRuby::Text::Span.new(
        content: cell[:char],
        style: cell[:style] || {}
      )
    end

    line = RatatuiRuby::Text::Line.new(spans: spans)

    frame.render_widget(
      RatatuiRuby::Widgets::Paragraph.new(
        text: line,
        alignment: if field_obj.text.to_s.empty?
                     :left
                   else
                     input_field_alignment(field_obj)
                   end,
        wrap: false
      ),
      field_inner_area
    )
  end

  def self.build_input_field_cells(
    layout,
    range,
    cursor_column,
    field_obj,
    cursor_visible
  )
    cells = []

    layout.each_with_index do |item, idx|
      logical_index = item[:logical_index]

      style = {
        fg: AppConfig.settings.theme_item(:foreground),
        bg: AppConfig.settings.theme_item(:background)
      }

      if idx == cursor_column && cursor_visible
        style[:bg] = AppConfig.settings.theme_item(:cursor_color).to_s
        style[:fg] = AppConfig.settings.theme_item(:cursor_text).to_s
        style[:modifiers] = []
      elsif logical_index &&
            range &&
            logical_index >= range[0] &&
            logical_index < range[1]

        style[:bg] = AppConfig.settings.theme_item(:selection_background).to_s
        style[:fg] = AppConfig.settings.theme_item(:foreground).to_s
      end

      cells << {
        char: item[:char], # Bevat nu letter + klinker onafscheidelijk samen!
        style: style,
        logical_index: logical_index,
        is_rtl: field_obj.rtl_char?(item[:char].chars.first)
      }
    end

    cells
  end

  def self.reverse_ghostty_input_cells(cells)
    # Alleen voor Ghostty voeren we de groeps-reversal uit tijdens het typen
    grouped_cells = []
    i = 0

    while i < cells.length
      is_rtl = cells[i][:is_rtl]
      j = i + 1
      j += 1 while j < cells.length && cells[j][:is_rtl] == is_rtl
      chunk_segment = cells[i...j]
      grouped_cells.concat(is_rtl ? chunk_segment.reverse : chunk_segment)
      i = j
    end

    grouped_cells
  end

  def self.render_input_field_viewport(frame, field_inner_area, cells, cursor_column, width)
    width = [width.to_i, 1].max
    cursor_column = [[cursor_column.to_i, 0].max, [cells.length - 1, 0].max].min

    start_column = [cursor_column - width + 1, 0].max
    max_start = [cells.length - width, 0].max
    start_column = [start_column, max_start].min

    visible_cells = cells.slice(start_column, width) || []

    settings = AppConfig.settings
    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)

    is_latin_or_common = lambda do |char|
      char.to_s.match?(/\A[\p{Latin}0-9\s[:punct:]]\z/)
    end

    # 🎯 KOGELVRIJE EN SCHONE METHODE:
    # Eén LRM marker aan de voorkant om de LTR basislijn te dwingen voor de terminal emulator.
    spans = []

    visible_cells.each do |cell|
      final_style = cell[:style] ? cell[:style].dup : {}

      if is_handwritten && !is_latin_or_common.call(cell[:char])
        final_style[:modifiers] = Array(final_style[:modifiers]) | [:italic]
      end

      spans << RatatuiRuby::Text::Span.new(
        content: cell[:char],
        style: final_style
      )
    end

    line = RatatuiRuby::Text::Line.new(spans: spans)

    frame.render_widget(
      RatatuiRuby::Widgets::Paragraph.new(text: line, alignment: :left, wrap: false),
      field_inner_area
    )
    nil
  end

  def self.calculate_centered_rect(r, exact_width_x, exact_height_y)
    remaining_height = r.height - exact_height_y
    top_and_bottom_space = [remaining_height / 2, 0].max

    _top, middle_row, _bottom = RatatuiRuby::Layout::Layout.split(
      r,
      direction: :vertical,
      constraints: [
        RatatuiRuby::Layout::Constraint.length(top_and_bottom_space),
        RatatuiRuby::Layout::Constraint.length(exact_height_y),
        RatatuiRuby::Layout::Constraint.length(top_and_bottom_space)
      ]
    )

    remaining_width = r.width - exact_width_x
    left_and_right_space = [remaining_width / 2, 0].max

    _left, centered_popup, _right = RatatuiRuby::Layout::Layout.split(
      middle_row,
      direction: :horizontal,
      constraints: [
        RatatuiRuby::Layout::Constraint.length(left_and_right_space),
        RatatuiRuby::Layout::Constraint.length(exact_width_x),
        RatatuiRuby::Layout::Constraint.length(left_and_right_space)
      ]
    )

    centered_popup
  end

  def self.active_form_input_direction(popup_data)
    return nil unless popup_data&.dig(:type) == :form

    fields = popup_data[:fields] || {}
    focus = popup_data[:form_focus] || fields.keys.first
    field_obj = fields[focus]

    return nil unless field_obj
    return nil unless field_obj.respond_to?(:text)
    return nil unless field_obj.respond_to?(:cursor_index)

    text = field_obj.text.to_s
    return nil if text.empty?

    chars = text.chars
    cursor = [[field_obj.cursor_index.to_i, 0].max, chars.length].min

    rtl_char = lambda do |char|
      char.to_s.match?(/[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]/)
    end

    strong_direction = lambda do |char|
      next nil unless char

      if rtl_char.call(char)
        :rtl
      elsif char.match?(/[[:alpha:]]/)
        :ltr
      end
    end

    # Geef voorrang aan de letter direct op de cursorpositie.
    direction = strong_direction.call(chars[cursor])
    return direction if direction

    # Als de cursor aan het einde staat, of op witruimte/leestekens,
    # zoek dan de dichtstbijzijnde sterke letter.
    left = cursor - 1
    right = cursor + 1

    while left >= 0 || right < chars.length
      if left >= 0
        direction = strong_direction.call(chars[left])
        return direction if direction

        left -= 1
      end

      next unless right < chars.length

      direction = strong_direction.call(chars[right])
      return direction if direction

      right += 1
    end

    nil
  end
end
