# =========================================================================
# 🎯 INTERACTIVE SUFFIX-AWARE STATUSBAR TRUNCATOR
# 👉 RESOLVED: Automatically crops overflowing strings with '...'
# but intelligently preserves '(y/n)' suffixes to keep prompts functional!
# =========================================================================
def truncate_statusbar_text(text, available_width)
  text = text.to_s
  available_width = [available_width.to_i, 1].max

  # 1. If it fits perfectly, leave it completely unchanged
  return text if text.length <= available_width

  # Check if the message demands user confirmation at its absolute tail
  prompt_suffix = '? (y/n)'
  is_interactive_prompt = text.end_with?(prompt_suffix)

  if is_interactive_prompt
    # 🎯 OPTION B: INTERACTIVE PROMPT OVERRIDE […? (y/n)]
    suffix = '…? (y/n)'

    # Defensive check: if the terminal is too micro even for the suffix,
    # fall back to a hard slice to prevent a layout explosion
    return suffix[0...available_width] if available_width <= suffix.length

    allowed_text_len = available_width - suffix.length
    core_message = text[0...allowed_text_len]

    "#{core_message}#{suffix}"
  else
    # 🎯 OPTION A: STANDARD TEXT TRUNCATION [...]
    suffix = '…'
    return suffix[0...available_width] if available_width <= suffix.length

    allowed_text_len = available_width - suffix.length
    "#{text[0...allowed_text_len]}#{suffix}"
  end
end

def mark_popup_for_input_indicators
  popup = @popup&.active_popup
  popup[:show_input_indicators] = true if popup.is_a?(Hash)
end

# =========================================================================
# 🎯 GEOMETRISCHE STATUSBAR ENGINE (THE RESTORED DATA PARITY FINALE)
# Volledig hersteld: De normale statusbalk-data is 100% in zijn originele,
# Restore the original behavior. Only Quiz receives the visual spacing fix.
# =========================================================================
def draw_bottom_region(tui, frame, region)
  expire_status_message if respond_to?(:expire_status_message, true)
  bottom_block = build_bottom_block(tui, frame, region)
  frame.render_widget(bottom_block, region)

  settings = AppConfig.settings

  is_command_visible = defined?(@command_mode_visible) && @command_mode_visible
  popup_is_displayed = (defined?(@active_focus) && @active_focus.to_s == 'popup') ||
                       (defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?)

  title_area = RatatuiRuby::Layout::Rect.new(region.x + 2, region.y, [region.width - 4, 1].max, 1)

  accent_style = tui.style(fg: settings.theme_item(:window_shortcut_section),
                           bg: settings.theme_item(:background), modifiers: [:bold])
  text_style   = tui.style(fg: settings.theme_item(:window_title), bg: settings.theme_item(:background))

  label, key = settings
               .language_string(:statusbar_title)
               .split(/\s+/, 2)

  title_spans = [
    # Deze syntax werkt aantoonbaar in middle_left.rb
    tui.span(" #{label} ", text_style)
  ]

  title_spans << tui.span("#{key} ", accent_style) if key

  formatted_title =
    RatatuiRuby::Text::Line.new(spans: title_spans)

  frame.render_widget(
    RatatuiRuby::Widgets::Paragraph.new(
      text: formatted_title,
      alignment: :left
    ),
    title_area
  )

  inner_region = bottom_block.inner(region)

  # =========================================================================
  # ⌨️ INTERACTIEVE RATINFIELD COMMANDO INVOER MATRIX
  # =========================================================================
  if is_command_visible && !active_statusbar_message
    active_text = settings.theme_item(:foreground) # prompt & text
    bg_color    = settings.theme_item(:background) # prompt

    field_obj = @statusbar_field

    if field_obj
      field_obj.is_focused = true

      # Retrieve the complete raw line spans from RatinField.
      raw_line = field_obj.display_value(active_text, settings.theme_item(:window_shortcut_section))

      # 🎯 BEREKEN HIER DE DIRECTE HORIZONTALE VIEWPORT VAN JOUW STATUSBALK:
      available_input_width = [inner_region.width - 3, 1].max
      cursor_column = field_obj.visual_cursor_column.to_i

      start_column = [cursor_column - available_input_width + 5, 0].max
      start_column = [start_column, [raw_line.spans.length - available_input_width, 0].max].min

      # Snijd de spans exact op maat van de statusbalk-breedte
      visible_spans = raw_line.spans[start_column, available_input_width] || []

      # =========================================================================
      # 🎯 UNIVERSELE INLINE STATUSBALK BRANDMUUR (NIEUW)
      # 👉 We her-evalueren de spans van de viewport live op character-niveau!
      # =========================================================================
      active_lang = settings.language
      is_handwritten = settings.handwritten?(active_lang)

      is_latin_or_common = lambda do |char|
        char =~ /\A[\p{Latin}0-9\s[:punct:]]\z/
      end

      if is_handwritten
        visible_spans = visible_spans.map do |old_span|
          char_content = old_span.content.to_s

          # Bouw een veilige kopie van de karakterstijl
          final_style = old_span.style ? old_span.style.dup : {}

          # Add :italic only when the i key is enabled and the character is non-Latin.
          unless is_latin_or_common.call(char_content)
            final_style[:modifiers] = Array(final_style[:modifiers]) | [:italic]
          end

          RatatuiRuby::Text::Span.new(content: char_content, style: final_style)
        end
      end
      # =========================================================================

      # Smeed de boel samen met het Vim-style " :" voorvoegsel
      spans = [
        RatatuiRuby::Text::Span.new(content: ' :', style: { fg: active_text, bg: bg_color })
      ]
      spans.concat(visible_spans)

      line = RatatuiRuby::Text::Line.new(spans: spans)

      frame.render_widget(
        tui.paragraph(text: line, alignment: :left),
        inner_region
      )

      return unless respond_to?(:active_statusbar_message, true) && active_statusbar_message
    end
  end

  if active_statusbar_message
    render_status_message(tui, frame, inner_region)

    # Dim statusmeldingen tijdens de bedoelde tree-popups.
    popup_data = @popup&.active_popup

    if popup_data.is_a?(Hash) &&
       popup_data[:show_input_indicators] == true &&
       defined?(@active_focus) &&
       @active_focus.to_s == 'popup'

      # The popup indicator is shown in the same render cycle.
      # render_status_message applies the actual dim style.
    end

    return
  end

  context = bottom_status_context
  total_width = inner_region.width
  is_test_active =
    defined?(@current_study_mode) &&
    %i[drill quiz multiple_choice memory two_of_a_kind].include?(@current_study_mode)
  is_test_starting =
    defined?(@test_starting) && @test_starting == true

  is_two_of_a_kind_start_message =
    @current_study_mode == :two_of_a_kind &&
    @two_of_a_kind_show_start_message == true

  # 🔒 DE ROTSVASTE COCKPIT BREEDTE-ANKERS
  target_left_width = 26
  target_mid_width  = 25

  # =========================================================================
  # 🎯 1. DIRECT CALL TO THE SEGMENTED LINE HELPERS
  # =========================================================================

  raw_left_spans, raw_middle_spans = if is_two_of_a_kind_start_message
                                       shortcut_message =
                                         settings.language_string(
                                           :study_status_screen_play_two_of_a_kind_shortcuts
                                         )

                                       [
                                         [span(shortcut_message, context[:default_style])],
                                         []
                                       ]

                                     elsif is_test_starting
                                       # Keep the status bar empty during the interstitial screen.
                                       [[], []]

                                     elsif is_test_active
                                       # --- VOORTGANGSBEREKENING ---
                                       total_start = (@test_progressbar_total || 1).to_f

                                       if @current_study_mode == :memory
                                         memory_cards = Array(@memory_cards)

                                         # Eén uniek ID vertegenwoordigt één paar.
                                         total_pairs = memory_cards.map { |card| card[:id] }.uniq.length

                                         # Reeds gevonden paren.
                                         matched_ids = memory_cards
                                                       .select { |card| card[:matched] }
                                                       .map { |card| card[:id] }
                                                       .uniq

                                         # Een correct paar telt direct mee, ook voordat de speler
                                         # de volgende toets indrukt.
                                         if @memory_first_flipped_idx && @memory_second_flipped_idx
                                           first_card  = memory_cards[@memory_first_flipped_idx]
                                           second_card = memory_cards[@memory_second_flipped_idx]

                                           if first_card && second_card && first_card[:id] == second_card[:id]
                                             matched_ids << first_card[:id]
                                           end
                                         end

                                         completed_pairs = matched_ids.uniq.length
                                         remaining_cards = [total_pairs - completed_pairs, 0].max

                                         progress_ratio = if total_pairs.positive?
                                                            completed_pairs.to_f / total_pairs
                                                          else
                                                            0.0
                                                          end

                                         # Voorkom dat een verouderde initialisatiewaarde de balk beïnvloedt.
                                         total_start = total_pairs.to_f
                                       else
                                         # Reguliere berekening voor Drill, Quiz en Multiple Choice.
                                         remaining_cards = @cards_to_test ? @cards_to_test.length : 0
                                         done_count = [total_start.to_i - remaining_cards, 0].max
                                         progress_ratio = if total_start > 0
                                                            (done_count.to_f / total_start)
                                                          else
                                                            0.0
                                                          end
                                       end

                                       # --- VISUELE PROGRESSBAR ---
                                       progress_ratio = [[progress_ratio, 0.0].max, 1.0].min
                                       filled_blocks = (progress_ratio * 12).round

                                       visual_bar = '█' * filled_blocks + '░' * (12 - filled_blocks)
                                       left_res = [span(visual_bar, context[:default_style])]

                                       is_paused = defined?(@test_timer_paused) && @test_timer_paused == true
                                       pause_indicator = is_paused ? '⏸' : '▶'

                                       if @current_study_mode == :memory
                                         buffer_str = if defined?(@memory_input_buffer)
                                                        @memory_input_buffer.to_s.upcase
                                                      else
                                                        ''
                                                      end

                                         display_buffer = buffer_str.dup
                                         display_buffer << '_' while display_buffer.length < 2

                                         # --- PAGINA-INDICATOR MEMORY ---
                                         memory_visible_rows = [@memory_visible_rows.to_i, 1].max
                                         memory_total_rows = [@memory_total_rows.to_i, 1].max

                                         memory_max_scroll = [memory_total_rows - memory_visible_rows, 0].max

                                         memory_total_pages = [
                                           (memory_total_rows.to_f / memory_visible_rows).ceil,
                                           1
                                         ].max

                                         memory_scroll = [
                                           [@memory_scroll_offset.to_i, 0].max,
                                           memory_max_scroll
                                         ].min

                                         memory_current_page = if memory_scroll == memory_max_scroll
                                                                 memory_total_pages
                                                               else
                                                                 (memory_scroll / memory_visible_rows) + 1
                                                               end

                                         memory_page_indicator = format(
                                           '‹%d/%d›',
                                           memory_current_page,
                                           memory_total_pages
                                         )

                                         progress_percentage = (progress_ratio * 100).to_i

                                         raw_middle_study = [
                                           pause_indicator,
                                           memory_page_indicator,
                                           "%:#{progress_percentage}",
                                           "⧉:#{remaining_cards}",
                                           "⌨:#{display_buffer}"
                                         ].join('   ')

                                         middle_res = [
                                           span(raw_middle_study, context[:default_style])
                                         ]

                                       elsif @current_study_mode == :two_of_a_kind

                                         # Totaal aantal paren (twee kaarten per paar)
                                         total_pairs = (@test_progressbar_total || 0).to_i / 2
                                         total_pairs = 1 if total_pairs <= 0

                                         completed_pairs = (@user_score || 0).to_i +
                                                           (@computer_score || 0).to_i

                                         progress_ratio = if total_pairs.positive?
                                                            completed_pairs.to_f / total_pairs
                                                          else
                                                            0.0
                                                          end

                                         progress_ratio = [[progress_ratio, 0.0].max, 1.0].min
                                         # Pagina-indicator: gebruik exact dezelfde viewport als de kaartweergave.
                                         total_cards = Array(@user_hand).length

                                         visible_rows = [
                                           (@two_of_a_kind_visible_rows || 1).to_i,
                                           1
                                         ].max

                                         visible_rows = [visible_rows, [total_cards, 1].max].min

                                         total_pages = [
                                           (total_cards.to_f / visible_rows).ceil,
                                           1
                                         ].max

                                         max_offset = [total_cards - visible_rows, 0].max

                                         current_offset = [
                                           [(@two_of_a_kind_scroll_y || 0).to_i, 0].max,
                                           max_offset
                                         ].min

                                         current_page = if total_cards <= visible_rows
                                                          1
                                                        else
                                                          [(current_offset.to_f / visible_rows).ceil + 1,
                                                           total_pages].min
                                                        end

                                         page_indicator = format('‹%d/%d›', current_page, total_pages)

                                         # Resterende kaarten in de trekstapel
                                         deck_count = @two_of_a_kind_deck&.length || 0

                                         progress_percentage = (progress_ratio * 100).to_i

                                         raw_middle_study = [
                                           pause_indicator,
                                           page_indicator,
                                           "%:#{progress_percentage}",
                                           "#:#{deck_count}"
                                         ].join('   ')

                                         middle_res = [
                                           span(raw_middle_study, context[:default_style])
                                         ]

                                       else
                                         # --- REGULIERE WEERGAVE VOOR DRILL, QUIZ EN MULTIPLE CHOICE ---
                                         progress_percentage = (progress_ratio * 100).to_i
                                         fixed_percentage = "%:#{progress_percentage}"
                                         fixed_remaining = "◪:#{remaining_cards}"

                                         countdown_string = if @current_study_mode == :drill
                                                              if defined?(@test_drill_timed) && @test_drill_timed == true
                                                                display_secs = [
                                                                  ((@test_time_left || 0) + 0.99).to_i, 0
                                                                ].max

                                                                format(
                                                                  '⏱︎:%01d/%d″',
                                                                  display_secs,
                                                                  @test_drill_timer_max || 3
                                                                )
                                                              else
                                                                format('⏱︎:-/%d″', @test_drill_timer_max || 3)
                                                              end
                                                            else
                                                              ''
                                                            end

                                         indicator_str = ''

                                         if @current_study_mode == :drill &&
                                            @cards_to_test &&
                                            !@cards_to_test.empty?

                                           terminal_height = RatatuiRuby.terminal_size&.height || 24
                                           drill_region_height = terminal_height - 3

                                           visible_rows = if @test_show_context
                                                            (drill_region_height - 4)
                                                          else
                                                            (drill_region_height - 2)
                                                          end

                                           page_size = [visible_rows - 1, 1].max

                                           total_pages = (
                                             (@cards_to_test.length - 1).to_f / page_size
                                           ).floor + 1

                                           current_page = [
                                             [((@test_current_idx || 0) / page_size) + 1, 1].max,
                                             total_pages
                                           ].min

                                           indicator_str = format('‹%d/%d›', current_page, total_pages)
                                         end

                                         raw_middle_study = [
                                           pause_indicator,
                                           indicator_str,
                                           fixed_percentage,
                                           fixed_remaining,
                                           countdown_string
                                         ].reject { |s| s.to_s.empty? }.join('   ')

                                         middle_res = [
                                           span(raw_middle_study, context[:default_style])
                                         ]
                                       end

                                       [left_res, middle_res]

                                     elsif replacing_status?(context)
                                       replacement_segmented_line(context)
                                     elsif context[:has_active_search]
                                       search_segmented_line(context)
                                     else
                                       normal_segmented_line(context)
                                     end

  # Toon toetsenbordindeling en tekstrichting uitsluitend bij
  # Search, Replace, Rename, Add en Edit.
  popup_data = @popup&.active_popup

  if popup_data.is_a?(Hash) &&
     popup_data[:show_input_indicators] == true

    kb_label = "⌨:#{os_keyboard_layout}"
    direction_label = active_popup_input_direction_label || '-'

    raw_middle_spans = [
      span("#{kb_label}   ⇄:#{direction_label}", context[:default_style])
    ]
  end

  text_width = lambda do |spans|
    Unicode::DisplayWidth.of(
      spans.map { |s| s.content.to_s }.join
    )
  end

  # =========================================================================
  # 📐 2. BINDENDE OPVUL-MATRIX (NET ALS VROEGER)
  # We vullen zowel LINKS als MIDDEN aan tot exact hun vaste cel-breedtes.
  # This keeps all columns fixed in place.
  # =========================================================================

  if context[:has_active_search] || replacing_status?(context) || is_test_active
    # JOUW BREEDTE-ANKER VOOR GEBALANSEERDE MODI:
    # Preserve the natural spans without adding trailing padding spaces,
    # waardoor de spacers het middenstuk exact naar het visuele centrum trekken!
    left_spans = raw_left_spans.dup
    middle_spans = raw_middle_spans.dup
  else
    # Alleen de normale ruststand (hoofdmenu/cockpit navigatie) behoudt zijn rotsvaste kolom-grendels
    left_text_len = text_width.call(raw_left_spans)
    needed_left_spaces = [target_left_width - left_text_len, 0].max
    left_spans = raw_left_spans.dup
    left_spans << span(' ' * needed_left_spaces, context[:default_style]) if needed_left_spaces > 0

    middle_text_len = text_width.call(raw_middle_spans)
    needed_mid_spaces = [target_mid_width - middle_text_len, 0].max
    middle_spans = raw_middle_spans.dup
    middle_spans << span(' ' * needed_mid_spaces, context[:default_style]) if needed_mid_spaces > 0
  end

  # =========================================================================
  # ⏱️ 3. KLOK / STOPWATCH SECTOR (RECHTS)
  # We bakken de 1-spatie marge direct aan het einde van de string in,
  # maar we tellen hem hieronder wiskundig mee in de totale breedte!
  # =========================================================================
  right_spans = if is_test_starting
                  []
                elsif is_test_active && defined?(@test_time_left)
                  popup_is_open = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?
                  @test_last_tick_time ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)

                  if !popup_is_open && !(defined?(@test_timer_paused) && @test_timer_paused == true) && !(defined?(@test_finished_waiting) && @test_finished_waiting == true)
                    current_monotonic_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
                    elapsed_delta = current_monotonic_time - @test_last_tick_time

                    if %i[memory drill two_of_a_kind].include?(@current_study_mode)
                      # MEMORY, DRILL EN TWO OF A KIND:
                      # Oplopende sessietijd
                      @test_drill_elapsed ||= 0.0
                      @test_drill_elapsed += elapsed_delta

                      # Optionele countdown uitsluitend voor Drill
                      if @current_study_mode == :drill && @test_drill_timed == true
                        @test_time_left -= elapsed_delta

                        if @test_time_left <= 0
                          @test_time_left = 0
                          handle_drill_input(' ', []) if respond_to?(:handle_drill_input)
                        end
                      end
                    else
                      # Quiz en Multiple Choice tellen regulier af van de totale tijd
                      # (Two of a Kind en Drill zijn hier nu volledig van uitgesloten)
                      if %i[quiz multiple_choice].include?(@current_study_mode)
                        @test_time_left -= elapsed_delta

                        if (@test_time_left <= 0) && respond_to?(:trigger_statusbar_message)
                          trigger_statusbar_message(
                            "#{AppConfig.settings.language_string(:study_test_failed)}: #{AppConfig.settings.language_string(:study_test_time_up)}!",
                            type: :error,
                            beep: false,
                            expires: false
                          )
                          @test_time_left = 0
                          SoundManager.play(:failed)
                          @test_time_was_up_notified = true
                          @test_finished_waiting = true
                        end
                      end
                    end
                  end

                  @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

                  # In drill/memory mode, the stopwatch on the right always shows elapsed session time.
                  active_seconds_value = if %i[drill
                                               memory two_of_a_kind].include?(@current_study_mode)
                                           @test_drill_elapsed || 0
                                         else
                                           @test_time_left
                                         end

                  mins_num = [active_seconds_value.to_i / 60, 0].max
                  secs_num = [active_seconds_value.to_i % 60, 0].max

                  time_string = format('%02d:%02d', mins_num, secs_num)
                  [span(time_string, context[:default_style])]
                else
                  [span('00:00', context[:default_style])]
                end

  # =========================================================================
  # 📐 4. STATUSBALKUITLIJNING
  # =========================================================================

  # Bepaal de standaardstijl voordat we de spans opbouwen.
  current_default_style = if popup_is_displayed
                            {
                              fg: settings.theme_item(:foreground),
                              modifiers: [:dim]
                            }
                          else
                            context[:default_style]
                          end

  # Remove trailing padding from the left segment.
  # Recalculate the gap afterward.
  left_spans = left_spans.dup

  loop do
    last = left_spans.last
    break unless last

    content = last.content.to_s
    trimmed = content.sub(/ +\z/, '')
    break if trimmed == content

    left_spans.pop
    unless trimmed.empty?
      left_spans << span(trimmed, last.style)
      break
    end
  end

  # Meet de breedtes van de drie tekstsegmenten.
  left_text_len   = text_width.call(left_spans)
  middle_text_len = text_width.call(middle_spans)
  right_text_len  = text_width.call(right_spans)

  # Bepaal de beschikbare breedte van de statusbalk.
  available_width = [inner_region.width, 0].max

  # Reserveer één cel marge aan beide uiteinden.
  side_margin = 1
  usable_width = [available_width - (side_margin * 2), 0].max

  # =========================================================================
  # 📐 BEREKEN DE TUSSENRUIMTES VOOR EEN GECENTREERD MIDDENSEGMENT
  # =========================================================================

  # Determine the gap between the left and right text.
  space_between = (usable_width || 0).to_i - (left_text_len || 0).to_i - (right_text_len || 0).to_i

  # Bereken de resterende ruimte na plaatsing van het middensegment.
  free_space = space_between - (middle_text_len || 0).to_i

  # Verdeel de vrije ruimte gelijkmatig over beide kanten van het midden.
  left_gap = [free_space / 2, 0].max
  right_gap = [free_space - left_gap, 0].max

  # Bouw de volledige statusbalkregel op.
  all_spans = [
    span(' ' * side_margin, current_default_style),
    *left_spans,
    span(' ' * left_gap, current_default_style),
    *middle_spans,
    span(' ' * right_gap, current_default_style),
    *right_spans,
    span(' ' * side_margin, current_default_style)
  ]

  #   File.open('test.log', 'a') do |file|
  #     left_text   = left_spans.map { |item| item.content.to_s }.join
  #     middle_text = middle_spans.map { |item| item.content.to_s }.join
  #     right_text  = right_spans.map { |item| item.content.to_s }.join
  #     rendered_text = all_spans.map { |item| item.content.to_s }.join
  #
  #     # Create a visual copy that shows each space as a dot.
  #     debug_line =
  #       ('·' * side_margin) +
  #       left_text.tr(' ', '·') +
  #       ('·' * left_gap) +
  #       middle_text.tr(' ', '·') +
  #       ('·' * right_gap) +
  #       right_text.tr(' ', '·') +
  #       ('·' * side_margin)
  #
  #     # Toon de kolomposities met een liniaal van terminalcellen.
  #     ruler = (0...available_width).map { |i| (i % 10).to_s }.join
  #
  #     file.puts
  #     file.puts('========== STATUSBAR DEBUG ==========')
  #     file.puts("ruler:        #{ruler}")
  #     file.puts("visible:      #{debug_line}")
  #     file.puts("left:         #{left_text.inspect}")
  #     file.puts("middle:       #{middle_text.inspect}")
  #     file.puts("right:        #{right_text.inspect}")
  #     file.puts(
  #       "widths: left=#{Unicode::DisplayWidth.of(left_text)} " \
  #       "middle=#{Unicode::DisplayWidth.of(middle_text)} " \
  #       "right=#{Unicode::DisplayWidth.of(right_text)}"
  #     )
  #     file.puts(
  #       "gaps: left=#{left_gap} right=#{right_gap} " \
  #       "total=#{Unicode::DisplayWidth.of(debug_line)} " \
  #       "available=#{available_width}"
  #     )
  #     file.puts("actual:       #{rendered_text.inspect}")
  #     file.puts('=====================================')
  #   end

  # Preserve the dimmed style while a popup is open.
  if popup_is_displayed
    all_spans.each do |item|
      item.style ||= {}
      item.style[:modifiers] ||= []
      item.style[:modifiers] << :dim unless item.style[:modifiers].include?(:dim)
    end
  end

  # Maak de uiteindelijke statusbalkregel.
  line_widget = RatatuiRuby::Text::Line.new(spans: all_spans)

  # Render de statusbalk.
  frame.render_widget(
    tui.paragraph(text: line_widget, alignment: :left),
    inner_region
  )
end

def tree_pagination_context
  return nil unless @tree

  tree_nodes =
    if @tree.respond_to?(:navigation_nodes)
      @tree.navigation_nodes
    elsif @tree.respond_to?(:all_visible_nodes)
      @tree.all_visible_nodes
    elsif @tree.respond_to?(:visible_nodes)
      @tree.visible_nodes
    else
      []
    end

  tree_nodes = tree_nodes.to_a
  total_nodes = tree_nodes.length
  return nil if total_nodes <= 0

  window_height = [(@tree_visible_height || 1).to_i, 1].max
  visible_rows = [window_height, total_nodes].min
  max_offset = [total_nodes - visible_rows, 0].max

  selected_row =
    if @tree_state&.respond_to?(:selected)
      (@tree_state.selected || 0).to_i
    else
      0
    end

  selected_row = [[selected_row, 0].max, total_nodes - 1].min

  # Gebruik de viewportpositie die bij de rendering hoort.
  state_offset =
    if @tree_state&.respond_to?(:offset)
      (@tree_state.offset || 0).to_i
    else
      0
    end

  viewport_offset =
    if !@search_page_viewport_start.nil?
      @search_page_viewport_start.to_i
    elsif @tree_page_navigation_active &&
          !@tree_page_viewport_start.nil?
      @tree_page_viewport_start.to_i
    else
      state_offset
    end

  viewport_offset = [[viewport_offset, 0].max, max_offset].min

  total_pages = [(total_nodes.to_f / window_height).ceil, 1].max

  current_page =
    if total_nodes <= window_height
      1
    else
      [(viewport_offset.to_f / window_height).ceil + 1, total_pages].min
    end

  {
    total_nodes: total_nodes,
    visible_rows: visible_rows,
    page_size: window_height,
    selected_row: selected_row,
    current_offset: viewport_offset,
    total_pages: total_pages,
    current_page: current_page
  }
end

def table_pagination_context(context = bottom_status_context)
  return nil unless context[:deck_selected]

  total_nodes = context[:selected_deck_cards].to_i
  return nil if total_nodes <= 0

  window_height = [(@table_visible_height || 1).to_i, 1].max
  visible_rows = [window_height, total_nodes].min
  max_offset = [total_nodes - visible_rows, 0].max

  selected_row =
    if @table_state&.respond_to?(:selected)
      (@table_state.selected || 0).to_i
    else
      0
    end

  selected_row = [[selected_row, 0].max, total_nodes - 1].min

  # De renderer houdt de werkelijke viewportpositie bij.
  # Gebruik de state-offset alleen als fallback.
  state_offset =
    if @table_state&.respond_to?(:offset)
      (@table_state.offset || 0).to_i
    else
      0
    end

  current_offset =
    if @table_viewport_offset.nil?
      state_offset
    else
      @table_viewport_offset.to_i
    end

  current_offset = [[current_offset, 0].max, max_offset].min

  total_pages = [(total_nodes.to_f / window_height).ceil, 1].max

  current_page =
    if total_nodes <= window_height
      1
    else
      [((current_offset.to_f / window_height).ceil + 1), total_pages].min
    end

  current_page = [[current_page, 1].max, total_pages].min

  {
    total_nodes: total_nodes,
    visible_rows: visible_rows,
    page_size: window_height,
    selected_row: selected_row,
    current_offset: current_offset,
    total_pages: total_pages,
    current_page: current_page
  }
end

def expire_status_message
  return unless @status_message_expires_at
  return unless Process.clock_gettime(Process::CLOCK_MONOTONIC) > @status_message_expires_at

  @status_message = nil
  @status_message_expires_at = nil
end

def build_bottom_block(tui, frame, region)
  settings = AppConfig.settings

  is_statusbar_searching = defined?(@search_replace_origin_mode) && @search_replace_origin_mode == :command_mode
  is_command_active = (defined?(@active_focus) && @active_focus == :command_mode) || is_statusbar_searching

  border_color = is_command_active ? settings.theme_item(:window_border) : settings.theme_item(:foreground)
  border_modifiers = is_command_active ? [] : [:dim]

  border_style = {
    fg: border_color,
    bg: settings.theme_item(:background),
    modifiers: border_modifiers
  }

  tui.block(
    title: nil,
    border_style: border_style,
    style: { bg: settings.theme_item(:background) },
    borders: [:all],
    border_type: settings.corner
  )
end

def render_status_message(tui, frame, region)
  raw_message = @status_message.to_s
  available_text_width = [region.width - 2, 10].max
  clean_display_text = truncate_statusbar_text(raw_message, available_text_width)

  popup_data = @popup&.active_popup

  dim_status_message =
    ((defined?(@active_focus) && @active_focus.to_s == 'popup') ||
      (defined?(@popup) && @popup &&
       @popup.respond_to?(:active?) && @popup.active?)) &&
    popup_data.is_a?(Hash) &&
    popup_data[:show_input_indicators] == true

  style = {
    fg: AppConfig.settings.theme_item(:foreground),
    bg: AppConfig.settings.theme_item(:background),
    modifiers: dim_status_message ? [:dim] : []
  }

  line = RatatuiRuby::Text::Line.new(
    spans: [
      RatatuiRuby::Text::Span.new(
        content: " #{clean_display_text}",
        style: style
      )
    ]
  )

  frame.render_widget(tui.paragraph(text: line), region)
end

def bottom_status_context
  settings = AppConfig.settings
  is_global_active = defined?(@global_search_active) && @global_search_active

  # 🎯 REPARATIE: Als de global array gevuld is, is er ALTIJD een actieve zoektoestand!
  has_table_search = (@search_matches && @search_matches.any?) || is_global_active
  has_tree_search = @tree_search_matches && @tree_search_matches.any?

  selected_deck_cards, deck_selected = selected_deck_card_count
  total_counts = database_counts
  default_style = { fg: settings.theme_item(:foreground) }
  search_style = { fg: settings.theme_item(:background), bg: settings.theme_item(:search_results_background) }

  {
    settings: settings,
    has_table_search: has_table_search,
    has_tree_search: has_tree_search,
    has_active_search: has_table_search || has_tree_search || is_global_active,
    global_active: is_global_active,
    selected_deck_cards: selected_deck_cards,
    deck_selected: deck_selected,
    total_subjects: total_counts[0],
    total_sources: total_counts[1],
    total_decks: total_counts[2],
    global_total_cards: total_counts[3],
    default_style: default_style,
    search_style: search_style
  }
end

def database_counts
  subjects = @library.subjects
  total_subjects = subjects.length
  total_sources = subjects.sum { |sub| sub.sources.length }
  total_decks = subjects.sum { |sub| sub.sources.sum { |src| src.decks.length } }
  total_cards = subjects.sum { |sub| sub.sources.sum { |src| src.decks.sum { |deck| deck.cards.length } } }
  [total_subjects, total_sources, total_decks, total_cards]
end

def selected_deck_card_count
  path = @tree&.selected_path
  return [0, false] unless path && path.length == 3

  subject = @library.subjects.find { |s| s.id.to_s == path[0].to_s }
  source = subject&.sources&.find { |src| src.id.to_s == path[1].to_s }
  deck = source&.decks&.find { |item| item.id.to_s == path[2].to_s }
  [deck ? Array(deck.cards).length : 0, true]
end

def build_bottom_status_line(context)
  left_spans, middle_spans = if replacing_status?(context)
                               replacement_segmented_line(context)
                             elsif context[:has_active_search]
                               search_segmented_line(context)
                             else
                               normal_segmented_line(context)
                             end

  # Return two clean Lines without adding spaces.
  [
    RatatuiRuby::Text::Line.new(spans: left_spans),
    RatatuiRuby::Text::Line.new(spans: middle_spans)
  ]
end

def replacement_segmented_line(context)
  current_match, total_matches = current_match_info(context)
  replacement = @last_replace_text.to_s.strip.empty? ? '-' : @last_replace_text.to_s

  # LEFT: The statistics section has been fully replaced by the clear string.
  left = [
    span("#{AppConfig.settings.language_string(:statusbar_replace_with)} ", context[:default_style]),
    span(replacement, context[:search_style]),
    span('? (y/n/a)', context[:default_style])
  ]

  # MIDDEN: Toont de actuele match-indicators tijdens het vervangen
  middle = if context[:global_active] && defined?(@global_search_matches) && @global_search_matches
             current_pos = (@global_search_current_idx || 0) + 1
             [span(" * ➔:#{current_pos}/#{@global_search_matches.length}", context[:default_style])]
           else
             current_match, total_matches = current_match_info(context)
             [span("➔:#{current_match}/#{total_matches}", context[:default_style])]
           end

  [left, middle]
end

def search_segmented_line(context)
  left = [
    span(
      "▲:#{context[:total_subjects]} △:#{context[:total_sources]} ■:#{context[:total_decks]} ◪:#{context[:deck_selected] ? context[:selected_deck_cards].to_s : '-'}/#{context[:global_total_cards]}", context[:default_style]
    )
  ]

  # 🎯 FIX C: Als de global search aanstaat, tonen we de voortgang over de hele library!
  middle = if context[:global_active] && defined?(@global_search_matches) && @global_search_matches
             current_pos = (@global_search_current_idx || 0) + 1
             [span("* ➔:#{current_pos}/#{@global_search_matches.length}", context[:default_style])]
           else
             current_match, total_matches = current_match_info(context)
             [span("➔:#{current_match}/#{total_matches}", context[:default_style])]
           end

  [left, middle]
end

def active_popup_input_direction_label
  return nil unless defined?(@popup) && @popup&.active?

  popup_data = @popup.active_popup
  return nil unless popup_data.is_a?(Hash)
  return nil unless popup_data[:type] == :form

  fields = popup_data[:fields]
  return nil unless fields.is_a?(Hash) && !fields.empty?

  focus = popup_data[:form_focus] || fields.keys.first
  field = begin
    fields[focus] || fields[focus.to_s] ||
      fields[focus.to_sym]
  rescue StandardError
    nil
  end

  return nil unless field && field.respond_to?(:text)

  text = field.text.to_s
  cursor = if field.respond_to?(:cursor_index)
             field.cursor_index.to_i
           else
             0
           end

  chars = text.each_char.to_a
  cursor = [[cursor, 0].max, chars.length].min

  # Bepaal de richting van het dichtstbijzijnde sterke teken.
  # When distances are equal, prefer the character before the cursor.
  before = chars[0...cursor].reverse
  after  = chars[cursor..] || []

  [before, after].each do |side|
    side.each do |char|
      next unless char.match?(/\p{L}/)

      return 'RTL' if char.match?(
        /[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF\u{10800}-\u{10FFF}\u{1E800}-\u{1EEFF}]/
      )

      return 'LTR'
    end
  end

  nil
end

def normal_segmented_line(context)
  visible_rows = [(@table_visible_height || 1).to_i, 1].max
  page_size = [visible_rows - 1, 1].max

  left = [
    span(
      "▲:#{context[:total_subjects]} △:#{context[:total_sources]} ■:#{context[:total_decks]} ◪:#{context[:deck_selected] ? context[:selected_deck_cards].to_s : '-'}/#{context[:global_total_cards]}", context[:default_style]
    )
  ]

  # =========================================================================
  # DYNAMISCHE INTERCEPTIE VAN DE PAGINERINGSLABEL
  # 👉 We controleren als ALLEREERSTE of er een help-popup geopend is.
  # Zo ja, dan schakelt de indicator over naar de help-pagina's (@popup_current_page).
  # Zo nee, dan vallen de tabel- en tree-pagineringen ongestoord terug op hun eigen plek!
  # =========================================================================
  popup_is_help_view = defined?(@popup) && @popup && @popup.active? &&
                       @popup.active_popup && @popup.active_popup[:type] == :help

  indicator = if popup_is_help_view
                # 🟢 HELPSCHERM ACTIVE STAND:
                curr_p = defined?(@popup_current_page) && @popup_current_page ? @popup_current_page : 1
                tot_p  = defined?(@popup_total_pages) && @popup_total_pages ? @popup_total_pages : 1
                "‹#{curr_p}/#{tot_p}›"
              elsif @active_focus == :table && context[:deck_selected] && context[:selected_deck_cards] > 0
                table_ctx = table_pagination_context(context)

                if table_ctx
                  "‹#{table_ctx[:current_page]}/#{table_ctx[:total_pages]}›"
                else
                  '‹1/1›'
                end
              elsif @active_focus == :tree && respond_to?(:tree_pagination_context, true)
                # 🌲 TREE PAGINERING POORT: Haal de actuele data live op uit jouw methode!
                tree_ctx = tree_pagination_context
                if tree_ctx && tree_ctx[:total_pages] > 0
                  "‹#{tree_ctx[:current_page]}/#{tree_ctx[:total_pages]}›"
                else
                  '‹1/1›'
                end
              else
                '‹-/-›'
              end

  strategy_labels = {
    fronts_random: AppConfig.settings.language_string(:study_modus_front),
    backs_random: AppConfig.settings.language_string(:study_modus_back),
    alternately_fronts_and_backs_random: AppConfig.settings.language_string(:study_modus_alternate),
    everything_random: AppConfig.settings.language_string(:study_modus_mixed)
  }
  active_strat = AppConfig.settings.study_strategy || :fronts_random
  strat_code = strategy_labels[active_strat] || AppConfig.settings.language_string(:study_modus_front)

  middle = [
    span("⌨:#{os_keyboard_layout}   #{indicator}   #{marked_text(context)}   M:#{strat_code}",
         context[:default_style])
  ]

  [left, middle]
end

def replacing_status?(context)
  (@active_focus == :replace_mode) ||
    ((@interactively_replacing == true) && %i[table tree].include?(@active_focus))
end

def replacement_status_line(context)
  current_match, total_matches = current_match_info(context)
  replacement = @last_replace_text.to_s.strip.empty? ? '-' : @last_replace_text.to_s
  spans = [
    span(context[:settings].language_string(:status_replace_with), context[:default_style]),
    span(replacement, context[:search_style]),
    span("? (y/n/a)   ➔:#{current_match}/#{total_matches}", context[:default_style])
  ]
  RatatuiRuby::Text::Line.new(spans: spans)
end

def search_status_line(context)
  current_match, total_matches = current_match_info(context)
  counts = " ▲:#{context[:total_subjects]} △:#{context[:total_sources]} ■:#{context[:total_decks]} ◪:#{context[:deck_selected] ? context[:selected_deck_cards].to_s : '-'}/#{context[:global_total_cards]}"
  RatatuiRuby::Text::Line.new(spans: [
                                span(counts, context[:default_style]),
                                span("   ➔:#{current_match}/#{total_matches}",
                                     context[:default_style])
                              ])
end

def normal_status_line(context)
  cards = context[:deck_selected] ? context[:selected_deck_cards].to_s : '-'

  indicator =
    if @active_focus == :table &&
       context[:deck_selected] &&
       context[:selected_deck_cards] > 0

      table_ctx = table_pagination_context(context)

      if table_ctx
        "‹#{table_ctx[:current_page]}/#{table_ctx[:total_pages]}›"
      else
        '‹1/1›'
      end
    else
      ' ‹-/-›'
    end
  text = " ▲:#{context[:total_subjects]} △:#{context[:total_sources]} ■:#{context[:total_decks]} ◪:#{cards}/#{context[:global_total_cards]}   #{indicator}   #{marked_text(context)}"
  RatatuiRuby::Text::Line.new(spans: [span(text, context[:default_style])])
end

def current_match_info(context)
  if context[:has_tree_search]
    [(@tree_search_current_idx || 0) + 1, Array(@tree_search_matches).length]
  else
    [(@search_current_match_idx || 0) + 1, Array(@search_matches).length]
  end
end

def marked_text(context)
  count = @active_focus == :tree ? (@selected_tree_paths || []).length : (@selected_table_rows || []).length
  count > 0 ? "▍:#{count}" : '▍:-'
end

def span(content, style)
  RatatuiRuby::Text::Span.new(content: content, style: style)
end

# =========================================================================
# 🎯 DYNAMISCHE OS TOETSENBORD DETECTIE MATRIX
# Vraagt live de actieve input-source op van macOS of Linux zonder hapering.
# Cache the call briefly to reduce excessive subshells (I/O overhead).
# =========================================================================
def os_keyboard_layout
  @last_kb_check ||= 0
  current_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  # Check at most every 0.4 seconds to keep the TUI render loop responsive.
  if current_time - @last_kb_check > 0.4 || @cached_kb_layout.nil?
    @last_kb_check = current_time

    raw_layout =
      case RbConfig::CONFIG['host_os']
      when /darwin/i
        # macOS FIX: We scannen de gehele HIToolbox plist op actieve invoer-ID's.
        # Dit vangt zowel traditionele keylayouts als internationale input-methods (zoals Cyrillisch).
        cmd = "defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleSelectedInputSources 2>/dev/null | egrep 'KeyboardLayout Name|InputSourceID' | sed -E 's/^.+ = \"?([^\"]+)\"?;$/\\1/' | tr '\\n' ' '"
        `#{cmd}`.strip.upcase
      when /linux/i
        # Linux: Vraagt de actieve X11/Wayland layout op
        `setxkbmap -query 2>/dev/null | grep layout | awk '{print $2}'`.strip.upcase
      else
        'US'
      end

    # If the query is empty, fall back to the default US layout.
    raw_layout = 'US' if raw_layout.empty?

    # 🎯 COCKPIT VERTAAL-MATRIX (Gegarandeerd 2 letters)
    @cached_kb_layout = case raw_layout
                        when /RUSSIAN|CYRILLIC/i  then 'RU'
                        when /DUTCH|NETHERLANDS/i then 'NL'
                        when /GERMAN|DEUTSCH/i    then 'DE'
                        when /FRENCH|FRANCAIS/i   then 'FR'
                        when /ABC/i               then 'US'
                        when /U\.S\.|UNITED-STATES/i then 'US'
                        when /INTERNATIONAL/i then 'NL'
                        else
                          # Fallback: Extraheer de pure landcode uit de Apple-string (bijv. com.apple.keylayout.Russian)
                          clean_match = raw_layout.match(/KEYLAYOUT\.([A-Z]{2})/)
                          if clean_match
                            clean_match[1]
                          else
                            # Ultieme afkap-veiligheid: pak de eerste twee letters
                            raw_layout.gsub(/[^A-Z]/, '')[0, 2] || 'US'
                          end
                        end
  end

  @cached_kb_layout
end
