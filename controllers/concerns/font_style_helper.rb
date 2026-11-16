# frozen_string_literal: true

module FontStyleHelper
  private

  # =========================================================================
  # 🎯 UNIVERSELE TAAL-GEÏSOLEERDE SPAN SPLITTER
  # 👉 Beschikbaar voor álle schermen (Tabel, Tree, Drill, Quiz, Memory, etc.)
  #    Vangt alle Latijnse letters met accenten (é, ë, ç, etc.) kogelvrij op.
  #    All digits, Western letters, spaces, and punctuation remain upright.
  # =========================================================================
  def build_study_handwritten_line(tui, raw_value, base_style, is_handwritten)
    text = raw_value.to_s

    is_latin_or_common = lambda do |char|
      # \p{Latin} vangt alle letters met accenten (é, ë, ç, etc.) kogelvrij op!
      char =~ /\A[\p{Latin}0-9\s[:punct:]]\z/
    end

    build_span_style = lambda do |content_str|
      style_copy = base_style.dup
      if is_handwritten && !is_latin_or_common.call(content_str)
        style_copy[:modifiers] = Array(style_copy[:modifiers]) | [:italic]
      end
      style_copy
    end

    spans = []
    segment = +''

    text.chars.each do |char|
      if segment.empty?
        segment << char
      elsif is_latin_or_common.call(segment[-1]) == is_latin_or_common.call(char)
        segment << char
      else
        spans << RatatuiRuby::Text::Span.new(content: segment, style: build_span_style.call(segment))
        segment = +'' << char
      end
    end
    unless segment.empty?
      spans << RatatuiRuby::Text::Span.new(content: segment,
                                           style: build_span_style.call(segment))
    end

    RatatuiRuby::Text::Line.new(spans: spans)
  end
end
