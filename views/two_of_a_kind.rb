# frozen_string_literal: true

require_relative 'test'

class RatatuiRubyApp
  include TestView

  private

  def render_two_of_a_kind_view(tui, frame, region)
    settings = AppConfig.settings

    @user_hand ||= []
    @user_card_index ||= 0
    bg_color = settings.theme_item(:background)

    @two_of_a_kind_show_context = true if @two_of_a_kind_show_context.nil?

    render_two_of_a_kind_view_background(frame, region, bg_color)
    return if render_two_of_a_kind_completion_state(tui, frame, region, settings)

    geometry = two_of_a_kind_view_geometry(region)

    @two_of_a_kind_visible_rows = geometry[:max_visible_rows]

    ensure_two_of_a_kind_cursor_visible

    geometry[:scroll_y] = @two_of_a_kind_scroll_y

    is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    styles = two_of_a_kind_view_styles(settings, bg_color, is_popup_active)
    style_header = styles[:header]
    style_bracket = styles[:bracket]
    style_dimmed = styles[:dimmed]
    style_normal = styles[:normal]
    style_cursor = styles[:cursor]

    # Header tekenen (Term / Duet)
    render_two_of_a_kind_view_header(
      tui, frame, region, geometry,
      style_header, style_bracket, style_dimmed
    )

    # Handkaarten van de gebruiker weergeven in een tabelstructuur
    render_two_of_a_kind_table_body(
      tui, frame, settings, region, geometry,
      style_normal, style_cursor, style_dimmed, bg_color
    )

    render_two_of_a_kind_computer_question(
      tui, frame, region, geometry, style_header, style_dimmed
    )

    render_two_of_a_kind_context_panel(
      tui, frame, settings, region, geometry,
      bg_color, style_dimmed, is_popup_active
    )

    render_two_of_a_kind_view_borders(
      tui, frame, region, settings, geometry, style_dimmed
    )

    # Scrollbar: dezelfde renderer als de drill view.
    return unless geometry[:scrollbar_visible]

    render_drill_scrollbar(
      tui,
      frame,
      region,
      @user_hand.length,
      @user_card_index,
      geometry[:max_visible_rows],
      position: @user_card_index,
      hard_boundary_y: geometry[:hard_boundary_y],
      visible_height: geometry[:max_visible_rows]
    )
  end

  def render_two_of_a_kind_table_body(tui, frame, settings, region, geometry,
                                      style_normal, style_cursor, style_dimmed, bg_color)
    render_two_of_a_kind_card_rows(
      tui, frame, settings, region, geometry,
      style_normal, style_cursor
    )
  end

  def render_two_of_a_kind_computer_question(tui, frame, region, geometry, style_header, style_dimmed)
    # De rij voor de computerkaart is permanent gereserveerd.
    # Teken daarom ook permanent de horizontale divider erboven.
    question_y = geometry[:hard_boundary_y] - 1
    divider_y = question_y - 1

    # Horizontale divider met optionele middenverbinding
    divider_line = '─' * region.width

    if @show_table_dividers == true
      middle_offset = geometry[:middle_sep_x] - region.x
      divider_line[middle_offset] = '┼'
    end

    frame.render_widget(
      tui.paragraph(text: divider_line, style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(
        region.x, divider_y, region.width, 1
      )
    )

    # Aansluitingen aan de linker- en rechterrand
    frame.render_widget(
      tui.paragraph(text: '├', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(
        region.x - 1, divider_y, 1, 1
      )
    )

    frame.render_widget(
      tui.paragraph(text: '┤', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(
        region.x + region.width, divider_y, 1, 1
      )
    )

    # Verticale divider in de computerkaart altijd tekenen
    if @show_table_dividers == true
      frame.render_widget(
        tui.paragraph(text: '│', style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(
          geometry[:middle_sep_x], question_y, 1, 1
        )
      )
    end

    # Draw the card content only when there is a question.
    return unless @two_of_a_kind_waiting_for_answer
    return unless @two_of_a_kind_computer_question

    card_term = @two_of_a_kind_computer_question[:term].to_s
    card_meaning = @two_of_a_kind_computer_question[:meaning].to_s

    return if card_term.empty?

    text_start_x = geometry[:text_start_x]
    left_col_w = geometry[:left_col_w]
    right_col_x = geometry[:right_col_x]
    right_col_w = geometry[:right_col_w]
    middle_sep_x = geometry[:middle_sep_x]

    # Achtergrond van de volledige tabelrij
    frame.render_widget(
      tui.paragraph(text: ' ' * region.width, style: style_header),
      RatatuiRuby::Layout::Rect.new(
        region.x, question_y, region.width, 1
      )
    )

    # Left column: right-align the word.
    formatted_term = format_drill_left_cell(card_term, left_col_w)

    frame.render_widget(
      tui.paragraph(
        text: formatted_term,
        style: style_header,
        alignment: :right,
        wrap: false
      ),
      RatatuiRuby::Layout::Rect.new(
        text_start_x, question_y, left_col_w, 1
      )
    )

    # Rechterkolom: betekenis links uitgelijnd
    formatted_meaning = format_drill_right_cell(card_meaning, right_col_w)

    frame.render_widget(
      tui.paragraph(
        text: formatted_meaning,
        style: style_header,
        alignment: :left,
        wrap: false
      ),
      RatatuiRuby::Layout::Rect.new(
        right_col_x + 1, question_y, right_col_w, 1
      )
    )

    # Verticale divider boven op de achtergrond en tekst tekenen
    return unless @show_table_dividers == true

    frame.render_widget(
      tui.paragraph(text: '│', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(
        middle_sep_x, question_y, 1, 1
      )
    )
  end

  def render_two_of_a_kind_view_background(frame, region, bg_color)
    return unless defined?(RatatuiRuby::Widgets::Clear)

    frame.render_widget(RatatuiRuby::Widgets::Clear.new, region)
    background = RatatuiRuby::Widgets::Block.new(style: { bg: bg_color }, borders: [:none])
    frame.render_widget(background, region)
  end

  def render_two_of_a_kind_completion_state(tui, frame, region, settings)
    duo_active = defined?(@current_study_mode) &&
                 @current_study_mode == :two_of_a_kind
    finished = defined?(@test_finished_waiting) &&
               @test_finished_waiting == true

    return false unless duo_active && finished

    completed_message =
      "#{settings.language_string(:statusbar_study_two_of_a_kind_computer)}: #{@computer_score} " \
      "– #{settings.language_string(:statusbar_study_two_of_a_kind_user)}: #{@user_score}"

    lines = [
      settings.language_string(:study_status_screen_play_two_of_a_kind),
      completed_message,
      settings.language_string(:study_status_screen_finished)
    ]

    render_test_status_screen(tui, frame, region, '✓', lines)
    true
  end

  def two_of_a_kind_view_geometry(region)
    base_data_y = region.y + 2

    hard_boundary_y = if @two_of_a_kind_show_context
                        region.y + region.height - 2
                      else
                        region.y + region.height
                      end

    actual_table_height = hard_boundary_y - base_data_y

    # Reserveer altijd twee vaste rijen:
    # 1. De horizontale divider.
    # 2. De rij voor de computerkaart.
    # This keeps the viewport stable when the question appears.
    max_visible_rows = [actual_table_height - 2, 1].max
    @two_of_a_kind_visible_rows = max_visible_rows

    scrollbar_visible = drill_scrollbar_needed?(
      @user_hand.length,
      max_visible_rows
    )

    start_x = region.x
    padding_side = 1

    full_table_w = [region.width - 1, 1].max
    available_w = full_table_w - (padding_side * 2) - 1

    left_col_w = [(available_w / 2).floor, 1].max
    middle_sep_x = start_x + padding_side + left_col_w
    right_col_x = middle_sep_x + 1

    right_col_w = [
      (region.x + full_table_w - padding_side) - right_col_x,
      1
    ].max

    # Reserveer dezelfde rechterkolombreedte als in de drill view.
    right_col_w = [right_col_w - 1, 1].max if scrollbar_visible

    {
      base_data_y: base_data_y,
      max_visible_rows: max_visible_rows,
      hard_boundary_y: hard_boundary_y,
      actual_table_height: actual_table_height,
      scrollbar_visible: scrollbar_visible,
      scrollbar_height: max_visible_rows,
      start_x: start_x,
      padding_side: padding_side,
      text_start_x: start_x + padding_side,
      card_width: [region.width - (padding_side * 2), 1].max,
      left_col_w: left_col_w,
      right_col_w: right_col_w,
      right_col_x: right_col_x,
      middle_sep_x: middle_sep_x,
      scroll_y: @two_of_a_kind_scroll_y || 0
    }
  end

  def render_two_of_a_kind_view_header(tui, frame, region, geometry,
                                       style_header, style_bracket, style_dimmed)
    settings = AppConfig.settings

    style_header_right = {
      fg: settings.theme_item(:selected_row_background),
      bg: settings.theme_item(:background)
    }

    computer_active = @two_of_a_kind_active_player == :computer
    user_active = @two_of_a_kind_active_player == :user

    computer_header_style = if computer_active
                              style_header
                            else
                              {
                                fg: settings.theme_item(:table_header_text),
                                bg: settings.theme_item(:background),
                                modifiers: [:dim]
                              }
                            end

    user_header_style = if user_active
                          style_header_right
                        else
                          {
                            fg: settings.theme_item(:selected_row_background),
                            bg: settings.theme_item(:background),
                            modifiers: [:dim]
                          }
                        end

    half_width = geometry[:middle_sep_x] - region.x
    middle_sep_x = geometry[:middle_sep_x]

    computer_pair_source = @computer_last_pair_source
    user_pair_source = @user_last_pair_source

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    computer_last_pair =
      if @computer_last_pair_until && now < @computer_last_pair_until
        case computer_pair_source
        when :asked then ' (⇄)'
        when :drawn then ' (↓)'
        else ''
        end
      else
        ''
      end

    user_last_pair =
      if @user_last_pair_until && now < @user_last_pair_until
        case user_pair_source
        when :asked then ' (⇄)'
        when :drawn then ' (↓)'
        else ''
        end
      else
        ''
      end

    left_pairs = "⧉:#{@computer_score}#{computer_last_pair}"
    left_hand = "🂠:#{@computer_hand.length}"

    right_pairs = "⧉:#{@user_score}#{user_last_pair}"
    right_hand = "🂠:#{@user_hand.length}"

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    draw_animating =
      @two_of_a_kind_draw_animation_until &&
      now < @two_of_a_kind_draw_animation_until

    computer_animating =
      draw_animating &&
      @two_of_a_kind_draw_animation_player == :computer

    user_animating =
      draw_animating &&
      @two_of_a_kind_draw_animation_player == :user

    rotation_symbol = active_bar_rotation_indicator_symbol(force: true)

    # Header: bij aanvang de studiemelding tonen
    if @two_of_a_kind_show_start_message
      message = settings.language_string(:statusbar_study_two_of_a_kind_msg)

      frame.render_widget(
        tui.paragraph(
          text: "#{message}!",
          style: {
            fg: settings.theme_item(:table_header_text),
            bg: settings.theme_item(:background)
          },
          alignment: :center,
          wrap: false
        ),
        RatatuiRuby::Layout::Rect.new(
          region.x, region.y, region.width, 1
        )
      )
    else
      # Computer
      frame.render_widget(
        tui.paragraph(text: left_pairs, style: computer_header_style, alignment: :left),
        RatatuiRuby::Layout::Rect.new(
          region.x + 1, region.y, half_width / 2, 1
        )
      )

      frame.render_widget(
        tui.paragraph(text: left_hand, style: computer_header_style, alignment: :right),
        RatatuiRuby::Layout::Rect.new(
          region.x + (half_width / 2), region.y,
          half_width - (half_width / 2) - 1, 1
        )
      )

      if computer_animating
        frame.render_widget(
          tui.paragraph(
            text: rotation_symbol,
            style: computer_header_style,
            alignment: :center
          ),
          RatatuiRuby::Layout::Rect.new(
            region.x + 1, region.y, half_width - 1, 1
          )
        )
      end

      # Gebruiker
      right_start_x = middle_sep_x + 2
      right_width = region.width - half_width - 1

      frame.render_widget(
        tui.paragraph(text: right_pairs, style: user_header_style, alignment: :left),
        RatatuiRuby::Layout::Rect.new(
          right_start_x, region.y, right_width / 2, 1
        )
      )

      frame.render_widget(
        tui.paragraph(text: right_hand, style: user_header_style, alignment: :right),
        RatatuiRuby::Layout::Rect.new(
          right_start_x + (right_width / 2), region.y,
          right_width - (right_width / 2) - 2, 1
        )
      )

      if user_animating
        frame.render_widget(
          tui.paragraph(
            text: rotation_symbol,
            style: user_header_style,
            alignment: :center
          ),
          RatatuiRuby::Layout::Rect.new(
            right_start_x, region.y, right_width - 2, 1
          )
        )
      end

      # Middelste divider alleen bij de normale header
      header_sep_char = @show_table_dividers == true ? '│' : ' '

      frame.render_widget(
        tui.paragraph(text: header_sep_char, style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(middle_sep_x, region.y, 1, 1)
      )
    end

    # Horizontale lijn onder de header
    frame.render_widget(
      tui.paragraph(text: '─' * region.width, style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(
        region.x, region.y + 1, region.width, 1
      )
    )
  end

  def render_two_of_a_kind_view_borders(tui, frame, region, settings, geometry, style_dimmed)
    middle_sep_x = geometry[:middle_sep_x]
    header_divider_y = region.y + 1

    # Aansluitingen aan weerszijden van de headerlijn
    frame.render_widget(
      tui.paragraph(text: '├', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(region.x - 1, header_divider_y, 1, 1)
    )

    frame.render_widget(
      tui.paragraph(text: '┤', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(region.x + region.width, header_divider_y, 1, 1)
    )

    if (@show_table_dividers == true) && !@two_of_a_kind_show_start_message

      frame.render_widget(
        tui.paragraph(text: '┬', style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(middle_sep_x, region.y - 1, 1, 1)
      )

      frame.render_widget(
        tui.paragraph(text: '┼', style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(middle_sep_x, header_divider_y, 1, 1)
      )
    end

    # Onderste aansluiting van de tabel
    end_junction_y = geometry[:hard_boundary_y]

    if @two_of_a_kind_show_context
      # Context visible: the context panel draws the horizontal line.
      frame.render_widget(
        tui.paragraph(text: '├', style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(region.x - 1, end_junction_y, 1, 1)
      )

      frame.render_widget(
        tui.paragraph(text: '┤', style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(region.x + region.width, end_junction_y, 1, 1)
      )
    else
      # Context verborgen: teken zelf de horizontale onderlijn
      frame.render_widget(
        tui.paragraph(text: '─' * region.width, style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(region.x, end_junction_y, region.width, 1)
      )
    end

    # Verticale divider sluit onderaan aan op de horizontale lijn
    return unless @show_table_dividers == true

    frame.render_widget(
      tui.paragraph(text: '┴', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(middle_sep_x, end_junction_y, 1, 1)
    )
  end

  def render_two_of_a_kind_card_rows(tui, frame, settings, region, geometry,
                                     style_normal, style_cursor)
    base_data_y = geometry[:base_data_y]
    hard_boundary_y = geometry[:hard_boundary_y]
    max_visible_rows = geometry[:max_visible_rows]
    start_x = geometry[:start_x]
    text_start_x = geometry[:text_start_x]
    left_col_w = geometry[:left_col_w]
    right_col_x = geometry[:right_col_x]
    right_col_w = geometry[:right_col_w]
    middle_sep_x = geometry[:middle_sep_x]

    style_dimmed = {
      fg: settings.theme_item(:window_border),
      bg: settings.theme_item(:background)
    }

    # Handwritten-instelling ophalen, net als in de drill-view
    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)

    is_latin_or_common = lambda do |char|
      char =~ /\A[\p{Latin}0-9\s[:punct:]]\z/
    end

    # Show the first card at the top and the newest card at the bottom.
    # Kaarten tekenen met dynamische scrollpositie
    scroll_y = geometry[:scroll_y]

    visible_cards = @user_hand.each_with_index.select do |_card, original_idx|
      original_idx >= scroll_y &&
        original_idx < scroll_y + max_visible_rows
    end

    if settings.alternate_rows_enabled
      max_visible_rows.times do |index|
        absolute_idx = scroll_y + index
        next unless absolute_idx.odd?

        alternate_bg = alternate_table_row_background(
          settings.theme_item(:background),
          settings.theme_item(:foreground)
        )

        next unless alternate_bg

        frame.render_widget(
          tui.paragraph(
            text: ' ' * region.width,
            style: { bg: alternate_bg }
          ),
          RatatuiRuby::Layout::Rect.new(
            start_x, base_data_y + index, region.width, 1
          )
        )
      end
    end

    visible_cards.each do |card, original_idx|
      screen_idx = original_idx - scroll_y
      current_row_y = base_data_y + screen_idx

      is_active_row = original_idx == @user_card_index

      row_style = if is_active_row
                    style_cursor
                  elsif settings.alternate_rows_enabled && original_idx.odd?
                    alternate_bg = alternate_table_row_background(
                      settings.theme_item(:background),
                      settings.theme_item(:foreground)
                    )
                    alternate_bg ? style_normal.merge(bg: alternate_bg) : style_normal
                  else
                    style_normal
                  end

      card_text = card[:term].to_s
      meaning_text = is_active_row ? card[:meaning].to_s : ''

      formatted_text = format_drill_left_cell(card_text, left_col_w)
      right_text_max_w = [right_col_w, 1].max
      formatted_meaning = format_drill_right_cell(
        meaning_text, right_text_max_w
      )

      frame.render_widget(
        tui.paragraph(text: ' ' * region.width, style: row_style),
        RatatuiRuby::Layout::Rect.new(
          start_x, current_row_y, region.width, 1
        )
      )

      if is_active_row && @show_table_dividers == true
        frame.render_widget(
          tui.paragraph(
            text: '│',
            style: {
              fg: settings.theme_item(:window_border),
              bg: style_cursor[:bg]
            }
          ),
          RatatuiRuby::Layout::Rect.new(
            middle_sep_x, current_row_y, 1, 1
          )
        )
      end

      left_line = RatatuiRuby::Text::Line.new(spans: [
                                                RatatuiRuby::Text::Span.new(
                                                  content: formatted_text,
                                                  style: row_style
                                                )
                                              ])

      if is_handwritten && formatted_text.chars.any? { |c| !is_latin_or_common.call(c) }
        left_line.spans.first.style[:modifiers] =
          Array(left_line.spans.first.style[:modifiers]) | [:italic]
      end

      frame.render_widget(
        RatatuiRuby::Widgets::Paragraph.new(
          text: left_line,
          alignment: :right,
          wrap: false
        ),
        RatatuiRuby::Layout::Rect.new(
          text_start_x, current_row_y, left_col_w, 1
        )
      )

      right_line = RatatuiRuby::Text::Line.new(spans: [
                                                 RatatuiRuby::Text::Span.new(
                                                   content: formatted_meaning,
                                                   style: row_style
                                                 )
                                               ])

      if is_handwritten && formatted_meaning.chars.any? { |c| !is_latin_or_common.call(c) }
        right_line.spans.first.style[:modifiers] =
          Array(right_line.spans.first.style[:modifiers]) | [:italic]
      end

      frame.render_widget(
        RatatuiRuby::Widgets::Paragraph.new(
          text: right_line,
          alignment: :left,
          wrap: false
        ),
        RatatuiRuby::Layout::Rect.new(
          right_col_x + 1, current_row_y, right_text_max_w, 1
        )
      )
    end

    return unless @show_table_dividers == true

    table_height = max_visible_rows + 1

    table_height.times do |line_offset|
      absolute_idx = scroll_y + line_offset
      is_selected = absolute_idx == @user_card_index

      divider_bg = if is_selected
                     style_cursor[:bg]
                   elsif settings.alternate_rows_enabled && absolute_idx.odd?
                     alternate_table_row_background(
                       settings.theme_item(:background),
                       settings.theme_item(:foreground)
                     ) || style_normal[:bg]
                   else
                     style_normal[:bg]
                   end

      frame.render_widget(
        tui.paragraph(
          text: '│',
          style: {
            fg: settings.theme_item(:window_border),
            bg: divider_bg
          }
        ),
        RatatuiRuby::Layout::Rect.new(
          middle_sep_x, base_data_y + line_offset, 1, 1
        )
      )
    end
  end

  def render_two_of_a_kind_context_panel(tui, frame, settings, region, geometry,
                                         bg_color, style_dimmed, is_popup_active)
    return unless @two_of_a_kind_show_context

    text_start_x = geometry[:text_start_x]
    padding_side = geometry[:padding_side]

    bottom_divider_y = region.y + region.height - 2
    context_text_y = bottom_divider_y + 1

    clean_width = ('─' * region.width).gsub(/[\u200E\u200F\u2068\u2069\u2066\u2067]/, '').length
    frame.render_widget(
      tui.paragraph(text: '─' * clean_width, style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(region.x, bottom_divider_y, clean_width, 1)
    )

    # Show the context of the selected card.
    context_raw = @two_of_a_kind_current_context.to_s

    context_style = {
      fg: settings.theme_item(:studysessions_context),
      bg: bg_color,
      modifiers: is_popup_active ? [:dim] : []
    }

    label_text = 'Context: '
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
      context_value = '(Geen context beschikbaar)'
      value_style = {
        fg: settings.theme_item(:studysessions_context),
        bg: bg_color,
        modifiers: is_popup_active ? %i[italic dim] : [:italic]
      }
    else
      # Gebruik dezelfde FriBidi-layout, richtingdetectie en afkaprichting
      # als render_drill_context_panel.
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

    # Preserve the isolation used by the existing drill view.
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

  def two_of_a_kind_view_styles(settings, bg_color, is_popup_active)
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

  def ensure_two_of_a_kind_cursor_visible
    total_cards = @user_hand.length
    return if total_cards.zero?

    visible_rows = [@two_of_a_kind_visible_rows.to_i, 1].max

    @two_of_a_kind_scroll_y ||= 0
    @user_card_index = @user_card_index.to_i

    if @user_card_index >= @two_of_a_kind_scroll_y + visible_rows
      @two_of_a_kind_scroll_y = @user_card_index - visible_rows + 1
    elsif @user_card_index < @two_of_a_kind_scroll_y
      @two_of_a_kind_scroll_y = @user_card_index
    end

    max_offset = [total_cards - visible_rows, 0].max

    @two_of_a_kind_scroll_y = [
      [@two_of_a_kind_scroll_y, 0].max,
      max_offset
    ].min
  end
end
