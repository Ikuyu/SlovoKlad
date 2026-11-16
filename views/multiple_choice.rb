# frozen_string_literal: true

require_relative 'test'

class RatatuiRubyApp
  include TestView

  private

  def render_multiple_choice_view(tui, frame, region)
    @cards_to_test ||= respond_to?(:active_cards) ? active_cards : []
    @test_current_idx ||= 0
    bg_color = AppConfig.settings.theme_item(:background)

    render_multiple_choice_background(frame, region, bg_color)
    return if render_multiple_choice_status(tui, frame, region)

    current_card = @cards_to_test[@test_current_idx]
    return if current_card.nil?

    # 1. First retrieve the card values as plain LTR strings.
    raw_term = current_card.term.to_s
    raw_mean = current_card.meaning.to_s

    # 2. Determine the context and convert it to RTL.
    ctx_value = current_card.context.to_s

    line_x = region.x + 3
    fixed_x = region.x + 5
    fixed_w = region.width - 8
    start_y = region.y + 4
    current_direction = multiple_choice_current_direction
    is_popup_active = multiple_choice_popup_active?

    render_multiple_choice_frame(tui, frame, region, bg_color, is_popup_active)
    return if render_multiple_choice_difficulty_state(tui, frame, region, bg_color)

    term_value = raw_term
    mean_value = raw_mean

    # 5. Pass term_value (which now contains the actual RTL question) to the remaining render call.
    render_multiple_choice_question(tui, frame, region, bg_color, is_popup_active,
                                    current_direction, term_value, mean_value,
                                    fixed_x, fixed_w, start_y)

    # Zorg dat de opties (@test_mc_options) bij het vullen van de view ook door visual_text zijn gegaan
    # (If @test_mc_options is populated elsewhere, pass each string through RatinField.visual_text there.)

    options_start_y = start_y + 4
    render_multiple_choice_options(tui, frame, region, bg_color, is_popup_active,
                                   fixed_x, fixed_w, options_start_y)
    render_multiple_choice_context(tui, frame, region, bg_color, is_popup_active,
                                   ctx_value, fixed_x, fixed_w, options_start_y)
    render_multiple_choice_margin(tui, frame, region, bg_color, line_x, start_y)
  end

  def multiple_choice_current_direction
    return @test_card_directions[@test_current_idx] if defined?(@test_card_directions) && @test_card_directions

    :front
  end

  def multiple_choice_popup_active?
    defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?
  end

  def render_multiple_choice_background(frame, region, bg_color)
    return unless defined?(RatatuiRuby::Widgets::Clear)

    frame.render_widget(RatatuiRuby::Widgets::Clear.new, region)
    # ALWAYS PAD UNCONDITIONALLY FOR A UNIFORM RESULT.
    bg_block = RatatuiRuby::Widgets::Block.new(style: { bg: bg_color }, borders: [:none])
    frame.render_widget(bg_block, region)
  end

  def render_multiple_choice_status(tui, frame, region)
    # SCENARIO A: DE TIJD IS OM!
    if defined?(@test_time_was_up_notified) && @test_time_was_up_notified == true
      lines = [
        AppConfig.settings.language_string(:study_status_screen_multiple_choice),
        "#{AppConfig.settings.language_string(:study_status_screen_failed)}!",
        AppConfig.settings.language_string(:study_status_screen_finished)
      ]
      render_test_status_screen(tui, frame, region, '✕', lines)
      return true
    end

    # SCENARIO B: DE TEST IS VOLTOOID!
    if (defined?(@test_finished_waiting) && @test_finished_waiting == true) || @cards_to_test.empty?
      lines = [
        AppConfig.settings.language_string(:study_status_screen_multiple_choice),
        "#{AppConfig.settings.language_string(:study_status_screen_passed)}!",
        AppConfig.settings.language_string(:study_status_screen_finished)
      ]
      render_test_status_screen(tui, frame, region, '✓', lines)
      return true
    end

    false
  end

  def render_multiple_choice_frame(tui, frame, region, bg_color, is_popup_active)
    # Teken de tab-balken bovenin (altijd op de voorkant-stand)
    header_text_color = AppConfig.settings.theme_item(:table_header_text)
    style_active = multiple_choice_header_style(header_text_color, bg_color, dim: is_popup_active)
    style_dimmed = multiple_choice_header_style(header_text_color, bg_color, dim: true)

    front_active = false
    back_active  = false

    if defined?(@test_mc_answered) && @test_mc_answered == true
      chosen_text = @test_mc_options[@test_selected_option_idx] if @test_selected_option_idx

      if chosen_text == @test_mc_correct_answer
        front_active = true
        back_active  = false
      else
        front_active = false
        back_active  = true
      end
    end

    render_multiple_choice_tabs(
      tui, frame, region, front_active, back_active, style_active, style_dimmed
    )

    full_table_w_mc = [region.width - 1, 1].max
    padding_side_mc = 1
    available_w_mc  = full_table_w_mc - (padding_side_mc * 2) - 1
    left_col_w_mc   = (available_w_mc / 2).floor
    middle_sep_x_mc = region.x + padding_side_mc + left_col_w_mc

    style_junction = { fg: AppConfig.settings.theme_item(:window_border), bg: bg_color,
                       modifiers: is_popup_active ? [:dim] : [] }

    header_sep_char = @show_table_dividers == true ? '│' : ' '
    frame.render_widget(
      tui.paragraph(text: header_sep_char, style: style_junction),
      RatatuiRuby::Layout::Rect.new(middle_sep_x_mc, region.y, 1, 1)
    )

    # 🎯 FIX: Restore the stable original multiplier without bidi side effects.
    frame.render_widget(
      tui.paragraph(text: '─' * region.width, style: style_junction),
      RatatuiRuby::Layout::Rect.new(region.x, region.y + 1, region.width, 1)
    )

    header_divider_y = region.y + 1

    unless @test_awaiting_difficulty
      frame.render_widget(
        tui.paragraph(text: '├', style: style_junction),
        RatatuiRuby::Layout::Rect.new(region.x - 1, header_divider_y, 1, 1)
      )

      frame.render_widget(
        tui.paragraph(text: '┤', style: style_junction),
        RatatuiRuby::Layout::Rect.new(region.x + region.width, header_divider_y, 1, 1)
      )
    end

    if @show_table_dividers == true && !@test_awaiting_difficulty
      frame.render_widget(
        tui.paragraph(text: '┬', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_mc, region.y - 1, 1, 1)
      )

      frame.render_widget(
        tui.paragraph(text: '┴', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_mc, region.y + 1, 1, 1)
      )
    else
      frame.render_widget(
        tui.paragraph(text: '─', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_mc, region.y - 1, 1, 1)
      )

      frame.render_widget(
        tui.paragraph(text: '─', style: style_junction),
        RatatuiRuby::Layout::Rect.new(middle_sep_x_mc, region.y + 1, 1, 1)
      )
    end
  end

  def render_multiple_choice_tabs(tui, frame, region, front_active, back_active,
                                  style_active, style_dimmed)
    front_style = front_active ? style_active : style_dimmed
    front_spans = [
      RatatuiRuby::Text::Span.new(content: '[', style: front_style),
      RatatuiRuby::Text::Span.new(
        content: AppConfig.settings.language_string(:study_multiple_choice_right),
        style: front_style
      ),
      RatatuiRuby::Text::Span.new(content: ']', style: front_style)
    ]
    frame.render_widget(
      tui.paragraph(text: RatatuiRuby::Text::Line.new(spans: front_spans)),
      RatatuiRuby::Layout::Rect.new(region.x + 1, region.y, 12, 1)
    )

    back_style = back_active ? style_active : style_dimmed
    back_spans = [
      RatatuiRuby::Text::Span.new(content: '[', style: back_style),
      RatatuiRuby::Text::Span.new(
        content: AppConfig.settings.language_string(:study_multiple_choice_wrong),
        style: back_style
      ),
      RatatuiRuby::Text::Span.new(content: ']', style: back_style)
    ]
    frame.render_widget(
      tui.paragraph(text: RatatuiRuby::Text::Line.new(spans: back_spans), alignment: :right),
      RatatuiRuby::Layout::Rect.new(region.x, region.y, region.width - 1, 1)
    )
  end

  def multiple_choice_header_style(fg_color, bg_color, dim: false)
    style = { fg: fg_color, bg: bg_color }
    style[:modifiers] = [:dim] if dim
    style
  end

  def render_multiple_choice_difficulty_state(tui, frame, region, bg_color)
    return false unless @test_awaiting_difficulty

    render_multiple_choice_background(frame, region, bg_color)
    lines = [
      AppConfig.settings.language_string(:study_status_screen_multiple_choice),
      "#{@cards_to_test.length} #{AppConfig.settings.language_string(:study_status_screen_flashcards)}",
      AppConfig.settings.language_string(:study_status_screen_start)
    ]
    render_test_status_screen(tui, frame, region, '⏱︎', lines)
    true
  end

  def render_multiple_choice_question(tui, frame, region, bg_color, is_popup_active,
                                      current_direction, term_value, mean_value,
                                      fixed_x, fixed_w, start_y)
    style_base_left = multiple_choice_question_style(
      :studysessions_question, bg_color, is_popup_active, bold: true
    )

    header_text = @test_show_meaning ? AppConfig.settings.language_string(:study_answer) : AppConfig.settings.language_string(:study_question)
    active_text_content = multiple_choice_active_question_text(
      current_direction, term_value, mean_value
    )

    left_label = AppConfig.settings.language_string(:study_question)

    help_symbol = '?'
    remaining_spaces = [fixed_w - (header_text.length + help_symbol.length), 1].max
    padding_string = ' ' * remaining_spaces

    unified_top_line = RatatuiRuby::Text::Line.new(spans: [
                                                     RatatuiRuby::Text::Span.new(content: left_label,
                                                                                 style: style_base_left),
                                                     RatatuiRuby::Text::Span.new(content: padding_string,
                                                                                 style: { bg: bg_color })
                                                   ])

    frame.render_widget(
      tui.paragraph(text: unified_top_line, alignment: :left),
      RatatuiRuby::Layout::Rect.new(fixed_x, start_y, fixed_w, 1)
    )

    raw_text = active_text_content.to_s.gsub(/[\u2066\u2069]/, '')
    question_field = RatinField.new
    question_field.text = raw_text

    visual_clusters = question_field.visual_layout.map { |item| item[:char] }
    is_rtl = question_field.direction == :rtl
    max_width = [fixed_w.to_i, 1].max
    text_width = visual_clusters.sum { |cluster| Unicode::DisplayWidth.of(cluster) }

    if text_width > max_width
      target_width = [max_width - 1, 0].max
      retained_clusters = []
      current_width = 0

      if is_rtl
        visual_clusters.reverse_each do |cluster|
          cluster_width = Unicode::DisplayWidth.of(cluster)
          break if current_width + cluster_width > target_width

          retained_clusters.unshift(cluster)
          current_width += cluster_width
        end
        display_text = "…#{retained_clusters.join}"
      else
        visual_clusters.each do |cluster|
          cluster_width = Unicode::DisplayWidth.of(cluster)
          break if current_width + cluster_width > target_width

          retained_clusters << cluster
          current_width += cluster_width
        end
        display_text = "#{retained_clusters.join}…"
      end
    else
      display_text = visual_clusters.join
    end

    display_width = Unicode::DisplayWidth.of(display_text)
    formatted_mc_content_style = multiple_choice_question_style(
      :studysessions_answer, bg_color, is_popup_active
    )

    active_lang = AppConfig.settings.language
    is_handwritten = AppConfig.settings.handwritten?(active_lang)
    is_latin_or_common = lambda do |char|
      char.to_s.match?(/\A[\p{Latin}0-9\s[:punct:]]\z/)
    end

    # FriBidi has already placed the clusters in visual order; only the
    # starting position changes so the full RTL line sits against the right edge.
    current_qx = is_rtl ? fixed_x + [max_width - display_width, 0].max : fixed_x

    frame.render_widget(
      tui.paragraph(text: "\u2066", style: formatted_mc_content_style),
      RatatuiRuby::Layout::Rect.new(current_qx, start_y + 2, 0, 1)
    )

    display_text.grapheme_clusters.each do |grapheme|
      char_style = formatted_mc_content_style.dup
      first_char = grapheme.chars.first

      if is_handwritten && !is_latin_or_common.call(first_char)
        char_style[:modifiers] = Array(char_style[:modifiers]) | [:italic]
      end

      grapheme_width = Unicode::DisplayWidth.of(grapheme)
      next if grapheme_width.zero?

      frame.render_widget(
        tui.paragraph(text: grapheme, style: char_style),
        RatatuiRuby::Layout::Rect.new(current_qx, start_y + 2, grapheme_width, 1)
      )
      current_qx += grapheme_width
    end

    frame.render_widget(
      tui.paragraph(text: "\u2069", style: formatted_mc_content_style),
      RatatuiRuby::Layout::Rect.new(current_qx, start_y + 2, 0, 1)
    )
  end

  def multiple_choice_active_question_text(current_direction, term_value, mean_value)
    question_is_term = (current_direction == :front) != !!@test_show_meaning
    question_is_term ? term_value : mean_value
  end

  def multiple_choice_question_style(theme_key, bg_color, is_popup_active, bold: false)
    style = {
      fg: AppConfig.settings.theme_item(theme_key),
      bg: bg_color
    }
    modifiers = []
    modifiers << :dim if is_popup_active
    modifiers << :bold if bold
    style[:modifiers] = modifiers unless modifiers.empty?
    style
  end

  def render_multiple_choice_options(tui, frame, region, bg_color, is_popup_active,
                                     fixed_x, fixed_w, options_start_y)
    @test_mc_options ||= []

    active_lang = AppConfig.settings.language
    is_handwritten = AppConfig.settings.handwritten?(active_lang)
    is_latin_or_common = lambda do |char|
      char.to_s.match?(/\A[\p{Latin}0-9\s[:punct:]]\z/)
    end

    @test_mc_options.each_with_index do |raw_option_text, option_index|
      current_option_y = options_start_y + option_index
      break if current_option_y >= (region.y + region.height - 1)

      raw_text = raw_option_text.to_s.gsub(/[\u2066\u2069]/, '')
      option_field = RatinField.new
      option_field.text = raw_text

      visual_clusters = option_field.visual_layout.map { |item| item[:char] }
      is_rtl = option_field.direction == :rtl

      prefix, option_style = multiple_choice_option_feedback(
        raw_option_text, option_index, bg_color, is_popup_active
      )
      prefix_width = Unicode::DisplayWidth.of(prefix)
      available_text_width = [fixed_w.to_i - prefix_width, 0].max
      text_width = visual_clusters.sum { |cluster| Unicode::DisplayWidth.of(cluster) }

      if available_text_width.zero?
        display_text = ''
      elsif text_width > available_text_width
        target_width = [available_text_width - 1, 0].max
        retained_clusters = []
        current_width = 0

        if is_rtl
          visual_clusters.reverse_each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_width

            retained_clusters.unshift(cluster)
            current_width += cluster_width
          end
          display_text = "…#{retained_clusters.join}"
        else
          visual_clusters.each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_width

            retained_clusters << cluster
            current_width += cluster_width
          end
          display_text = "#{retained_clusters.join}…"
        end
      else
        display_text = visual_clusters.join
      end

      frame.render_widget(
        tui.paragraph(text: prefix, style: option_style),
        RatatuiRuby::Layout::Rect.new(fixed_x, current_option_y, prefix_width, 1)
      )

      display_width = Unicode::DisplayWidth.of(display_text)
      current_ox = if is_rtl
                     fixed_x + [fixed_w.to_i - display_width, prefix_width].max
                   else
                     fixed_x + prefix_width
                   end

      frame.render_widget(
        tui.paragraph(text: "\u2066", style: option_style),
        RatatuiRuby::Layout::Rect.new(current_ox, current_option_y, 0, 1)
      )

      display_text.grapheme_clusters.each do |grapheme|
        char_style = option_style.dup
        first_char = grapheme.chars.first

        if is_handwritten && !is_latin_or_common.call(first_char)
          char_style[:modifiers] = Array(char_style[:modifiers]) | [:italic]
        end

        grapheme_width = Unicode::DisplayWidth.of(grapheme)
        next if grapheme_width.zero?

        frame.render_widget(
          tui.paragraph(text: grapheme, style: char_style),
          RatatuiRuby::Layout::Rect.new(current_ox, current_option_y, grapheme_width, 1)
        )
        current_ox += grapheme_width
      end

      frame.render_widget(
        tui.paragraph(text: "\u2069", style: option_style),
        RatatuiRuby::Layout::Rect.new(current_ox, current_option_y, 0, 1)
      )
    end
  end

  def multiple_choice_option_feedback(option_text, option_index, bg_color, is_popup_active)
    prefix = "[#{option_index + 1}] "
    option_style = multiple_choice_option_style(bg_color, is_popup_active)
    return [prefix, option_style] unless defined?(@test_mc_answered) && @test_mc_answered == true

    is_correct = (option_text.to_s == @test_mc_correct_answer.to_s)
    is_chosen = (@test_selected_option_idx == option_index)
    chosen_text = @test_mc_options[@test_selected_option_idx] if @test_selected_option_idx
    was_choice_correct = (chosen_text == @test_mc_correct_answer)

    if was_choice_correct && is_correct
      prefix = '[✓] '
    elsif is_chosen && !is_correct
      prefix = '[✕] '
      option_style = multiple_choice_option_style(
        bg_color, is_popup_active, dim: true, crossed_out: true
      )
    elsif !was_choice_correct && is_correct
      # Show the correct option even when the selected answer was wrong.
      prefix = '[✓] '
    else
      option_style = multiple_choice_option_style(bg_color, is_popup_active, dim: true)
    end

    [prefix, option_style]
  end

  def multiple_choice_option_style(bg_color, is_popup_active, dim: nil, crossed_out: false)
    dim = is_popup_active if dim.nil?
    style = {
      fg: AppConfig.settings.theme_item(:foreground),
      bg: bg_color
    }
    modifiers = []
    modifiers << :dim if dim
    modifiers << :crossed_out if crossed_out
    style[:modifiers] = modifiers unless modifiers.empty?
    style
  end

  def render_multiple_choice_context(tui, frame, region, bg_color, is_popup_active,
                                     ctx_value, fixed_x, fixed_w, options_start_y)
    return unless @test_show_context

    context_y = options_start_y + 5
    return unless context_y < (region.y + region.height)

    context_style = multiple_choice_context_style(bg_color, is_popup_active)
    context_label_span = RatatuiRuby::Text::Span.new(
      content: AppConfig.settings.language_string(:study_context),
      style: context_style
    )

    max_context_width = [fixed_w.to_i - 9, 1].max
    frame.render_widget(
      tui.paragraph(text: RatatuiRuby::Text::Line.new(spans: [context_label_span])),
      RatatuiRuby::Layout::Rect.new(fixed_x, context_y, 9, 1)
    )

    italic_style = multiple_choice_context_style(bg_color, is_popup_active, italic: true)
    raw_context = ctx_value.to_s.gsub(/[\u2066\u2069]/, '')
    context_field = RatinField.new
    context_field.text = raw_context

    active_lang = AppConfig.settings.language
    is_handwritten = AppConfig.settings.handwritten?(active_lang)
    is_latin_or_common = lambda do |char|
      char.to_s.match?(/\A[\p{Latin}0-9\s[:punct:]]\z/)
    end

    if raw_context.strip.empty?
      missing_context = AppConfig.settings.language_string(:study_context_not_available)
      value_field = RatinField.new
      value_field.text = missing_context
      display_clusters = value_field.visual_layout.map { |item| item[:char] }
      is_rtl = value_field.direction == :rtl
    else
      display_clusters = context_field.visual_layout.map { |item| item[:char] }
      is_rtl = context_field.direction == :rtl
      text_width = display_clusters.sum { |cluster| Unicode::DisplayWidth.of(cluster) }

      if text_width > max_context_width
        target_width = [max_context_width - 1, 0].max
        retained_clusters = []
        current_width = 0

        if is_rtl
          display_clusters.reverse_each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_width

            retained_clusters.unshift(cluster)
            current_width += cluster_width
          end
          display_clusters = ["…#{retained_clusters.join}"]
        else
          display_clusters.each do |cluster|
            cluster_width = Unicode::DisplayWidth.of(cluster)
            break if current_width + cluster_width > target_width

            retained_clusters << cluster
            current_width += cluster_width
          end
          display_clusters = ["#{retained_clusters.join}…"]
        end
      end
    end

    context_value = display_clusters.join
    display_width = Unicode::DisplayWidth.of(context_value)
    current_cx = fixed_x + 9
    current_cx += [max_context_width - display_width, 0].max if is_rtl

    frame.render_widget(
      tui.paragraph(text: "\u2066", style: italic_style),
      RatatuiRuby::Layout::Rect.new(current_cx, context_y, 0, 1)
    )

    context_value.grapheme_clusters.each do |grapheme|
      char_style = italic_style.dup
      first_char = grapheme.chars.first

      if is_handwritten && !is_latin_or_common.call(first_char)
        char_style[:modifiers] = Array(char_style[:modifiers]) | [:italic]
      end

      grapheme_width = Unicode::DisplayWidth.of(grapheme)
      next if grapheme_width.zero?

      frame.render_widget(
        tui.paragraph(text: grapheme, style: char_style),
        RatatuiRuby::Layout::Rect.new(current_cx, context_y, grapheme_width, 1)
      )
      current_cx += grapheme_width
    end

    frame.render_widget(
      tui.paragraph(text: "\u2069", style: italic_style),
      RatatuiRuby::Layout::Rect.new(current_cx, context_y, 0, 1)
    )
  end

  def multiple_choice_context_line(ctx_value, max_ctx_chars, context_label_span,
                                   bg_color, is_popup_active)
    italic_style = multiple_choice_context_style(bg_color, is_popup_active, italic: true)
    context_value = if ctx_value.to_s.strip.empty?
                      AppConfig.settings.language_string(:study_context_not_available)
                    else
                      # 🎯 FIX: Because ctx_value has already passed through visual_text,
                      # moeten we zorgen dat de afkappingslogica de pure bidi-detectie correct uitvoert.
                      multiple_choice_truncate_text(ctx_value, max_ctx_chars + 1)
                    end
    value_span = RatatuiRuby::Text::Span.new(content: context_value, style: italic_style)
    RatatuiRuby::Text::Line.new(spans: [context_label_span, value_span])
  end

  def multiple_choice_truncate_text(value, max_chars)
    text = value.to_s
    clusters = text.grapheme_clusters
    return text unless clusters.length > max_chars

    is_pure_bidi = text =~ /\A[\p{Hebrew}\p{Arabic}\p{M}\s[:punct:]\u200E\u200F\u2068\u2069]+\z/
    segment = clusters[0...(max_chars - 1)]

    if is_pure_bidi
      segment[0] = '…' # Zet het afbreekteken links neer
    else
      segment[-1] = '…' # Standaard rechts
    end

    segment.join
  end

  def multiple_choice_context_style(bg_color, is_popup_active, italic: false)
    style = {
      fg: AppConfig.settings.theme_item(:studysessions_context),
      bg: bg_color
    }
    modifiers = []
    modifiers << :italic if italic
    modifiers << :dim if is_popup_active
    style[:modifiers] = modifiers unless modifiers.empty?
    style
  end

  def render_multiple_choice_margin(tui, frame, region, bg_color, line_x, start_y)
    end_offset_y = 7
    end_offset_y += 2 if @test_show_context

    (0..end_offset_y).each do |offset_y|
      current_line_y = start_y + offset_y
      break if current_line_y >= (region.y + region.height)

      frame.render_widget(
        tui.paragraph(text: '▍', style: { fg: AppConfig.settings.theme_item(:studysessions_margin_line),
                                          bg: bg_color }),
        RatatuiRuby::Layout::Rect.new(line_x, current_line_y, 1, 1)
      )
    end
  end
end
