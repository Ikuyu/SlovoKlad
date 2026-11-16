# frozen_string_literal: true

require 'fileutils'

module StartupView
  private

  # Parse the fixed FIGfont header, then read glyphs in blocks of `height` rows.
  def parse_local_flf_font(font_path)
    return nil unless File.file?(font_path)

    lines = File.readlines(font_path, encoding: 'UTF-8').map do |line|
      line.chomp.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end
    return nil if lines.empty?

    # FIGfont header: signature/hardblank followed by height and comment_lines.
    header = lines.first
    return nil unless header.start_with?('flf2a')

    header_parts = header[6..].to_s.split
    hardblank = header[5] || '$'
    height = begin
      Integer(header_parts[0], 10)
    rescue StandardError
      0
    end
    comment_lines = begin
      Integer(header_parts[4], 10)
    rescue StandardError
      0
    end
    return nil unless height.positive? && comment_lines >= 0

    # Comment_Lines counts the exact number of rows after the header, including blank rows.
    index = 1 + comment_lines
    return nil if index >= lines.length

    font_matrix = {}
    next_ascii_code = 32

    # FIGcharacters can follow each other directly or be preceded
    # by a code-tag line (e.g. 196 or 0x00C4). Consume each glyph individually,
    # not with each_slice(height), which would treat code tags as glyph rows.
    while index < lines.length
      code = nil
      tag = lines[index].match(/\A\s*(0x[0-9a-fA-F]+|\d+)\s+\z/)
      if tag
        token = tag[1]
        code = token.start_with?('0x') ? token.to_i(16) : token.to_i
        index += 1
      else
        code = next_ascii_code
      end

      break if index + height > lines.length

      glyph_rows = lines[index, height]
      index += height
      next_ascii_code = code + 1 unless tag

      # The FIGfont endmark appears at the end of each row; the final glyph row
      # conventionally uses two endmarks. Determine the character per glyph.
      endmark = glyph_rows.last.to_s[-1]
      next if endmark.nil?

      cleaned_rows = glyph_rows.map do |row|
        row.sub(/#{Regexp.escape(endmark)}{1,2}\z/, '').gsub(hardblank, ' ')
      end

      begin
        font_matrix[code.chr(Encoding::UTF_8)] = cleaned_rows if code >= 0
      rescue RangeError, ArgumentError
        # Skip invalid code tags without blocking the entire font.
      end
    end

    return nil if font_matrix.empty?

    { matrix: font_matrix, height: height }
  end

  # 📊 DE GEZUIVERDE STRIPING EN CENTRERINGS ENGINE
  def build_dynamic_flf_banner(app_title, font_data, spacing)
    matrix = font_data[:matrix]
    height = font_data[:height]

    letter_widths = {}
    app_title.each_char do |char|
      letter_widths[char] = if matrix.key?(char)
                              matrix[char].map(&:length).max
                            else
                              4
                            end
    end

    banner_lines = Array.new(height) { +'' }

    (0...height).each do |line_idx|
      app_title.each_char.with_index do |char, char_idx|
        if matrix.key?(char)
          raw_segment = matrix[char][line_idx].to_s
          padding = [letter_widths[char] - raw_segment.length, 0].max

          banner_lines[line_idx] << raw_segment
          banner_lines[line_idx] << (' ' * padding)
        else
          banner_lines[line_idx] << (' ' * letter_widths[char])
        end

        banner_lines[line_idx] << (' ' * spacing) if char_idx < app_title.length - 1
      end
    end

    total_width = banner_lines.first.to_s.length
    [banner_lines, total_width, height]
  end

  def render_startup_screen_view(tui, frame, region)
    unless @startup_chime_played
      SoundManager.play(:chime)
      @startup_chime_played = true
    end

    bg_color = AppConfig.settings.theme_item(:background)

    frame.render_widget(RatatuiRuby::Widgets::Clear.new, region) if defined?(RatatuiRuby::Widgets::Clear)
    bg_block = RatatuiRuby::Widgets::Block.new(style: { bg: bg_color }, borders: [:none])
    frame.render_widget(bg_block, region)

    app_title = @app_name.to_s
    reg_width = region.width.to_i
    reg_height = region.height.to_i

    configured_font = AppConfig.settings.startup_screen_font_name || 'colossal.flf'
    font_path = File.expand_path(
      File.join('..', 'fonts', configured_font),
      __dir__
    )
    font_data = parse_local_flf_font(font_path)

    text_style = { fg: AppConfig.settings.theme_item(:table_header_text), bg: bg_color, modifiers: [:bold] }
    prompt_style = { fg: AppConfig.settings.theme_item(:window_shortcut_section), bg: bg_color,
                     modifiers: %i[dim] }

    # Safe status fallback when the .flf file is not yet present on disk.
    # 🎯 FALLBACK 1: If the .flf file is missing from disk.
    if font_data.nil?
      fallback_lines = [
        "#{app_title}",
        '', # 🟢 Lege regel voor ademruimte
        "[Font missing at: #{File.basename(font_path)}]",
        '', # 🟢 Lege regel voor ademruimte
        '— Press any key to continue —'
      ]

      start_y = region.y + [((reg_height - fallback_lines.length) / 2).floor, 0].max
      fallback_lines.each_with_index do |line_content, idx|
        line_w = line_content.length
        centered_x = region.x + [((reg_width - line_w) / 2).floor, 0].max

        # 🔐 SAFETY GUARD: Draw only within the physical window bounds.
        next unless (start_y + idx) < (region.y + reg_height)

        frame.render_widget(
          tui.paragraph(text: line_content, style: idx.zero? ? text_style : prompt_style),
          RatatuiRuby::Layout::Rect.new(centered_x, start_y + idx, [line_w, reg_width].min, 1)
        )
      end
      return
    end

    # CONFIGURATION ARGUMENT: Change the third argument (currently '1') to add extra spacing between letters.
    final_ascii_lines, total_ascii_width, font_height = build_dynamic_flf_banner(app_title, font_data, 1)

    trailing_empty_rows = 0
    final_ascii_lines.reverse_each do |line|
      break unless line.strip.empty?

      trailing_empty_rows += 1
    end

    effective_visual_height = font_height - trailing_empty_rows
    effective_visual_height = 1 if effective_visual_height <= 0

    # VEILIGHEIDS-POORTWACHTER VOOR RESIZING:
    if reg_height < (effective_visual_height + 8) || reg_width < (total_ascii_width + 6)
      fallback_lines = [
        "#{app_title}",
        '',
        "[Window too small for font: #{File.basename(font_path)}]",
        '',
        '— Press any key to continue —'
      ]

      start_y = region.y + [((reg_height - fallback_lines.length) / 2).floor, 0].max
      fallback_lines.each_with_index do |line_content, idx|
        line_w = line_content.length
        centered_x = region.x + [((reg_width - line_w) / 2).floor, 0].max

        # 🔐 SAFETY GUARD: Draw only within the physical window bounds.
        next unless (start_y + idx) < (region.y + reg_height)

        frame.render_widget(
          tui.paragraph(text: line_content, style: idx.zero? ? text_style : prompt_style),
          RatatuiRuby::Layout::Rect.new(centered_x, start_y + idx, [line_w, reg_width].min, 1)
        )
      end
      return
    end

    start_y = region.y + ((reg_height - (effective_visual_height + 4)) / 2).floor
    prompt_style = { fg: AppConfig.settings.theme_item(:window_shortcut_section), bg: bg_color,
                     modifiers: %i[dim] }

    final_ascii_lines.each_with_index do |line_content, line_idx|
      next if line_idx >= effective_visual_height

      centered_x = region.x + ((reg_width - total_ascii_width) / 2).floor
      frame.render_widget(
        tui.paragraph(text: line_content, style: text_style),
        RatatuiRuby::Layout::Rect.new(centered_x, start_y + line_idx, total_ascii_width, 1)
      )
    end

    # Font notice at + 1.
    clean_font_display = "Font: #{File.basename(configured_font, '.flf')}"
    font_msg_w = clean_font_display.length
    font_msg_x = region.x + ((reg_width - font_msg_w) / 2).floor

    # frame.render_widget(
    #  tui.paragraph(text: clean_font_display, style: prompt_style),
    #  RatatuiRuby::Layout::Rect.new(font_msg_x, start_y + effective_visual_height + 1, font_msg_w, 1)
    # )

    # Keep the dismiss prompt exactly 3 rows below the effective height.
    prompt_msg = '— Press any key to continue —'
    prompt_w = prompt_msg.length
    prompt_x = region.x + ((reg_width - prompt_w) / 2).floor

    frame.render_widget(
      tui.paragraph(text: prompt_msg, style: prompt_style),
      RatatuiRuby::Layout::Rect.new(prompt_x, start_y + effective_visual_height + 6, prompt_w, 1)
    )
  end
end
