# frozen_string_literal: true

module TestView
  def render_test_status_screen(tui, frame, region, symbol, text_lines = [])
    icon_lines = [
      ' ╭─────╮',
      "┌─│  #{symbol}  │─┐",
      '│ ╰─────╯ │',
      '└─────────┘'
    ]

    # Zorg dat we gegarandeerd 3 zinnen hebben
    lines = text_lines.dup
    lines << '' while lines.length < 3

    if region.height < 9 || region.width < 15
      fallback_composition = [" #{symbol} #{lines[0]}", " #{lines[1]}", " #{lines[2]}"]
      frame.render_widget(
        tui.paragraph(text: fallback_composition.join("\n"), alignment: :center,
                      style: { fg: AppConfig.settings.theme_item(:foreground),
                               bg: AppConfig.settings.theme_item(:background) }),
        region
      )
      return
    end

    # Calculate the total available blank space (screen height minus 7 content rows).
    total_padding = [region.height - 7, 0].max

    # Verdeel de witruimte over 5 zones: top_marge, gap1, gap2, gap3, bottom_marge
    pad_base = total_padding / 5
    pad_remainder = total_padding % 5

    slots = Array.new(5, pad_base)
    # Verdeel eventuele rest-pixels elegant over de top, bodem en het centrum
    [0, 4, 2, 1, 3].each_with_index do |slot_idx, i|
      slots[slot_idx] += 1 if i < pad_remainder
    end

    top_pad, gap1, gap2, gap3, bottom_pad = slots

    # Samenvoegen tot één perfect gebalanceerde compositie
    full_composition = []
    top_pad.times { full_composition << '' }
    full_composition += icon_lines
    gap1.times { full_composition << '' }
    full_composition << lines[0]
    gap2.times { full_composition << '' }
    full_composition << lines[1]
    gap3.times { full_composition << '' }
    full_composition << lines[2]
    bottom_pad.times { full_composition << '' }

    # Render het paragraph-widget direct over de volledige regio
    frame.render_widget(
      tui.paragraph(text: full_composition.join("\n"),
                    alignment: :center,
                    style: { fg: AppConfig.settings.theme_item(:foreground),
                             bg: AppConfig.settings.theme_item(:background) }),
      region
    )
  end

  # =========================================================================
  # 🎭 UNIVERSELE VECTOR-SMILEY ENGINE (JOUW EIGEN SCHAAL-AS BEHOUDEN!)
  # FIXED: The manually supplied 'radius' argument is authoritative.
  # De engine koppelt de live venster-hoogte puur als een maximale begrenzer.
  # Always fit between the divider and status bar with exactly one row of margin.
  # =========================================================================
  def render_giant_ascii_smiley(tui, frame, region, success, radius = 42)
    # style_happy = { fg: 'green', modifiers: [:bold] }
    # style_sad   = { fg: 'red', modifiers: [:bold] }
    # active_style = success ? style_happy : style_sad
    active_style = AppConfig.settings.theme_item(:foreground)

    canvas_height = region.height
    canvas_width  = region.width

    # 🚨 1. ULTRA-COMPACTE BRANDMUUR TEGEN MINI-VENSTER CRASHES
    if canvas_height < 12 || canvas_width < 30
      mini_smiley = success ? '   (^_^)   ' : '   (T_T)   '
      center_y = region.y + (canvas_height / 2)
      center_x = region.x + [((canvas_width - mini_smiley.length) / 2), 0].max
      line_widget = RatatuiRuby::Text::Line.new(spans: [RatatuiRuby::Text::Span.new(content: mini_smiley,
                                                                                    style: active_style)])
      frame.render_widget(tui.paragraph(text: line_widget, alignment: :left),
                          RatatuiRuby::Layout::Rect.new([center_x, 0].max, [center_y, 0].max,
                                                        [mini_smiley.length, canvas_width].min, 1))
      return
    end

    # =========================================================================
    # 📐 2. JOUW VENSTER-GEKOPPELDE SCHAAL-GRENDEL
    # Preserve the manually supplied radius, but cap it at the
    # remaining available height minus two margin rows.
    # =========================================================================
    max_safe_height = canvas_height - 2

    # 🚨 DE GOUDEN GRENDEL: Pakt jouw handmatige radius, tenzij het venster te klein is!
    active_radius = [radius.to_f, max_safe_height.to_f].min

    # Vanaf hier draait JOUW PURE CODE binnenskamers op de actieve radius!
    r = active_radius
    p = (r / 2).round
    q = [(p / 5.0).round, 1].max
    s = +''

    y = -p

    while (y += 1) < p
      x = -r.to_i

      while (x += 1) < r
        d = c_math_v3(y, r * 2, p)

        # OGEN
        e = c_math_v3(y + q, r / 4.0, q)
        f = e - p
        g = e + p

        # MOND
        mouth_offset = success ? 0 : -p
        h = c_math_v3(y + mouth_offset, r * 1.3, r / 3.0)

        mouth_bottom = (r / 3.0).floor

        mouth =
          y > q &&
          y < mouth_bottom &&
          x > -h &&
          x < h

        s << if x >= d ||
                x <= -d ||
                (x > -g && x < f) ||
                (x < g && x > -f) ||
                mouth
               ' '
             else
               '0'
             end
      end

      s << "\n"
    end

    # =========================================================================
    # 🏢 3. PROJECTIE MATRIX: DE VOLLEDIGE LIFTING-AS NAAR HET SCHERM
    # =========================================================================
    lines = s.split("\n")
    shape_height = lines.length
    shape_width  = lines.first ? lines.first.length : 0

    # start_y berekent live de verticale centrering op basis van JOUW actieve vormhoogte!
    start_y = region.y + [((canvas_height - shape_height) / 2), 0].max

    # Als er genoeg verticale ruimte is, dwingen we hem strak met een marge van 1 onder de divider
    start_y = region.y + 1 if shape_height == max_safe_height

    # Horizontale centrering over de X-as
    start_x = region.x + [((canvas_width - shape_width) / 2), 0].max

    lines.each_with_index do |line_content, r_idx|
      current_y = start_y + r_idx

      # Marge-brandmuur onderin: raak de statusbalk-rand nooit aan
      break if current_y >= (region.y + canvas_height - 1)

      # Gooi de pure string-regel rechtstreeks op de monitor cellen
      line_widget = RatatuiRuby::Text::Line.new(spans: [RatatuiRuby::Text::Span.new(content: line_content,
                                                                                    style: active_style)])
      frame.render_widget(tui.paragraph(text: line_widget, alignment: :left),
                          RatatuiRuby::Layout::Rect.new(start_x, current_y, [line_content.length, canvas_width].min, 1))
    end
  end

  private

  # JOUW EXACTE EN UNIEKE C-METHODE MET VALUE GRENDEL (LETTERLIJK OVERGENOMEN!)
  def c_math_v3(y, w, h)
    value = 1.0 - (y * y).to_f / (h * h)
    return 0 if value <= 0

    ((w / 2.0) * Math.sqrt(value) + 0.5).floor
  end
end
