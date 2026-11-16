# frozen_string_literal: true

require_relative '../controllers/concerns/font_style_helper'

class RatatuiRubyApp
  include FontStyleHelper

  private

  def render_memory_view(tui, frame, region)
    if !(defined?(@memory_cards) && @memory_cards) && @current_study_mode == :memory &&
       @test_finished_waiting != true
      cards_list = respond_to?(:active_cards) ? active_cards : (@cards_to_test || [])
      initialize_memory_game(cards_list) if respond_to?(:initialize_memory_game, true)
    end

    return unless @memory_cards

    visible_cards = @memory_cards

    # Kleuren en instellingen.
    settings = AppConfig.settings
    background_color = settings.theme_item(:background)
    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)
    is_latin_or_common = lambda do |char|
      char =~ /\A[\p{Latin}0-9\s[:punct:]]\z/
    end

    return if render_memory_completion_state(tui, frame, region, settings)

    # --------------------------------------------------
    # 🎯 1. BOVENZIJDE: Header bar initialisatie
    # We reserveren exact 1 regel bovenin voor de gecentreerde inhoud.
    # --------------------------------------------------
    # Header: bij de start gecentreerd, daarna gesplitst.
    header_rect = RatatuiRuby::Layout::Rect.new(region.x, region.y, region.width, 1)

    active_idx =
      @memory_second_flipped_idx ||
      @memory_first_flipped_idx ||
      (
        @memory_cards.index(@memory_pending_match.first) if @memory_pending_match
      )

    if active_idx && @memory_cards[active_idx]
      left_text = @memory_header_left_text.to_s
      right_text = @memory_header_right_text.to_s

      middle_x = region.x + (region.width / 2)

      left_width = middle_x - region.x - 2
      right_width = (region.x + region.width - 1) - (middle_x + 2)

      left_rect = RatatuiRuby::Layout::Rect.new(
        region.x + 1, region.y, [left_width, 1].max, 1
      )

      right_rect = RatatuiRuby::Layout::Rect.new(
        middle_x + 2, region.y, [right_width, 1].max, 1
      )

      # ----------------
      # LEFT HEADER TEXT
      # ----------------
      left_color = settings.theme_item(:foreground) # must be the same as the key-combination color of the 1st pick

      render_memory_header_text(
        tui, frame, left_rect, left_text, :left, settings,
        background_color, is_handwritten, left_color, []
      )

      # -----------------
      # RIGHT HEADER TEXT
      # -----------------
      right_color = settings.theme_item(:foreground) # match color && memory_second_flipped_idx(key-combination color of the 2nd pick()

      crossed_out_right_text =
        if @memory_second_flipped_idx &&
           @memory_first_flipped_idx &&
           @memory_cards[@memory_first_flipped_idx][:id] !=
           @memory_cards[@memory_second_flipped_idx][:id]
          right_text
        end

      # right_modifiers = @memory_pending_match ? [:bold] : %i[bold reversed]

      render_memory_header_text(
        tui, frame, right_rect, right_text, :right, settings,
        background_color, is_handwritten, right_color, [], crossed_out_right_text
      )

      # ------------------
      # HORIZONTAL DIVIDER
      # ------------------
      frame.render_widget(
        tui.paragraph(
          text: @show_table_dividers ? '│' : ' ',
          style: { fg: settings.theme_item(:window_border) }
        ),
        RatatuiRuby::Layout::Rect.new(middle_x, region.y, 1, 1)
      )
    else
      # Keep the intro message centered without a middle divider.
      header_text =
        @memory_message ||
        "#{settings.language_string(:statusbar_study_memory_init_msg)}!"

      render_memory_header_text(
        tui, frame, header_rect, header_text, :center, settings,
        background_color, is_handwritten
      )
    end

    header_divider_y = region.y + 1
    style_dimmed = { fg: settings.theme_item(:window_border) }

    frame.render_widget(
      tui.paragraph(text: '─' * region.width, style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(
        region.x, header_divider_y, region.width, 1
      )
    )

    frame.render_widget(
      tui.paragraph(text: '├', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(region.x - 1, header_divider_y, 1, 1)
    )

    frame.render_widget(
      tui.paragraph(text: '┤', style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(
        region.x + region.width, header_divider_y, 1, 1
      )
    )

    if active_idx && @memory_cards[active_idx]
      middle_x = region.x + (region.width / 2)

      frame.render_widget(
        tui.paragraph(text: @show_table_dividers ? '┴' : '─', style: style_dimmed),
        RatatuiRuby::Layout::Rect.new(middle_x, header_divider_y, 1, 1)
      )

      if @show_table_dividers
        frame.render_widget(
          tui.paragraph(text: @show_table_dividers ? '┬' : '─', style: style_dimmed),
          RatatuiRuby::Layout::Rect.new(middle_x, region.y - 1, 1, 1)
        )
      end
    end

    # ---------------------------------------------------------------------------------
    # 📐 Geometrieberekeningen (Ondergrens schuift nog 1 regel op voor de divider line)
    # ---------------------------------------------------------------------------------
    card_w = 4
    card_h = 3
    spacing_x = 1
    spacing_y = 0

    # Move the card start point (base_data_y) directly below the new divider (+2 offset from region.y).
    base_data_y = region.y + 2
    hard_boundary_y = @test_show_context ? (region.y + region.height - 2) : (region.y + region.height)

    start_x = region.x + 1
    start_y = base_data_y

    @memory_scroll_offset = [@memory_scroll_offset.to_i, 0].max

    # --------------------------------------------------
    # 2. KAARTEN: Vloeiend Button-verloop
    # --------------------------------------------------

    current_x = start_x
    current_y = start_y

    max_row_height = card_h + spacing_y
    available_width = (region.x + region.width - 1) - start_x

    cards_per_row = [
      ((available_width + spacing_x).to_f / (card_w + spacing_x)).floor,
      1
    ].max

    @memory_cards_per_row = cards_per_row

    total_rows = (visible_cards.length.to_f / cards_per_row).ceil

    visible_window_height = [
      hard_boundary_y - base_data_y,
      0
    ].max

    visible_rows = [
      ((visible_window_height + spacing_y).to_f / max_row_height).floor,
      0
    ].max

    @memory_max_scroll = [total_rows - visible_rows, 0].max

    # Bewaar de grid-afmetingen voor de statusbalk-paginering.
    @memory_total_rows = total_rows
    @memory_visible_rows = visible_rows

    @memory_scroll_offset = [
      @memory_scroll_offset.to_i,
      @memory_max_scroll
    ].min

    visible_cards.each_with_index do |card, idx|
      row = idx / cards_per_row
      column = idx % cards_per_row

      current_x = start_x + column * (card_w + spacing_x)
      current_y = start_y + row * max_row_height

      visual_y = current_y - (@memory_scroll_offset * max_row_height)

      is_card_visible =
        visual_y >= base_data_y &&
        visual_y + card_h <= hard_boundary_y

      next unless is_card_visible && (!card[:matched] || card[:flipped])

      button_rect = RatatuiRuby::Layout::Rect.new(
        current_x, visual_y, card_w, card_h
      )

      content_text = card[:coord].to_s.strip.upcase

      is_selected =
        [@memory_first_flipped_idx, @memory_second_flipped_idx].include?(idx)

      border_style = {
        fg: settings.theme_item(:window_border),
        bg: background_color,
        modifiers: is_selected ? [] : [:dim]
      }

      is_matching =
        card[:matched] ||
        (
          @memory_pending_match &&
          @memory_pending_match.include?(card)
        )

      text_style =
        if card[:flipped] && is_matching
          {
            fg: settings.theme_item(:foreground), # match color
            bg: background_color,
            modifiers: []
          }
        elsif card[:flipped] && idx == @memory_first_flipped_idx
          {
            fg: settings.theme_item(:foreground), # key-combination color of the 1st pick
            bg: background_color,
            modifiers: []
          }
        elsif card[:flipped] && idx == @memory_second_flipped_idx
          {
            fg: settings.theme_item(:foreground), # key-combination color of the 2nd pick
            bg: background_color,
            modifiers: [:crossed_out]
          }
        else
          {
            fg: settings.theme_item(:foreground), # remaining cards
            bg: background_color,
            modifiers: [:dim]
          }
        end

      button_box = tui.block(
        borders: [:all],
        border_style: border_style,
        border_type: settings.corner
      )

      frame.render_widget(button_box, button_rect)

      paragraph = tui.paragraph(
        text: content_text,
        alignment: :center,
        style: text_style
      )

      frame.render_widget(paragraph, button_box.inner(button_rect))
    end

    # --------------------------------------------------
    # Scrollbar aan de rechterzijde
    # --------------------------------------------------
    render_memory_scrollbar(
      tui, frame, region,
      total_rows,
      @memory_scroll_offset,
      visible_rows,
      visible_window_height,
      base_data_y
    )

    # --------------------------------------------------
    # Contextpaneel
    # --------------------------------------------------
    return unless @test_show_context

    render_memory_context_panel(
      tui, frame, settings, region, base_data_y, hard_boundary_y
    )
  end

  def render_memory_header_text(
    tui, frame, rect, text, alignment, settings,
    background_color, is_handwritten, text_color = nil,
    modifiers = [], crossed_out_text = nil
  )
    raw = text.to_s.gsub(/[\u2066\u2069]/, '')

    field = RatinField.new
    field.text = raw

    clusters = field.visual_layout.map { |item| item[:char] }
    is_rtl = field.direction == :rtl

    max_width = [rect.width.to_i, 1].max
    visual_width = Unicode::DisplayWidth.of(clusters.join)

    if visual_width > max_width
      target_width = [max_width - 1, 0].max
      retained = []
      current_width = 0

      if is_rtl
        clusters.reverse_each do |cluster|
          width = Unicode::DisplayWidth.of(cluster)
          break if current_width + width > target_width

          retained.unshift(cluster)
          current_width += width
        end

        display_text = "…#{retained.join}"
      else
        clusters.each do |cluster|
          width = Unicode::DisplayWidth.of(cluster)
          break if current_width + width > target_width

          retained << cluster
          current_width += width
        end

        display_text = "#{retained.join}…"
      end
    else
      display_text = clusters.join
    end

    display_text = "\u2066#{display_text}\u2069"

    style = {
      fg: text_color || settings.theme_item(:table_header_text),
      bg: background_color,
      modifiers: modifiers
    }

    style[:modifiers] |= [:italic] if is_handwritten && raw.match?(/[^\p{Latin}0-9\s[:punct:]]/)

    spans = []

    if crossed_out_text && !crossed_out_text.empty?
      parts = display_text.split(crossed_out_text, -1)

      parts.each_with_index do |part, index|
        spans << tui.span(content: part, style: style) unless part.empty?

        next unless index < parts.length - 1

        spans << tui.span(
          content: crossed_out_text,
          style: style.merge(
            modifiers: style[:modifiers] | [:crossed_out]
          )
        )
      end
    else
      spans << tui.span(content: display_text, style: style)
    end

    paragraph = tui.paragraph(
      text: [tui.line(spans: spans)],
      alignment: alignment,
      style: { bg: background_color },
      wrap: false
    )

    frame.render_widget(paragraph, rect)
  end

  def render_memory_scrollbar(tui, frame, region, total_rows,
                              scroll_offset, visible_rows,
                              visible_height, base_data_y)
    total_rows = total_rows.to_i
    visible_rows = visible_rows.to_i
    track_height = visible_height.to_i

    return if total_rows <= visible_rows
    return if track_height <= 0

    settings = AppConfig.settings

    border_color = settings.theme_item(:window_border)

    scrollbar_style = {
      fg: border_color,
      modifiers: []
    }

    # Grootte van de thumb op basis van de verhouding
    # tussen het totale aantal rijen en het zichtbare aantal rijen.
    thumb_height = (
      track_height.to_f * visible_rows / total_rows
    ).round

    thumb_height = [[thumb_height, 1].max, track_height].min

    max_offset =
      if total_rows > 0 && visible_rows > 0
        (total_rows - 1).div(visible_rows) * visible_rows
      else
        0
      end
    max_thumb_top = track_height - thumb_height

    current_offset = [
      [scroll_offset.to_i, 0].max,
      max_offset
    ].min

    # Calculate the thumb position.
    # Bij de laatste scrollpositie eindigt hij exact onderaan.
    thumb_top = if max_offset.zero?
                  0
                elsif current_offset == max_offset
                  max_thumb_top
                else
                  (
                    max_thumb_top.to_f * current_offset / max_offset
                  ).round
                end

    thumb_bottom = thumb_top + thumb_height - 1

    # Draw the scrollbar one row at a time.
    track_height.times do |line|
      symbol =
        if line >= thumb_top && line <= thumb_bottom
          '┆'
        elsif line.zero?
          thumb_top.zero? ? '┆' : '│'
        elsif line == track_height - 1
          thumb_bottom == track_height - 1 ? '┆' : '│'
        else
          '│'
        end

      frame.render_widget(
        tui.paragraph(text: symbol, style: scrollbar_style),
        RatatuiRuby::Layout::Rect.new(
          region.x + region.width,
          base_data_y + line,
          1,
          1
        )
      )
    end
  end

  def render_memory_context_panel(tui, frame, settings, region, base_data_y, hard_boundary_y)
    bottom_divider_y = hard_boundary_y
    context_text_y = bottom_divider_y + 1
    style_dimmed = { fg: settings.theme_item(:window_border) }

    frame.render_widget(
      tui.paragraph(text: '─' * region.width, style: style_dimmed),
      RatatuiRuby::Layout::Rect.new(region.x, bottom_divider_y, region.width, 1)
    )

    frame.render_widget(tui.paragraph(text: '├', style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x - 1, bottom_divider_y, 1, 1))
    frame.render_widget(tui.paragraph(text: '┤', style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x + region.width, bottom_divider_y, 1, 1))

    left_corner = settings.corner == :rounded ? '╰' : '└'
    right_corner = settings.corner == :rounded ? '╯' : '┘'

    frame.render_widget(tui.paragraph(text: left_corner, style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x - 1, region.y + region.height, 1, 1))
    frame.render_widget(tui.paragraph(text: right_corner, style: style_dimmed),
                        RatatuiRuby::Layout::Rect.new(region.x + region.width, region.y + region.height, 1, 1))

    active_card = nil

    if @memory_cards
      active_idx =
        @memory_second_flipped_idx ||
        @memory_first_flipped_idx ||
        (@memory_cards.index(@memory_pending_match.first) if @memory_pending_match)
      active_card = @memory_cards[active_idx] if active_idx
    end

    context_raw = ''
    if active_card && defined?(@cards_to_test) && @cards_to_test
      orig_card = @cards_to_test.find { |card| card.object_id == active_card[:id] }
      context_raw = orig_card.context.to_s if orig_card
    end

    context_style = { fg: settings.theme_item(:studysessions_context), bg: settings.theme_item(:background) }
    label_text = settings.language_string(:study_context).to_s
    label_width = Unicode::DisplayWidth.of(label_text)

    frame.render_widget(
      tui.paragraph(text: label_text, style: context_style),
      RatatuiRuby::Layout::Rect.new(region.x + 1, context_text_y, label_width, 1)
    )

    context_value =
      if context_raw.strip.empty?
        settings.language_string(:study_context_not_available).to_s
      else
        context_raw.strip
      end

    value_x = region.x + label_width + 1
    value_width = [region.width - label_width - 2, 1].max

    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)

    context_field = RatinField.new
    context_field.text = context_value.gsub(/[\u2066\u2069]/, '')

    visual_clusters = context_field.visual_layout.map { |item| item[:char] }
    is_rtl = context_field.direction == :rtl
    visual_width = Unicode::DisplayWidth.of(visual_clusters.join)

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

    display_context = "\u2066#{display_context}\u2069"

    value_style = context_style.merge(modifiers: [:italic])

    if is_handwritten &&
       context_value.match?(/[^\p{Latin}0-9\s[:punct:]]/)
      value_style[:modifiers] |= [:italic]
    end

    frame.render_widget(
      tui.paragraph(
        text: display_context,
        style: value_style,
        alignment: is_rtl ? :right : :left,
        wrap: false
      ),
      RatatuiRuby::Layout::Rect.new(
        value_x, context_text_y, value_width, 1
      )
    )
  end

  def render_memory_completion_state(tui, frame, region, settings)
    memory_active = defined?(@current_study_mode) && @current_study_mode == :memory
    finished = defined?(@test_finished_waiting) && @test_finished_waiting == true
    return false unless memory_active && (finished || (@memory_cards && @memory_cards.empty?))

    lines = [
      settings.language_string(:study_status_screen_play_memory),
      "#{settings.language_string(:study_status_screen_memory_game_completed)}.",
      settings.language_string(:study_status_screen_finished)
    ]
    render_test_status_screen(tui, frame, region, '✓', lines)
    true
  end
end
