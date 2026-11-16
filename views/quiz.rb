# frozen_string_literal: true

require_relative 'test'

class RatatuiRubyApp
  include TestView

  private

  def render_quiz_view(tui, frame, region)
    @cards_to_test ||= respond_to?(:active_cards) ? active_cards : []
    @test_current_idx ||= 0
    @test_show_meaning = false if @test_show_meaning.nil?
    bg_color = AppConfig.settings.theme_item(:background)

    if defined?(RatatuiRuby::Widgets::Clear)
      frame.render_widget(RatatuiRuby::Widgets::Clear.new, region)
      # ALWAYS PAD UNCONDITIONALLY FOR A UNIFORM RESULT.
      bg_block = RatatuiRuby::Widgets::Block.new(style: { bg: bg_color }, borders: [:none])
      frame.render_widget(bg_block, region)
    end

    # Show a final status and stop drawing when the test is no longer active.
    return if render_quiz_status_screen_if_needed(tui, frame, region)

    # Additional safety guard for data extraction.
    return if @cards_to_test.empty?

    # =========================================================================
    # 🗂️ DATA EXTRACTION (Only when a card is actually available!)
    # =========================================================================
    term_value, ctx_value, mean_value = current_quiz_card_values

    # =========================================================================
    # 🏢 3. REGULAR QUIZ MODE (THE FAMILIAR, STRAIGHTFORWARD LAYOUT)
    # =========================================================================
    line_x  = region.x + 3
    fixed_x = region.x + 5
    fixed_w = region.width - 8
    start_y = region.y + 4

    header_text, active_text_content, is_showing_front_tab, is_showing_back_tab =
      current_quiz_display_state(term_value, mean_value)

    is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    render_styles = quiz_render_styles(is_popup_active, bg_color)
    style_junction = render_styles[:junction]

    render_quiz_tabs(
      tui, frame, region, render_styles,
      is_showing_front_tab, is_showing_back_tab
    )

    render_quiz_dividers(tui, frame, region, style_junction)

    if @test_awaiting_difficulty
      if defined?(RatatuiRuby::Widgets::Clear)
        frame.render_widget(RatatuiRuby::Widgets::Clear.new, region)
        # ALWAYS PAD UNCONDITIONALLY FOR A UNIFORM RESULT.
        bg_block = RatatuiRuby::Widgets::Block.new(style: { bg: bg_color }, borders: [:none])
        frame.render_widget(bg_block, region)
      end

      lines = [
        AppConfig.settings.language_string(:study_status_screen_quiz),
        "#{@cards_to_test.length} #{AppConfig.settings.language_string(:study_status_screen_flashcards)}",
        AppConfig.settings.language_string(:study_status_screen_start)
      ]

      render_test_status_screen(tui, frame, region, '⏱︎', lines)
      return
    end

    end_offset_y = @test_show_context ? 4 : 2

    render_quiz_header_and_margin(
      tui, frame, line_x, fixed_x, fixed_w, start_y, end_offset_y,
      header_text, is_popup_active, bg_color
    )

    render_quiz_main_content(
      tui, frame, active_text_content, fixed_x, fixed_w, start_y,
      is_popup_active, bg_color
    )

    render_quiz_context(
      tui, frame, region, ctx_value, fixed_x, fixed_w, start_y,
      is_popup_active, bg_color
    )
  end

  # Draw the main text of the current quiz card.

  def render_quiz_main_content(tui, frame, active_text_content, fixed_x, fixed_w,
                               start_y, is_popup_active, bg_color)
    raw = active_text_content.to_s.gsub(/[\u2066\u2069]/, '')
    field = RatinField.new
    field.text = raw

    visual_clusters = field.visual_layout.map { |item| item[:char] }
    is_rtl = field.direction == :rtl

    max_width = [fixed_w.to_i, 1].max
    visual_width = Unicode::DisplayWidth.of(visual_clusters.join)

    if visual_width > max_width
      target_space = [max_width - 1, 0].max
      retained_clusters = []
      current_width = 0

      if is_rtl
        # FriBidi already returns visual order. Keep the rightmost portion
        # of an RTL line and put the ellipsis at its visual left edge.
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

    # Keep the already visually ordered string isolated from the terminal's
    # bidi engine so it is not reordered a second time.
    display_text = "\u2066#{display_text}\u2069"

    active_content_key = @test_show_meaning ? :foreground : :studysessions_answer
    style = quiz_element_style(active_content_key, bg_color, [], is_popup_active)

    active_lang = AppConfig.settings.language
    is_handwritten = AppConfig.settings.handwritten?(active_lang)

    if is_handwritten && raw.match?(/[^\p{Latin}0-9\s[:punct:]]/)
      style[:modifiers] = Array(style[:modifiers]) | [:italic]
    end

    frame.render_widget(
      RatatuiRuby::Widgets::Paragraph.new(
        text: display_text,
        alignment: is_rtl ? :right : :left,
        wrap: false,
        style: style
      ),
      RatatuiRuby::Layout::Rect.new(fixed_x, start_y + 2, fixed_w, 1)
    )
  end

  # Draw the left margin and header for the current quiz card.
  def render_quiz_header_and_margin(tui, frame, line_x, fixed_x, fixed_w, start_y,
                                    end_offset_y, header_text, is_popup_active, bg_color)
    margin_style = quiz_element_style(
      :studysessions_margin_line, bg_color, [], is_popup_active
    )

    (0..end_offset_y).each do |offset_y|
      frame.render_widget(
        tui.paragraph(text: '▍', style: margin_style),
        RatatuiRuby::Layout::Rect.new(line_x, start_y + offset_y, 1, 1)
      )
    end

    help_symbol = '?'
    remaining_spaces = (fixed_w + 1) - (header_text.length + help_symbol.length)
    remaining_spaces = [remaining_spaces, 1].max
    padding_string   = ' ' * remaining_spaces

    header_style = quiz_element_style(
      :studysessions_question, bg_color, %i[bold], is_popup_active
    )

    unified_top_line = RatatuiRuby::Text::Line.new(spans: [
                                                     RatatuiRuby::Text::Span.new(content: header_text,
                                                                                 style: header_style),
                                                     RatatuiRuby::Text::Span.new(content: padding_string,
                                                                                 style: { bg: bg_color })
                                                   ])

    frame.render_widget(
      tui.paragraph(text: unified_top_line, alignment: :left),
      RatatuiRuby::Layout::Rect.new(fixed_x, start_y, fixed_w, 1)
    )
  end

  # Draw the horizontal and vertical divider lines of the quiz view.
  def render_quiz_dividers(tui, frame, region, style_junction)
    full_table_w_qz = [region.width - 1, 1].max
    padding_side_qz = 1
    available_w_qz  = full_table_w_qz - (padding_side_qz * 2) - 1
    left_col_w_qz   = (available_w_qz / 2).floor
    middle_sep_x_qz = region.x + padding_side_qz + left_col_w_qz

    header_sep_char = @show_table_dividers == true ? '│' : ' '
    frame.render_widget(
      tui.paragraph(text: header_sep_char, style: style_junction),
      RatatuiRuby::Layout::Rect.new(middle_sep_x_qz, region.y, 1, 1)
    )

    frame.render_widget(
      tui.paragraph(text: '─' * region.width,
                    style: style_junction),
      RatatuiRuby::Layout::Rect.new(region.x, region.y + 1, region.width, 1)
    )

    header_divider_y = region.y + 1

    unless @test_awaiting_difficulty
      frame.render_widget(
        tui.paragraph(text: '├', style: style_junction),
        RatatuiRuby::Layout::Rect.new(region.x - 1, header_divider_y, 1, 1)
      )

      # Close the right side with a clean T-junction pointing left.
      frame.render_widget(
        tui.paragraph(text: '┤', style: style_junction),
        RatatuiRuby::Layout::Rect.new(region.x + region.width, header_divider_y, 1, 1)
      )
    end

    if @show_table_dividers == true && !@test_awaiting_difficulty
      # 1. ┬ ABSOLUTE BOVENRAND JUNCTION
      frame.render_widget(
        tui.paragraph(text: '┬', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_qz, region.y - 1, 1, 1)
      )

      # 2. ┼ CENTER JUNCTION (Below the quiz headers)
      frame.render_widget(
        tui.paragraph(text: '┴', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_qz, region.y + 1, 1, 1)
      )
    else
      # 🎯 DE DYNAMISCHE HERSTEL-BRANDMUUR BIJ UITSTAND:
      frame.render_widget(
        tui.paragraph(text: '─', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_qz, region.y - 1, 1, 1)
      )

      frame.render_widget(
        tui.paragraph(text: '─', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_qz, region.y + 1, 1, 1)
      )
    end
  end

  # Draw the front and back tabs with the appropriate active or dimmed style.
  def render_quiz_tabs(tui, frame, region, render_styles, is_showing_front_tab, is_showing_back_tab)
    style_bracket = render_styles[:bracket]
    style_dimmed = render_styles[:dimmed]
    style_active_side = render_styles[:active_side]
    style_active_bside = render_styles[:active_back_side]

    aside_spans = if !@test_awaiting_difficulty && is_showing_front_tab && !@cards_to_test.empty?
                    [
                      RatatuiRuby::Text::Span.new(content: '[', style: style_bracket),
                      RatatuiRuby::Text::Span.new(content: AppConfig.settings.language_string(:study_quiz_front),
                                                  style: style_active_side),
                      RatatuiRuby::Text::Span.new(content: ']', style: style_bracket)
                    ]
                  else
                    [
                      RatatuiRuby::Text::Span.new(content: '[', style: style_dimmed),
                      RatatuiRuby::Text::Span.new(content: AppConfig.settings.language_string(:study_quiz_front),
                                                  style: style_dimmed),
                      RatatuiRuby::Text::Span.new(content: ']', style: style_dimmed)
                    ]
                  end
    frame.render_widget(tui.paragraph(text: RatatuiRuby::Text::Line.new(spans: aside_spans)),
                        RatatuiRuby::Layout::Rect.new(region.x + 1, region.y, 12, 1))

    b_spans = if !@test_awaiting_difficulty && is_showing_back_tab && !@cards_to_test.empty?
                [
                  RatatuiRuby::Text::Span.new(content: '[', style: style_bracket),
                  RatatuiRuby::Text::Span.new(content: AppConfig.settings.language_string(:study_quiz_back),
                                              style: style_active_bside),
                  RatatuiRuby::Text::Span.new(content: ']', style: style_bracket)
                ]
              else
                [
                  RatatuiRuby::Text::Span.new(content: '[', style: style_dimmed),
                  RatatuiRuby::Text::Span.new(content: AppConfig.settings.language_string(:study_quiz_back),
                                              style: style_dimmed),
                  RatatuiRuby::Text::Span.new(content: ']', style: style_dimmed)
                ]
              end
    frame.render_widget(tui.paragraph(text: b_spans.is_a?(Array) ? RatatuiRuby::Text::Line.new(spans: b_spans) : b_spans, alignment: :right),
                        RatatuiRuby::Layout::Rect.new(region.x, region.y, region.width - 1, 1))
  end

  # Retrieve the term, context, and meaning of the current quiz card as safe strings.
  def current_quiz_card_values
    current_card = @cards_to_test[@test_current_idx]
    [
      current_card ? current_card.term.to_s : '',
      current_card ? current_card.context.to_s : '',
      current_card ? current_card.meaning.to_s : ''
    ]
  end

  # Determine which side, heading, and content of the current quiz card are visible.
  def current_quiz_display_state(term_value, mean_value)
    current_direction = if defined?(@test_card_directions) && @test_card_directions
                          @test_card_directions[@test_current_idx]
                        else
                          :front
                        end

    header_text = @test_show_meaning ? AppConfig.settings.language_string(:study_answer) : AppConfig.settings.language_string(:study_question)
    active_text_content = if current_direction == :back
                            @test_show_meaning ? term_value : mean_value
                          else
                            @test_show_meaning ? mean_value : term_value
                          end

    is_showing_front_tab = current_direction == :back ? @test_show_meaning : !@test_show_meaning
    is_showing_back_tab = current_direction == :back ? !@test_show_meaning : @test_show_meaning

    [header_text, active_text_content, is_showing_front_tab, is_showing_back_tab]
  end

  def quiz_render_styles(is_popup_active, bg_color)
    header_text_color = AppConfig.settings.theme_item(:table_header_text)

    {
      bracket: if is_popup_active
                 { fg: header_text_color, bg: bg_color, modifiers: [:dim] }
               else
                 { fg: header_text_color, bg: bg_color }
               end,
      dimmed: if is_popup_active
                { fg: header_text_color, bg: bg_color, modifiers: [:dim] }
              else
                { fg: header_text_color, modifiers: [:dim], bg: bg_color }
              end,
      active_side: if is_popup_active
                     { fg: header_text_color, bg: bg_color, modifiers: :dim }
                   else
                     { fg: header_text_color, bg: bg_color }
                   end,
      active_back_side: if is_popup_active
                          { fg: header_text_color, bg: bg_color, modifiers: [:dim] }
                        else
                          { fg: header_text_color, bg: bg_color }
                        end,
      junction: {
        fg: AppConfig.settings.theme_item(:window_border),
        bg: bg_color,
        modifiers: is_popup_active ? [:dim] : []
      }
    }
  end

  # Draw the appropriate end screen when time runs out or the quiz is complete.
  # Return true if a status screen was drawn; otherwise, return false.
  def render_quiz_status_screen_if_needed(tui, frame, region)
    if defined?(@test_time_was_up_notified) && @test_time_was_up_notified == true
      lines = [
        AppConfig.settings.language_string(:study_status_screen_quiz),
        AppConfig.settings.language_string(:study_status_screen_failed),
        AppConfig.settings.language_string(:study_status_screen_finished)
      ]

      render_test_status_screen(tui, frame, region, '✕', lines)
      return true
    end

    if (defined?(@test_finished_waiting) && @test_finished_waiting == true) || @cards_to_test.empty?
      lines = [
        AppConfig.settings.language_string(:study_status_screen_quiz),
        "#{AppConfig.settings.language_string(:study_status_screen_passed)}!",
        AppConfig.settings.language_string(:study_status_screen_finished)
      ]

      render_test_status_screen(tui, frame, region, '✓', lines)
      return true
    end

    false
  end

  # Draw the context line below the quiz card text.
  def render_quiz_context(tui, frame, region, ctx_value, fixed_x, fixed_w,
                          start_y, is_popup_active, bg_color)
    return unless @test_show_context
    return unless (start_y + 4) < (region.y + region.height)

    settings = AppConfig.settings
    label_text = settings.language_string(:study_context).to_s
    total_width = [fixed_w.to_i, 1].max

    # Reserve at least one cell for the context value; keep the label on the left.
    label_width = [
      Unicode::DisplayWidth.of(label_text),
      [total_width - 1, 0].max
    ].min
    value_width = [total_width - label_width, 1].max
    context_y = start_y + 4

    context_label_style = quiz_element_style(
      :studysessions_context, bg_color, [], is_popup_active
    )

    if label_width.positive?
      label_line = RatatuiRuby::Text::Line.new(spans: [
                                                 RatatuiRuby::Text::Span.new(
                                                   content: label_text,
                                                   style: context_label_style
                                                 )
                                               ])

      frame.render_widget(
        tui.paragraph(text: label_line, alignment: :left, wrap: false),
        RatatuiRuby::Layout::Rect.new(fixed_x, context_y, label_width, 1)
      )
    end

    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)
    value_alignment = :left

    if ctx_value.to_s.strip.empty?
      na_style = quiz_context_value_style(is_popup_active, bg_color)
      value_line = RatatuiRuby::Text::Line.new(spans: [
                                                 RatatuiRuby::Text::Span.new(
                                                   content: settings.language_string(:study_context_not_available),
                                                   style: na_style
                                                 )
                                               ])
    else
      raw_context = ctx_value.to_s.gsub(/[\u2066\u2069]/, '')
      context_field = RatinField.new
      context_field.text = raw_context

      visual_clusters = context_field.visual_layout.map { |item| item[:char] }
      is_rtl = context_field.direction == :rtl
      value_alignment = is_rtl ? :right : :left
      visual_width = Unicode::DisplayWidth.of(visual_clusters.join)

      if visual_width > value_width
        target_space = [value_width - 1, 0].max
        retained_clusters = []
        current_width = 0

        if is_rtl
          # Preserve the rightmost visual portion; ellipsis goes on the left.
          visual_clusters.reverse_each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_space

            retained_clusters.unshift(cluster)
            current_width += cluster_width
          end
          display_context = "…#{retained_clusters.join}"
        else
          visual_clusters.each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_space

            retained_clusters << cluster
            current_width += cluster_width
          end
          display_context = "#{retained_clusters.join}…"
        end
      else
        display_context = visual_clusters.join
      end

      # Preserve FriBidi's output order and isolate it from terminal bidi handling.
      display_context = "\u2066#{display_context}\u2069"
      value_style = quiz_context_value_style(is_popup_active, bg_color)
      value_line = build_study_handwritten_line(
        tui, display_context, value_style, is_handwritten
      )
    end

    frame.render_widget(
      tui.paragraph(text: value_line, alignment: value_alignment, wrap: false),
      RatatuiRuby::Layout::Rect.new(
        fixed_x + label_width, context_y, value_width, 1
      )
    )
  end

  # Determine the style for a context value or missing context.
  def quiz_context_value_style(is_popup_active, bg_color)
    style = quiz_element_style(
      :studysessions_context, bg_color, [:italic], is_popup_active
    )

    # Preserve the existing modifier order.
    style[:modifiers] = %i[italic dim] if is_popup_active
    style
  end

  # Build an element style and dim it when a popup is active.
  def quiz_element_style(theme_key, bg_color, base_modifiers, is_popup_active)
    modifiers = base_modifiers.dup
    modifiers.unshift(:dim) if is_popup_active

    style = {
      fg: AppConfig.settings.theme_item(theme_key),
      bg: bg_color
    }
    style[:modifiers] = modifiers unless modifiers.empty?
    style
  end
end
