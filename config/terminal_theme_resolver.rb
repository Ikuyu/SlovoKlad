require 'io/console'

class TerminalThemeResolver
  TIMEOUT = 0.5

  def initialize
    @colors = {}
  end

  def load_colors
    return @colors unless File.exist?('/dev/tty')

    File.open('/dev/tty', 'r+') do |tty|
      tty.raw do |io|
        queries = [
          "\e]10;?\e\\", # Terminal foreground
          "\e]11;?\e\\", # Terminal background
          "\e]12;?\e\\" # Terminal cursor color
        ]

        16.times do |index|
          queries << "\e]4;#{index};?\e\\"
        end

        io.write(queries.join)
        io.flush

        response = +''
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT

        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          ready = IO.select([io], nil, nil, remaining)
          break unless ready

          chunk = io.read_nonblock(4096, exception: false)
          break if chunk == :wait_readable || chunk.nil?

          response << chunk
        end

        parse_response(response)
      end
    end

    @colors
  rescue StandardError
    @colors
  end

  def resolve(theme_definition, fallback_theme)
    result = {}

    theme_definition.each do |key, reference|
      # Derive an empty selection_background from the background later.
      if key.to_s == 'selection_background' &&
         (reference.nil? || reference.to_s.strip.empty?)
        next
      end

      fallback = value_for(fallback_theme, key)
      result[key] = resolve_reference(reference, fallback)
    end

    selection_key =
      theme_definition.keys.find { |key| key.to_s == 'selection_background' } ||
      :selection_background

    selection_reference = value_for(theme_definition, selection_key)

    if selection_reference.nil? || selection_reference.to_s.strip.empty?
      background = value_for(result, :background)

      background ||= resolve_reference(
        value_for(fallback_theme, :background),
        '#808080'
      )

      result[selection_key] = selection_shade(background)
    end

    result
  end

  def shade_selection(background)
    selection_shade(background)
  end

  def apply_terminal_contrast(colors)
    background = parse_color(colors[:background] || colors['background'])
    return colors unless background

    rgb = [1, 3, 5].map do |index|
      background[index, 2].to_i(16)
    end

    linear = rgb.map do |channel|
      value = channel / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end

    luminance =
      0.2126 * linear[0] +
      0.7152 * linear[1] +
      0.0722 * linear[2]

    target = luminance >= 0.5 ? 0 : 255
    amount = 0.65

    search_background_rgb = rgb.map do |channel|
      (channel * (1.0 - amount) + target * amount).round
    end

    search_background = format('#%02X%02X%02X', *search_background_rgb)

    shortcut_color = @colors['ansi.3'] || colors[:window_shortcut_section]

    shortcut_color = ensure_contrast(
      shortcut_color,
      background,
      minimum: 4.5
    )

    colors.merge(
      search_results_background: search_background,
      window_shortcut_section: shortcut_color
    )
  end

  private

  def ensure_contrast(color, background, minimum:)
    foreground_hex = parse_color(color)
    background_hex = parse_color(background)

    return color unless foreground_hex && background_hex
    return foreground_hex if contrast_ratio(foreground_hex, background_hex) >= minimum

    foreground_rgb = [1, 3, 5].map { |i| foreground_hex[i, 2].to_i(16) }
    background_rgb = [1, 3, 5].map { |i| background_hex[i, 2].to_i(16) }

    black = [0, 0, 0]
    white = [255, 255, 255]

    target = if contrast_ratio('#000000', background_hex) >=
                contrast_ratio('#FFFFFF', background_hex)
               black
             else
               white
             end

    low = 0.0
    high = 1.0

    20.times do
      mid = (low + high) / 2.0

      candidate = foreground_rgb.zip(target).map do |original, endpoint|
        (original * (1.0 - mid) + endpoint * mid).round
      end

      candidate_hex = format('#%02X%02X%02X', *candidate)

      if contrast_ratio(candidate_hex, background_hex) >= minimum
        high = mid
      else
        low = mid
      end
    end

    adjusted = foreground_rgb.zip(target).map do |original, endpoint|
      (original * (1.0 - high) + endpoint * high).round
    end

    format('#%02X%02X%02X', *adjusted)
  end

  def contrast_ratio(color_a, color_b)
    luminance_a = color_luminance(color_a)
    luminance_b = color_luminance(color_b)

    lighter, darker = [luminance_a, luminance_b].sort.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  def color_luminance(color)
    rgb = [1, 3, 5].map { |i| color[i, 2].to_i(16) }

    linear = rgb.map do |channel|
      value = channel / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end

    0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
  end

  def resolve_reference(reference, fallback)
    return fallback if reference.nil?

    case reference.to_s
    when /\Aansi\.(\d{1,3})\z/
      index = Regexp.last_match(1).to_i
      index <= 255 ? index : fallback
    when 'terminal.foreground'
      @colors['terminal.foreground'] || fallback
    when 'terminal.background'
      @colors['terminal.background'] || fallback
    when 'terminal.cursor'
      @colors['terminal.cursor'] || fallback
    else
      # Preserve literal colors, such as "#RRGGBB"; use the fallback
      # for unrecognized theme tokens.
      reference.to_s.match?(/\A#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/) ? reference : fallback
    end
  end

  def value_for(hash, key)
    return nil unless hash.is_a?(Hash)

    return hash[key] if hash.key?(key)
    return hash[key.to_s] if hash.key?(key.to_s)

    nil
  end

  def selection_shade(background)
    hex = parse_color(background)
    return background unless hex

    rgb = [1, 3, 5].map { |index| hex[index, 2].to_i(16) }

    linear = rgb.map do |channel|
      value = channel / 255.0
      value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055)**2.4
    end

    luminance = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]

    target = luminance >= 0.18 ? 0 : 255
    amount = 0.23

    adjusted = rgb.map do |channel|
      (channel * (1.0 - amount) + target * amount).round
    end

    format('#%02X%02X%02X', *adjusted)
  end

  def parse_response(response)
    # OSC 10: foreground
    response.scan(/\e\]10;(.*?)(?:\a|\e\\)/m) do |match|
      color = parse_color(match[0])
      @colors['terminal.foreground'] = color if color
    end

    # OSC 11: background
    response.scan(/\e\]11;(.*?)(?:\a|\e\\)/m) do |match|
      color = parse_color(match[0])
      @colors['terminal.background'] = color if color
    end

    # OSC 12: cursor color
    response.scan(/\e\]12;(.*?)(?:\a|\e\\)/m) do |match|
      color = parse_color(match[0])
      @colors['terminal.cursor'] = color if color
    end

    # OSC 4: ANSI palette
    response.scan(/\e\]4;(\d+);(.*?)(?:\a|\e\\)/m) do |index, value|
      color = parse_color(value)
      @colors["ansi.#{index.to_i}"] = color if color && index.to_i.between?(0, 15)
    end
  end

  def parse_color(value)
    value = value.to_s.strip

    # X11-style RGB response:
    # rgb:rrrr/gggg/bbbb
    if (match = value.match(%r{\Argb:([0-9a-f]+)/([0-9a-f]+)/([0-9a-f]+)\z}i))
      channels = match.captures.map do |hex|
        max = (16**hex.length) - 1
        ((hex.to_i(16) * 255.0) / max).round
      end

      return format('#%02X%02X%02X', *channels)
    end

    # Hex response:
    # #RRGGBB or #RGB
    return value.upcase if value.match?(/\A#[0-9a-f]{6}\z/i)

    if (match = value.match(/\A#([0-9a-f])([0-9a-f])([0-9a-f])\z/i))
      return '#' + match.captures.map { |c| c * 2 }.join.upcase
    end

    nil
  end
end
