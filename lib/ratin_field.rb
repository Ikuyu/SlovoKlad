# frozen_string_literal: true

require_relative 'ratin_field_history_manager'
require 'ffi' # FriBidi uses UTF-32 Unicode codepoints.
require 'time'

# Bidirectional layout and text indexing
# ---------------------------------------
# FriBidi determines the visual order of Unicode codepoints. Ruby string
# indices are used as logical codepoint offsets throughout this editor; they
# are neither byte offsets nor grapheme-cluster offsets.
#
# Rendering groups the reordered codepoints into grapheme clusters (\X), so
# combining marks such as Hebrew niqqud remain visually attached to their base
# character and terminal width is measured per visible cluster.
#
# Left/Right navigation follows visual caret stops from the FriBidi layout.
# Each stop maps back to a logical codepoint boundary, which remains the source
# of truth for text mutation. A visible grapheme cluster can span multiple
# logical codepoints, so keep visual caret stops and logical indices distinct.
#
# FriBidi remains the authority for visual ordering. This class maps its
# logical/visual results to Ruby codepoint ranges and handles editing state,
# terminal geometry, and rendering.

module FriBidiNative
  class Unavailable < StandardError; end

  extend FFI::Library

  library =
    case RbConfig::CONFIG['host_os']
    when /darwin/i
      'fribidi'
    when /linux/i
      'libfribidi.so.0'
    when /mswin|mingw|cygwin/i
      'libfribidi-0'
    else
      raise FriBidiNative::Unavailable,
            "\e[31mError:\e[0m FriBidi is not supported on this operating system."
    end

  begin
    ffi_lib library
  rescue LoadError
    raise FriBidiNative::Unavailable,
          "\e[31mError:\e[0m Could not load the FriBidi native library. Install it for your operating system and ensure it is available on the library search path."
  end

  attach_function :fribidi_log2vis,
                  %i[pointer int32 pointer pointer pointer pointer pointer],
                  :int

  attach_function :fribidi_get_bidi_type,
                  [:uint32],
                  :uint32
end

DIRECTION_MARKS = /[\u200E\u200F\u2068\u2069\u202B\u202C]/

class ClipboardManager
  def self.copy(text, direction)
    text = text.to_s

    # Add an explicit RTL mark only when the copied text is RTL.
    text = "\u200F" + text if direction == :rtl

    ::Clipboard.copy(text)
  end

  def self.paste
    ::Clipboard.paste
  end
end

class RatinField
  attr_accessor :placeholder, :max_length, :is_focused, :selection_start
  attr_reader :cursor_index, :text, :direction, :editing_direction

  def cursor_index=(value)
    clear_visual_caret_position!
    @cursor_index = value
  end

  # --- State and direction -------------------------------------------------

  def initialize(placeholder: '', max_length: nil, direction: :ltr)
    @text = ''
    @default_placeholder = placeholder
    @placeholder = placeholder
    @max_length = max_length
    @is_focused = false
    @cursor_index = 0
    @selection_start = nil
    @visual_selection_anchor_position_index = nil
    @history = RatinFieldHistoryManager.new
    @initial_direction = normalize_direction(direction)
    @alignment_override = :rtl if @initial_direction == :rtl
    @direction = @initial_direction
    # Alignment is selected once from the first strong character unless the
    # caller explicitly initialized the field as RTL or later sets direction=.
    @alignment_locked = !@alignment_override.nil?
    @editing_direction = @direction
    @editing_direction_manual = false
    @force_viewport_center = false
    @viewport_start = 0
    clear_visual_caret_position!
  end

  def normalize_direction(value)
    %i[rtl right_to_left].include?(value.to_s.downcase.to_sym) ? :rtl : :ltr
  end

  # Alignment direction is deliberately independent from the direction used
  # for the next typed fragment. Changing it explicitly locks the alignment.
  def direction=(value)
    @direction = normalize_direction(value)
    @alignment_override = @direction
    @alignment_locked = true
    @editing_direction = @direction unless @editing_direction_manual
    invalidate_bidi_cache!
    @direction
  end

  # Set the direction for subsequent text insertion. Fragment isolation is
  # handled by the insertion layer; this state must not be inferred from every
  # character typed into an already-aligned field.
  def set_editing_direction!(value)
    @editing_direction = normalize_direction(value)
    @editing_direction_manual = true
    @editing_direction
  end

  def clear
    @history.clear
    clear_visual_caret_position!
    @text = ''
    @placeholder = @default_placeholder
    @cursor_index = 0
    @direction = @alignment_override || @initial_direction
    @alignment_locked = !@alignment_override.nil?
    @editing_direction = @direction
    @editing_direction_manual = false
    clear_selection
    invalidate_bidi_cache!
  end

  # --- Text and selection --------------------------------------------------

  def get_text(visual: false)
    # If the view requests a visual layout string, we can return the bidi text,
    # otherwise we return the raw logical text string.
    visual ? bidi_visual(@text) : @text
  end

  def visual_text
    editor_visual_layout.map { |item| item[:char] }.join
  end

  def popup_visual_text
    visual_text
  end

  # A single logical range is returned only when it fully describes the selection.
  # Multiple visual spans can be non-contiguous in the source string.
  def selection_range
    ranges = selection_ranges
    ranges.length == 1 ? ranges.first : nil
  end

  def selection_ranges
    visual_ranges = visual_selection_ranges
    return visual_ranges unless visual_ranges.nil?

    range = logical_selection_range
    range ? [range] : []
  end

  # Shift+Left/Right selects the grapheme cells between two visual caret
  # positions. FriBidi can place those cells in separate logical text runs, so
  # return merged logical ranges for the existing copy/edit operations.
  def visual_selection_ranges
    anchor_index = @visual_selection_anchor_position_index
    return nil unless anchor_index.is_a?(Integer)

    positions = visual_caret_positions
    focus_index = active_visual_caret_position(positions)
    return nil unless anchor_index.between?(0, positions.length - 1) && focus_index

    anchor_column = positions[anchor_index][:visual_column]
    focus_column = positions[focus_index][:visual_column]
    return [] if anchor_column == focus_column

    left_column, right_column = [anchor_column, focus_column].minmax
    ranges = editor_visual_layout.filter_map do |item|
      next unless item[:cell_width].to_i.positive?
      next unless item[:cell_start] < right_column && item[:cell_end] > left_column
      next if item[:logical_index].nil? || item[:logical_end].nil?

      [item[:logical_index], item[:logical_end]]
    end.sort_by(&:first)

    ranges.each_with_object([]) do |range, merged|
      if merged.any? && range[0] <= merged[-1][1]
        merged[-1][1] = [merged[-1][1], range[1]].max
      else
        merged << range.dup
      end
    end
  end
  private :visual_selection_ranges

  def selection_active?
    !selection_ranges.empty?
  end
  private :selection_active?

  def logical_selection_range
    return nil if @selection_start.nil?

    start_index = normalize_text_index(@selection_start, bias: :left)
    end_index = normalize_text_index(@cursor_index, bias: :right)
    return nil if start_index == end_index

    [start_index, end_index].sort
  end
  private :logical_selection_range

  def selected_text_for_ranges(ranges)
    ranges.sort_by(&:first).map do |start_index, end_index|
      @text[start_index...end_index].to_s
    end.join
  end
  private :selected_text_for_ranges

  def delete_selection(record_history: true)
    ranges = selection_ranges
    return false if ranges.empty?

    original_cursor = @cursor_index
    positions = visual_caret_positions
    active_position = active_visual_caret_position(positions)

    target_column =
      if active_position.nil?
        visual_cursor_column
      else
        positions[active_position][:visual_column]
      end

    preferred_level =
      active_position.nil? ? 0 : positions[active_position][:bidi_level]

    if record_history
      @history.save_state(
        @text,
        @cursor_index,
        force: true,
        visual_caret: active_position
      )
    end

    # Removing ranges in descending logical order preserves earlier offsets.
    removed_before_cursor = ranges.sum do |start_index, end_index|
      [[end_index, original_cursor].min - start_index, 0].max
    end

    ranges.sort_by(&:first).reverse_each do |start_index, end_index|
      replace_text_range(start_index, end_index, '')
    end

    sync_text_direction!
    @cursor_index = [
      [original_cursor - removed_before_cursor, 0].max,
      @text.length
    ].min

    clear_selection
    normalize_cursor_and_selection!
    invalidate_bidi_cache!
    remember_visual_caret_near!(target_column, preferred_level)
    true
  end

  def clear_selection
    @selection_start = nil
    @visual_selection_anchor_position_index = nil
  end

  def begin_visual_selection_if_needed!
    return unless @selection_start.nil? &&
                  @visual_selection_anchor_position_index.nil?

    positions = visual_caret_positions
    anchor_position = active_visual_caret_position(positions)
    anchor_position ||= positions.each_index.min_by do |index|
      [(positions[index][:logical_index] - @cursor_index).abs, index]
    end
    @visual_selection_anchor_position_index = anchor_position
  end
  private :begin_visual_selection_if_needed!

  # Check the final value length after subtracting all selected logical spans.
  # --- Text mutation and insertion ----------------------------------------

  def replacement_fits_max_length?(incoming_text, ranges = nil)
    return true unless @max_length

    ranges ||= selection_ranges
    if ranges.is_a?(Array) &&
       ranges.length == 2 &&
       ranges.all? { |value| value.is_a?(Integer) }
      ranges = [ranges]
    end

    selected_length = ranges.sum do |start_index, end_index|
      end_index - start_index
    end

    @text.length - selected_length + incoming_text.to_s.length <= @max_length
  end
  private :replacement_fits_max_length?

  # Replace a logical codepoint range; callers retain cursor/history policy.
  def replace_text_range(start_index, end_index, replacement)
    left_part = @text[0...start_index].to_s
    right_part = @text[end_index..-1].to_s
    @text = left_part + replacement.to_s + right_part
    clear_visual_caret_position!
  end
  private :replace_text_range

  # Resolve a dual-caret bidi boundary using the direction of inserted text.
  def visual_insertion_index_for(incoming_text)
    positions = visual_caret_positions
    current_position = active_visual_caret_position(positions)
    direction = inserted_text_direction(incoming_text)
    return @cursor_index if direction.nil?

    target_is_rtl = direction == :rtl
    insertion_index = if current_position.nil?
                        @cursor_index
                      elsif positions[current_position][:bidi_level].to_i.odd? == target_is_rtl
                        @cursor_index
                      else
                        current = positions[current_position]
                        candidates = positions.each_index.select do |index|
                          candidate = positions[index]
                          candidate[:visual_column] == current[:visual_column] &&
                            candidate[:bidi_level].to_i.odd? == target_is_rtl
                        end

                        candidate_index = candidates.min_by do |index|
                          [(index - current_position).abs, index]
                        end
                        candidate_index ? positions[candidate_index][:logical_index] : @cursor_index
                      end

    # The block caret is drawn over an RTL grapheme at its logical start.
    # Typing there should place the new grapheme after the visible one in RTL
    # reading order, which is the grapheme's logical end boundary.
    if target_is_rtl
      item = editor_visual_layout.find do |entry|
        entry[:logical_index] == insertion_index &&
          entry[:bidi_level].to_i.odd? &&
          inserted_text_direction(entry[:char]) == :rtl
      end
      insertion_index = item[:logical_end] if item
    end

    insertion_index
  end
  private :visual_insertion_index_for

  def inserted_text_direction(text)
    text.to_s.each_char do |char|
      next if char.match?(/[\p{M}\s]/)

      return :rtl if self.class.rtl_char?(char)
      return :ltr if char.match?(/[\p{L}\p{N}]/)
    end
    nil
  end
  private :inserted_text_direction

  # Remember the visual side of the new caret after every insertion. This is
  # required even when bidi affinity did not change the logical insertion index.
  def remember_caret_after_insert!(inserted_start, inserted_text)
    return if inserted_text.empty?

    last_inserted_index = inserted_start + inserted_text.length - 1
    item = editor_visual_layout.find do |entry|
      last_inserted_index >= entry[:logical_index] &&
        last_inserted_index < entry[:logical_end]
    end
    return unless item

    desired_column = if item[:bidi_level].to_i.odd?
                       item[:cell_start]
                     else
                       item[:cell_end]
                     end
    positions = visual_caret_positions

    candidates = positions.each_index.select do |index|
      positions[index][:logical_index] == @cursor_index
    end
    return if candidates.empty?

    selected_position = candidates.min_by do |index|
      position = positions[index]
      [
        (position[:visual_column] - desired_column).abs,
        position[:bidi_level].to_i.odd? == item[:bidi_level].to_i.odd? ? 0 : 1,
        index
      ]
    end

    remember_visual_caret_position!(selected_position)
  end
  private :remember_caret_after_insert!

  # Insert text at the resolved logical boundary and advance by codepoint count.
  def insert_text_at_cursor(incoming_text, resolve_visual_direction: true)
    incoming_text = incoming_text.to_s
    insertion_index =
      if resolve_visual_direction
        visual_insertion_index_for(incoming_text)
      else
        @cursor_index
      end

    @cursor_index = insertion_index
    replace_text_range(@cursor_index, @cursor_index, incoming_text)
    @cursor_index += incoming_text.length

    remember_caret_after_insert!(insertion_index, incoming_text)
  end
  private :insert_text_at_cursor

  def paste_text(incoming_text)
    return unless @is_focused

    clean_paste = incoming_text.to_s.gsub(/\e\[\d+~/, '')
    return if clean_paste.empty?
    return unless replacement_fits_max_length?(clean_paste)

    ranges = selection_ranges
    resulting_text = @text.dup

    ranges.sort_by(&:first).reverse_each do |start_index, end_index|
      resulting_text[start_index...end_index] = ''
    end

    insertion_index = ranges.empty? ? @cursor_index : ranges.map(&:first).min
    resulting_text.insert(insertion_index, clean_paste)

    return if resulting_text == @text

    @history.save_state(@text, @cursor_index, force: true,
                                              visual_caret: current_visual_caret_position_index)
    delete_selection(record_history: false)

    @placeholder = '' if @text.empty?

    insert_text_at_cursor(clean_paste)

    sync_text_direction!
    clear_selection
    invalidate_bidi_cache!

    # Place the caret at the visual right edge after paste. For an RTL run,
    # that edge is commonly logical boundary 0, not text.length. Use the same
    # FriBidi-derived boundary list as visual left/right navigation so mixed
    # LTR/RTL content follows the actual visual layout.
    visual_stops = visual_caret_boundaries
    @cursor_index = visual_stops.last unless visual_stops.empty?
  end

  # --- Keyboard event dispatch --------------------------------------------

  def handle_key(key, modifiers = [])
    return unless @is_focused

    mods_gate = Array(modifiers).map { |m| m.to_s.downcase }
    key_gate_str = key.to_s.strip.sub(/\A:/, '')
    key_gate_down = key_gate_str.downcase

    # Detect Shift across the key formats used by supported terminals.
    is_shift_intent = mods_gate.include?('shift') ||
                      key_gate_str.include?(';2u') ||
                      key_gate_str.include?(';10u') ||
                      key_gate_str.include?(';6u')

    # Normalize vertical navigation intent, including terminal escape sequences.
    is_line_start_intent = %w[up k].include?(key_gate_down) ||
                           key_gate_str.include?('Up') ||
                           key_gate_str.include?('1A') ||
                           key_gate_str.include?('5;2u') # Fn-Shift-Up (PageUp) fallback

    is_line_end_intent   = %w[down j].include?(key_gate_down) ||
                           key_gate_str.include?('Down') ||
                           key_gate_str.include?('1B') ||
                           key_gate_str.include?('6;2u') # Fn-Shift-Down (PageDown) fallback

    if is_shift_intent && (is_line_start_intent || is_line_end_intent)
      # Pass normalized key values to the vertical-navigation handler.
      key = is_line_start_intent ? 'up' : 'down'
      modifiers << 'shift' unless modifiers.include?('shift')
    end

    raw_key = key.to_s
    key_str = raw_key.strip
    key_down = key_str.downcase
    mods = Array(modifiers).map { |m| m.to_s.downcase }

    is_enter_key = %w[enter \r \n].include?(key_down) || raw_key.include?('Enter')
    has_alt = mods.include?('alt') || mods.include?('meta') || mods.include?('option')
    has_ctrl = mods.include?('ctrl') || mods.include?('control')
    has_shift = mods.include?('shift')
    is_alt_d = (key_down == 'd' && has_alt) || raw_key.include?("\ed")

    # Ctrl+N/P are handled by the form controller, never by the text field.
    return true if has_ctrl && %w[n p].include?(key_down)
    return true if is_enter_key && has_alt
    return true if handle_ctrl_l(key_str, has_ctrl, has_shift)
    return true if handle_vertical_navigation(key_down, raw_key, has_shift, has_alt)
    return true if handle_transposition(key_str, has_ctrl)

    unless has_shift
      return :next_field if %w[tab].include?(key_down)
      return :prev_field if %w[back_tab backtab].include?(key_down)
    end

    return if %w[enter esc escape].include?(key_down)

    return true if handle_history(key_str, has_ctrl || mods.include?('control'), has_shift)
    return true if handle_clipboard(key_str, mods)
    return true if handle_emacs_wipes(key_str, mods)
    return true if handle_home_end(key_str, mods)
    return true if handle_word_navigation(key_str, key_down, mods)
    return true if handle_character_navigation(key_str, mods, has_shift)
    return true if handle_backspace_wipe(key_str, key_down, mods)
    return true if handle_forward_delete(key_str, key_down, raw_key, mods)

    handle_text_insertion(raw_key, key_str, key_down, mods)
  end

  # Remove the same Unicode direction marks everywhere.
  def strip_direction_marks(text)
    text.to_s.gsub(DIRECTION_MARKS, '')
  end
  private :strip_direction_marks

  # --- Keyboard commands --------------------------------------------------

  def handle_ctrl_l(key_str, has_ctrl, has_shift)
    return false unless has_ctrl && %w[l L].include?(key_str)

    if @text.empty?
      clear_selection unless has_shift
      @cursor_index = 0
    else
      if has_shift
        begin_visual_selection_if_needed!
        @selection_start ||= @cursor_index
      else
        clear_selection
      end

      positions = visual_caret_positions
      center_column = visual_content_width / 2.0
      target_position = positions.each_index.min_by do |index|
        [
          (positions[index][:visual_column] - center_column).abs,
          positions[index][:visual_column],
          index
        ]
      end

      if target_position
        @cursor_index = positions[target_position][:logical_index]
        @active_visual_caret_position_index = target_position
      else
        @cursor_index = (@text.length / 2).floor
        clear_visual_caret_position!
      end
    end

    true
  end

  def handle_vertical_navigation(key_down, raw_key, has_shift, has_alt = false)
    encoded_key = raw_key.to_s.downcase
    alt_up = (has_alt && key_down == 'up') ||
             encoded_key.match?(/\A(?:alt|option|meta)[+_ -]?up\z/) ||
             raw_key.match?(/\A\e\[1;3A\z/i)
    alt_down = (has_alt && key_down == 'down') ||
               encoded_key.match?(/\A(?:alt|option|meta)[+_ -]?down\z/) ||
               raw_key.match?(/\A\e\[1;3B\z/i)

    if alt_up || alt_down
      mods = has_shift ? ['shift'] : []
      return handle_home_end(alt_up ? 'Home' : 'End', mods)
    end

    if %w[up].include?(key_down) || raw_key.include?('Up')
      clear_visual_caret_position!
      if has_shift
        @selection_start ||= @cursor_index
      else
        clear_selection
      end
      first_letter_idx = @text =~ /[^\s\u200E\u200F\u2068\u2069]/
      @cursor_index = first_letter_idx || 0
      invalidate_bidi_cache!
      return true
    elsif %w[down].include?(key_down) || raw_key.include?('Down')
      clear_visual_caret_position!
      if has_shift
        @selection_start ||= @cursor_index
      else
        clear_selection
      end
      @cursor_index = @text.length
      invalidate_bidi_cache!
      return true
    end

    false
  end

  def handle_transposition(key_str, has_ctrl)
    return false unless has_ctrl && %w[t T].include?(key_str)

    # Transpose whole grapheme clusters. A Hebrew base letter and its niqqud
    # occupy one visible cell even though they contain multiple codepoints.
    clusters = []
    offset = 0
    @text.scan(/\X/) do |cluster|
      clusters << [offset, offset + cluster.length, cluster]
      offset += cluster.length
    end

    cursor = @cursor_index.to_i
    # A cursor inside a grapheme has no visual boundary at which to transpose.
    return true if clusters.any? { |start_index, end_index, _| cursor > start_index && cursor < end_index }

    if clusters.length >= 2 && cursor > 0
      # At the end of the text, transpose the last pair; elsewhere transpose
      # the grapheme immediately before the caret with the one after it.
      right_cluster_index = if cursor == @text.length
                              clusters.length - 1
                            else
                              clusters.index { |start_index, _end_index, _| start_index == cursor }
                            end
      return true unless right_cluster_index && right_cluster_index.positive?

      left_start = clusters[right_cluster_index - 1][0]
      split_index = clusters[right_cluster_index][0]
      right_end = clusters[right_cluster_index][1]

      if @history
        @history.save_state(@text, @cursor_index, force: true,
                                                  visual_caret: current_visual_caret_position_index)
      end

      left_cluster = @text[left_start...split_index]
      right_cluster = @text[split_index...right_end]
      replace_text_range(left_start, right_end, right_cluster + left_cluster)
      @cursor_index = right_end

      clear_selection
      invalidate_bidi_cache!
    end
    true
  end

  def handle_history(key_str, has_ctrl, has_shift = false)
    if (has_ctrl && %w[y Y].include?(key_str)) ||
       (has_ctrl && has_shift && %w[z Z].include?(key_str))
      current_visual_caret = active_visual_caret_position(visual_caret_positions)
      forward_state = @history.execute_redo(
        @text, @cursor_index, visual_caret: current_visual_caret
      )
      restore_history_state(forward_state) if forward_state
      return true
    elsif has_ctrl && %w[z Z].include?(key_str)
      current_visual_caret = active_visual_caret_position(visual_caret_positions)
      previous_state = @history.execute_undo(
        @text, @cursor_index, visual_caret: current_visual_caret
      )
      restore_history_state(previous_state) if previous_state
      return true
    end

    false
  end

  def handle_clipboard(key_str, mods)
    if mods.include?('ctrl') && %w[c C].include?(key_str)
      ranges = selection_ranges
      if ranges.empty?
        print "\a"
        $stdout.flush
      else
        text_to_copy = selected_text_for_ranges(ranges)

        copy_text_to_clipboard(text_to_copy)
      end
      return true

    elsif mods.include?('ctrl') && %w[x X].include?(key_str)
      ranges = selection_ranges
      if ranges.empty?
        # Beep when there is no selection to copy or cut.
        print "\a"
        $stdout.flush
      else
        text_to_cut = selected_text_for_ranges(ranges)
        copy_text_to_clipboard(text_to_cut)
        delete_selection # Preserve undo history while removing the selection.
      end

      return true

    elsif mods.include?('ctrl') && %w[v].include?(key_str)
      system_clipboard = ClipboardManager.paste.to_s
      unless system_clipboard.empty?
        return true unless replacement_fits_max_length?(system_clipboard)

        ranges = selection_ranges
        resulting_text = @text.dup

        ranges.sort_by(&:first).reverse_each do |start_index, end_index|
          resulting_text[start_index...end_index] = ''
        end

        insertion_index = ranges.empty? ? @cursor_index : ranges.map(&:first).min
        resulting_text.insert(insertion_index, system_clipboard)

        return true if resulting_text == @text

        if @history
          @history.save_state(@text, @cursor_index, force: true,
                                                    visual_caret: current_visual_caret_position_index)
        end
        delete_selection(record_history: false)

        @placeholder = '' if @text.empty?
        insert_text_at_cursor(system_clipboard)

        sync_text_direction!
        invalidate_bidi_cache!
      end
      return true
    end

    false
  end

  def visual_editing_insertion_index
    positions = visual_caret_positions
    active_position = active_visual_caret_position(positions)
    caret_rtl = if active_position
                  positions[active_position][:bidi_level].to_i.odd?
                else
                  item_at_cursor = editor_visual_layout.find do |item|
                    item[:logical_index] == @cursor_index &&
                      inserted_text_direction(item[:char]) == :rtl
                  end
                  item_at_cursor || @editing_direction == :rtl || @direction == :rtl
                end

    visual_insertion_index_for(caret_rtl ? 'א' : 'a')
  end
  private :visual_editing_insertion_index

  def handle_emacs_wipes(key_str, mods)
    has_ctrl = mods.include?('ctrl') || mods.include?('control')

    if has_ctrl && %w[u U].include?(key_str)
      insertion_index = visual_editing_insertion_index
      if insertion_index > 0
        if @history
          @history.save_state(@text, @cursor_index, force: true,
                                                    visual_caret: current_visual_caret_position_index)
        end
        replace_text_range(0, insertion_index, '')
        @cursor_index = 0
        @placeholder  = @text.empty? ? @default_placeholder : ''
        clear_selection
        invalidate_bidi_cache!
      end
      return true
    elsif has_ctrl && %w[k K].include?(key_str)
      insertion_index = visual_editing_insertion_index

      if insertion_index < @text.length
        if @history
          @history.save_state(@text, @cursor_index, force: true,
                                                    visual_caret: current_visual_caret_position_index)
        end
        replace_text_range(insertion_index, @text.length, '')
        @cursor_index = insertion_index
        @placeholder = @text.empty? ? @default_placeholder : ''
        clear_selection
        invalidate_bidi_cache!
      end
      return true
    end

    false
  end

  # Home/Ctrl+A/Alt+Up/Fn+Left and End/Ctrl+E/Alt+Down/Fn+Right target the
  # same direction-aware edges.
  def handle_home_end(key_str, mods)
    has_ctrl = mods.include?('ctrl') || mods.include?('control')
    has_shift = mods.include?('shift')

    # Normalize symbolic key names, e.g. "Home", "home-left" or "page_up".
    normalized_key = key_str.to_s.strip.downcase.gsub(/[\s_+-]/, '')

    home_key = %w[home homeleft fnleft pageup].include?(normalized_key)
    end_key  = %w[end homeright fnright pagedown].include?(normalized_key)

    # Select all only for Ctrl+Shift+A.
    if key_str.downcase == 'a' && has_ctrl && has_shift
      clear_selection
      @selection_start = 0
      @cursor_index = @text.length
      invalidate_bidi_cache! if respond_to?(:invalidate_bidi_cache!, true)
      return true
    end

    ctrl_a_shortcut = key_str.downcase == 'a' && has_ctrl && !has_shift
    ctrl_e_shortcut = key_str.downcase == 'e' && has_ctrl

    # Ctrl+A/E share the Home/End destinations in the active paragraph direction.
    is_home_shortcut = home_key ||
                       ctrl_a_shortcut ||
                       (%w[left Left].include?(key_str) && mods.include?('super'))

    if is_home_shortcut
      if has_shift
        begin_visual_selection_if_needed!
        @selection_start ||= @cursor_index
      else
        clear_selection
      end

      positions = visual_caret_positions
      target_position = @direction == :rtl ? positions.length - 1 : 0

      self.cursor_index = visual_home_cursor
      remember_visual_caret_position!(target_position) unless positions.empty?

      invalidate_bidi_cache! if respond_to?(:invalidate_bidi_cache!, true)
      return true

    elsif end_key ||
          (%w[right Right].include?(key_str) && mods.include?('super')) ||
          ctrl_e_shortcut

      if has_shift
        begin_visual_selection_if_needed!
        @selection_start ||= @cursor_index
      else
        clear_selection
      end

      positions = visual_caret_positions
      target_position = @direction == :rtl ? 0 : positions.length - 1

      self.cursor_index = visual_end_cursor
      remember_visual_caret_position!(target_position) unless positions.empty?

      invalidate_bidi_cache! if respond_to?(:invalidate_bidi_cache!, true)
      return true
    end

    false
  end

  def handle_word_navigation(key_str, key_down, mods)
    has_shift = mods.include?('shift')
    has_ctrl  = mods.include?('ctrl') || mods.include?('control')
    has_alt   = mods.include?('alt') || mods.include?('meta') ||
                mods.include?('option')

    left_word =
      (%w[left Left].include?(key_str) && (has_ctrl || has_alt)) ||
      key_down.include?('alt_left') ||
      key_down.include?('ctrl_left') ||
      key_down.include?('meta_left') ||
      (%w[b B].include?(key_str) && has_alt) ||
      key_str.include?("\eb")

    right_word =
      (%w[right Right].include?(key_str) && (has_ctrl || has_alt)) ||
      key_down.include?('alt_right') ||
      key_down.include?('ctrl_right') ||
      key_down.include?('meta_right') ||
      (%w[f F].include?(key_str) && has_alt) ||
      key_str.include?("\ef")

    return false unless left_word || right_word

    if has_shift
      begin_visual_selection_if_needed!
      @selection_start ||= @cursor_index
    else
      clear_selection
    end

    normalize_cursor_and_selection!
    positions = visual_caret_positions
    return true if positions.empty?

    target_position = visual_word_target_position(left_word ? :left : :right, positions)
    if target_position
      target = positions[target_position]
      @cursor_index = target[:logical_index]
      @active_visual_caret_position_index = target_position
    end

    @editing_direction = @direction
    true
  end

  def visual_word_target_position(direction, positions = visual_caret_positions)
    return nil if positions.empty?

    current_index = active_visual_caret_position(positions)
    current_index ||= positions.each_index.min_by do |index|
      [(positions[index][:logical_index] - @cursor_index).abs, index]
    end
    current_column = positions[current_index][:visual_column]
    items = editor_visual_layout.select do |item|
      item[:cell_width].to_i.positive?
    end

    if direction == :right
      candidates = items.select { |item| item[:cell_end] > current_column }
      candidates.shift while candidates.first && visual_whitespace_item?(candidates.first)
      word_items = candidates.take_while { |item| !visual_whitespace_item?(item) }
      target_column = word_items.empty? ? positions.last[:visual_column] : word_items.last[:cell_end]
    else
      candidates = items.select { |item| item[:cell_start] < current_column }.reverse
      candidates.shift while candidates.first && visual_whitespace_item?(candidates.first)
      word_items = candidates.take_while { |item| !visual_whitespace_item?(item) }
      target_column = word_items.empty? ? positions.first[:visual_column] : word_items.last[:cell_start]
    end

    return current_index if target_column == current_column

    matches = positions.each_index.select do |index|
      positions[index][:visual_column] == target_column
    end
    return nil if matches.empty?

    direction == :right ? matches.last : matches.first
  end
  private :visual_word_target_position

  def visual_whitespace_item?(item)
    item[:char].to_s.match?(/\A\s+\z/u)
  end
  private :visual_whitespace_item?

  def word_boundary_index(cursor, direction)
    text = @text.to_s
    cursor = normalize_text_index(cursor, bias: :left)

    if direction == :left
      prefix = text[0...cursor]
      match = prefix.match(/\s*\S+\s*\z/u)
      match ? cursor - match[0].length : 0
    else
      suffix = text[cursor..-1].to_s
      match = suffix.match(/\A\s*\S+/u)
      match ? cursor + match[0].length : text.length
    end
  end

  # --- Visual caret navigation and logical deletion ----------------------

  # Left/Right move through the FriBidi-derived visual caret order. Shift
  # selection stores its anchor as a visual caret stop; selected grapheme cells
  # are then mapped back to one or more logical ranges for editing.

  # IMPORTANT: @cursor_index is always the authoritative logical text position.
  # Visual caret positions are display/navigation mappings only. They must
  # never replace the logical cursor index or determine text mutation indices.
  # All editing, selection and history operations must preserve logical indices.
  def handle_character_navigation(key_str, mods, has_shift)
    is_right_nav = %w[right Right].include?(key_str) ||
                   (%w[f F].include?(key_str) && mods.include?('ctrl'))
    is_left_nav = %w[left Left].include?(key_str) ||
                  (%w[b B].include?(key_str) && mods.include?('ctrl'))

    return false unless is_right_nav || is_left_nav

    if has_shift || mods.include?('shift')
      begin_visual_selection_if_needed!
      @selection_start ||= @cursor_index
    else
      clear_selection
    end

    move_cursor_visual(is_right_nav ? :right : :left, has_shift)

    true
  end

  def handle_backspace_wipe(key_str, key_down, mods)
    is_ctrl_h    = (key_str == 'h' && (mods.include?('ctrl') || mods.include?('control'))) || key_str == "Char('\b')"
    is_backspace = %w[backspace 127 \x7F
                      Backspace].include?(key_str) || key_down =~ /x7f/ || key_str == "Char('\x7f')" || is_ctrl_h
    is_ctrl_w    = key_str == 'w' && (mods.include?('ctrl') || mods.include?('control'))

    return false unless is_backspace || is_ctrl_w

    if is_ctrl_w || mods.include?('alt') || mods.include?('meta')
      word_cursor_index = is_ctrl_w ? visual_editing_insertion_index : @cursor_index
      if word_cursor_index > 0
        if @history
          @history.save_state(@text, @cursor_index,
                              visual_caret: current_visual_caret_position_index)
        end
        normalize_cursor_and_selection!
        left_part = @text[0...word_cursor_index]

        if left_part =~ /(\s*\S+\s*)\z/
          word_length = ::Regexp.last_match(1).length
          replace_text_range(word_cursor_index - word_length, word_cursor_index, '')
          @cursor_index = word_cursor_index - word_length
        else
          replace_text_range(0, word_cursor_index, '')
          @cursor_index = 0
        end
      end
    elsif !delete_selection
      # Backspace removes the previous logical character. In an RTL run that
      # character is normally visually to the RIGHT of the caret; in an LTR
      # run it is visually to the LEFT. Use the active caret's bidi level,
      # rather than assuming Backspace always means visual-left.
      positions = visual_caret_positions
      active_position = active_visual_caret_position(positions)
      caret_level = active_position && positions[active_position] && positions[active_position][:bidi_level]
      rtl_caret = if caret_level.nil?
                    @editing_direction == :rtl || @direction == :rtl
                  else
                    caret_level.to_i.odd?
                  end

      delete_character_logical(rtl_caret ? :right : :left, logical_direction: :backward)
    end

    normalize_cursor_and_selection!
    @placeholder = @default_placeholder if @text.empty?
    true
  end

  def handle_forward_delete(key_str, key_down, raw_key, mods)
    has_alt = mods.include?('alt') || mods.include?('meta') || mods.include?('option')
    is_alt_d = (key_down == 'd' && has_alt) || raw_key.include?("\ed")

    is_delete = %w[delete Delete \x04].include?(key_str) || key_down =~ /delete/
    is_ctrl_d = key_str == 'd' && (mods.include?('ctrl') || mods.include?('control'))

    # Support Alt+D and Alt+Delete (Fn+Option+Backspace).
    is_alt_delete = is_alt_d ||
                    (is_delete && has_alt) ||
                    raw_key.include?("\ed")

    return false unless is_delete || is_ctrl_d || is_alt_delete

    deletion_index = if is_alt_d
                       # Alt+D deletes the word in front of the visible
                       # cursor cell. In RTL text the block cursor can cover
                       # that cell, so start at its logical index instead of
                       # advancing past it as text insertion does.
                       @cursor_index
                     else
                       visual_editing_insertion_index
                     end

    if deletion_index < @text.length ||
       selection_active? ||
       visual_cursor_at_left_edge?
      if @history && @history.respond_to?(:save_state)
        @history.save_state(@text, @cursor_index,
                            visual_caret: current_visual_caret_position_index)
      end

      if is_alt_delete
        right_part = @text[deletion_index..-1] || ''
        if right_part =~ /\A(\s*\S+\s*)/
          word_length = ::Regexp.last_match(1).length
          replace_text_range(deletion_index, deletion_index + word_length, '')
        else
          replace_text_range(deletion_index, @text.length, '')
        end
        @cursor_index = deletion_index
      else
        unless delete_selection

          left_edge = visual_cursor_at_left_edge?

          if left_edge
            # At this RTL visual edge, the first displayed character is
            # the last character in logical text order.

            delete_character_logical(:left, logical_direction: :backward)
          else
            positions = visual_caret_positions
            active_position = active_visual_caret_position(positions)
            caret_level =
              active_position && positions[active_position] &&
              positions[active_position][:bidi_level]

            rtl_caret = if caret_level.nil?
                          @editing_direction == :rtl || @direction == :rtl
                        else
                          caret_level.to_i.odd?
                        end

            @cursor_index = deletion_index
            clear_visual_caret_position!

            delete_character_logical(
              rtl_caret ? :left : :right,
              logical_direction: :forward
            )
          end
        end
      end
      @placeholder = @default_placeholder if @text.empty?
    end
    true
  end

  def handle_text_insertion(raw_key, key_str, key_down, mods)
    parsed_char = if raw_key =~ /\AChar\('(.+)'\)\z/m
                    ::Regexp.last_match(1)
                  elsif raw_key.length == 1
                    raw_key
                  end

    return unless parsed_char && !parsed_char.empty?

    if parsed_char == '_' &&
       ((key_down.include?('_') && key_down.length > 1) ||
       key_down.include?('ctrl') || mods.include?('ctrl'))
      # Explicit underscore input is allowed.
    elsif (key_down.include?('_') && key_down.length > 1) ||
          key_down.include?('ctrl') || mods.include?('ctrl')
      return
    end

    normalize_cursor_and_selection!

    ranges = selection_ranges
    selected_length = ranges.sum { |start_index, end_index| end_index - start_index }

    resulting_length = @text.length - selected_length + parsed_char.length
    return if @max_length && resulting_length > @max_length

    @history.save_state(@text, @cursor_index, visual_caret: current_visual_caret_position_index) if @history

    had_selection = !ranges.empty?
    delete_selection if had_selection

    @placeholder = '' if @text.empty?

    insert_text_at_cursor(
      parsed_char,
      resolve_visual_direction: !had_selection
    )
    # Detect RTL input immediately; otherwise an empty field would keep its
    # default LTR alignment.
    sync_text_direction!

    clear_selection
    normalize_cursor_and_selection!
    invalidate_bidi_cache!
    true
  end

  # --- Bidi layout and index mapping --------------------------------------

  def invalidate_bidi_cache!
    @bidi_layout_cache_signature = nil
    @bidi_layout_cache = nil
  end

  def self.visual_text(text)
    value = text.to_s
    return value if value.empty?
    return value unless app_handles_bidi?

    # Use the same FriBidi-based layout as the editor.
    layout = app_visual_layout(text)
    layout.map { |item| item[:char] }.join
  end

  def self.app_visual_layout(text)
    field = new
    field.text = text
    field.editor_visual_layout
  end

  # Keep codepoint-level positions: the cursor may sit between a base
  # character and its combining marks. The bias keyword remains for
  # compatibility; every integer Ruby string index is already a valid stop.
  def normalize_text_index(index, bias: :left)
    [[index.to_i, 0].max, @text.length].min
  end

  def normalize_cursor_and_selection!
    max_index = @text.length
    @cursor_index = [[@cursor_index.to_i, 0].max, max_index].min

    return if @selection_start.nil?

    @selection_start = [[@selection_start.to_i, 0].max, max_index].min
  end

  def self.app_handles_bidi?
    term_program = ENV['TERM_PROGRAM'].to_s.downcase

    return false if term_program.include?('iterm')

    true
  end

  def self.rtl_char?(char)
    return false unless char

    cp = char.ord
    (0x0590..0x08FF).cover?(cp) || (0xFB1D..0xFDFF).cover?(cp) || (0xFE70..0xFEFF).cover?(cp)
  end

  def bidi_visual(text = @text)
    self.class.visual_text(text)
  end

  # Return the terminal-cell width of one grapheme cluster.
  # DisplayWidth measures combining marks and variation selectors
  # together with their base character.
  def terminal_cell_width(cluster)
    value = cluster.to_s
    return 0 if value.empty?

    if defined?(Unicode::DisplayWidth)
      Unicode::DisplayWidth.of(value)
    else
      # Fallback for environments where Unicode::DisplayWidth is unavailable.
      value.each_char.sum do |char|
        if char.match?(/\p{M}/) ||
           char == "\u200D" ||
           char.match?(/[\uFE00-\uFE0F]/)
          0
        elsif char.ord >= 0x1100
          2
        else
          1
        end
      end
    end
  end
  private :terminal_cell_width

  # Total visual content width, measured in terminal cells.
  def visual_content_width
    editor_visual_layout.sum { |item| item[:cell_width].to_i }
  end

  # Build the visual grapheme-cluster layout from FriBidi codepoint mappings.
  def editor_visual_layout
    text = @text.to_s
    return [] if text.empty?

    return @bidi_layout_cache if @bidi_layout_cache_signature == text

    # Pass the original text to FriBidi without a synthetic prefix.
    processed_text = text

    logical_codepoints = processed_text.codepoints
    codepoint_count = logical_codepoints.length

    input_ptr = FFI::MemoryPointer.new(:uint32, codepoint_count)
    input_ptr.write_array_of_uint32(logical_codepoints)

    visual_ptr = FFI::MemoryPointer.new(:uint32, codepoint_count)
    logical_to_visual_ptr = FFI::MemoryPointer.new(:int32, codepoint_count)
    visual_to_logical_ptr = FFI::MemoryPointer.new(:int32, codepoint_count)
    levels_ptr = FFI::MemoryPointer.new(:uint8, codepoint_count)

    base_direction_ptr = FFI::MemoryPointer.new(:uint32)

    base_direction_codepoint =
      @direction == :rtl ? 0x05D0 : 0x0041

    base_direction_ptr.write_uint32(
      FriBidiNative.fribidi_get_bidi_type(base_direction_codepoint)
    )

    result = FriBidiNative.fribidi_log2vis(
      input_ptr, codepoint_count, base_direction_ptr,
      visual_ptr, logical_to_visual_ptr, visual_to_logical_ptr, levels_ptr
    )

    return [] if result.zero?

    # FriBidi is the sole source of the visual codepoint order. Do not rebuild
    # the visual string by moving codepoints back into their logical graphemes:
    # that can attach niqqud/Arabic marks to a neighbouring visible character.
    visual_codepoints = visual_ptr.get_array_of_uint32(0, codepoint_count)
    visual_to_logical = visual_to_logical_ptr.get_array_of_int32(0, codepoint_count)
    bidi_levels = levels_ptr.get_array_of_uint8(0, codepoint_count)
    visual_text = visual_codepoints.pack('U*')

    visual_offset = 0
    cell_column = 0

    @bidi_layout_cache = visual_text.scan(/\X/).each_with_index.map do |visual_cluster, visual_index|
      cluster_codepoints = visual_cluster.codepoints
      cluster_length = cluster_codepoints.length
      visual_range = (visual_offset...(visual_offset + cluster_length))

      logical_indices = visual_range.map do |visual_cp_index|
        logical_cp_index = visual_to_logical[visual_cp_index]
        logical_cp_index if logical_cp_index && logical_cp_index >= 0 && logical_cp_index < codepoint_count
      end.compact

      cluster_chars = visual_cluster.each_char.to_a
      base_char_offset = cluster_chars.index { |char| !char.match?(/\p{M}/) } || 0
      base_visual_index = visual_offset + base_char_offset
      base_logical_index = visual_to_logical[base_visual_index]

      unless base_logical_index && base_logical_index >= 0 && base_logical_index < codepoint_count
        base_logical_index = logical_indices.first
      end

      logical_start = logical_indices.min || base_logical_index || 0
      logical_end = (logical_indices.max || logical_start) + 1
      level = (base_logical_index && bidi_levels[base_logical_index]) || 0

      cell_width = terminal_cell_width(visual_cluster)
      cell_start = cell_column
      cell_end = cell_start + cell_width

      visual_offset += cluster_length
      cell_column = cell_end

      {
        char: visual_cluster,
        logical_index: logical_start,
        logical_end: logical_end,
        logical_indices: logical_indices.dup,
        visual_index: visual_index,
        bidi_level: level,

        # Terminal-cell geometry; visual_index remains a layout-item index.
        cell_width: cell_width,
        cell_start: cell_start,
        cell_end: cell_end
      }
    end

    @bidi_layout_cache_signature = text
    @bidi_layout_cache
  end

  alias visual_layout editor_visual_layout

  # Returns a terminal-cell column, not a codepoint offset. Multiple
  # codepoints inside a grapheme (for example Hebrew niqqud) share one cell.
  #
  # IMPORTANT: @cursor_index remains the authoritative logical text position.
  # The active visual caret occurrence is only a display/navigation mapping
  # and is valid only when it refers to the current logical cursor position.
  def visual_cursor_column
    positions = visual_caret_positions
    return 0 if positions.empty?

    active_index = @active_visual_caret_position_index

    if active_index.is_a?(Integer) &&
       active_index.between?(0, positions.length - 1) &&
       positions[active_index][:logical_index] == @cursor_index
      return positions[active_index][:visual_column]
    end

    # Otherwise, find a visual stop with the current logical index.
    match = positions.find { |position| position[:logical_index] == @cursor_index }
    match ? match[:visual_column] : 0
  end

  def visual_cursor_at_left_edge?
    return false if @text.to_s.empty?
    return false unless paragraph_direction(@text) == :rtl
    return false unless @cursor_index == @text.length

    positions = visual_caret_positions
    return false if positions.empty?

    # The final logical character may be neutral punctuation. FriBidi can give
    # it an even embedding level even though the paragraph's logical end is
    # still the visual left edge. Determine the edge from the caret stops,
    # rather than the bidi level of that final grapheme.
    leftmost_column = positions.map { |position| position[:visual_column] }.min
    positions.any? do |position|
      position[:logical_index] == @text.length &&
        position[:visual_column] == leftmost_column
    end
  end

  # True when logical boundary zero is the visual right edge of an RTL run.
  def visual_cursor_at_right_edge?
    return false if @text.to_s.empty?
    return false unless paragraph_direction(@text) == :rtl
    return false unless @cursor_index.zero?

    layout = editor_visual_layout
    return false if layout.empty?

    item = layout.find do |entry|
      entry[:logical_index] <= 0 && 0 < entry[:logical_end]
    end

    item && item[:bidi_level].to_i.odd? &&
      item[:visual_index] == layout.length - 1
  end

  # Index of the visible grapheme item whose cell should show the cursor.
  # At the logical end of an RTL paragraph, the insertion point is outside the
  # text on its visual left edge and uses a separate cell. At the logical start
  # on the visual right edge, map to the outermost existing grapheme.
  def visual_cursor_item_index
    layout = editor_visual_layout
    return 0 if layout.empty?

    if paragraph_direction(@text) == :rtl
      return -1 if visual_cursor_at_left_edge?

      if visual_cursor_at_right_edge?
        right_item = layout.reverse.find { |item| item[:cell_width].positive? }
        return right_item[:visual_index] if right_item
      end
    end

    active_index = @active_visual_caret_position_index
    stops = visual_caret_positions

    if active_index.is_a?(Integer) &&
       active_index >= 0 &&
       active_index < stops.length
      stop = stops[active_index]

      if stop[:logical_index] == @cursor_index &&
         stop[:visual_index].is_a?(Integer) &&
         stop[:visual_index] >= 0 &&
         stop[:visual_index] < layout.length
        rtl_paragraph_left_run = paragraph_direction(@text) == :rtl &&
                                 layout.first &&
                                 layout.first[:bidi_level].to_i.odd?
        if stop[:bidi_level].to_i.odd? && rtl_paragraph_left_run
          rtl_items_at_boundary = layout.select do |item|
            item[:bidi_level].to_i.odd? &&
              (item[:logical_index] == @cursor_index ||
               item[:logical_end] == @cursor_index)
          end

          # In visual order the cell just crossed is immediately to the left
          # of this caret stop. Prefer it at shared RTL boundaries, where the
          # logical boundary belongs to both neighboring graphemes.
          crossed_item = rtl_items_at_boundary.select do |item|
            item[:cell_end] == stop[:visual_column]
          end.max_by { |item| item[:visual_index] }
          crossed_item ||= rtl_items_at_boundary.min_by { |item| item[:visual_index] }
          return crossed_item[:visual_index] if crossed_item
        end

        return stop[:visual_index]
      end
    end

    cursor = [[@cursor_index.to_i, 0].max, @text.length].min
    # Preserve a visible cell at either visual edge, including for a cursor at
    # the logical start or end of a mixed-direction paragraph.
    return 0 if visual_cursor_at_left_edge?
    return layout.length - 1 if visual_cursor_at_right_edge?

    layout.each do |item|
      first = item[:logical_index]
      last = item[:logical_end]
      rtl = item[:bidi_level].to_i.odd?

      return item[:visual_index] if cursor > first && cursor < last

      if rtl
        return item[:visual_index] if cursor == first || cursor == last
      else
        return item[:visual_index] if cursor == first
        return item[:visual_index] + 1 if cursor == last
      end
    end

    layout.length
  end

  def punctuation_item_at_visual_edge(edge)
    items = edge == :left ? editor_visual_layout : editor_visual_layout.reverse
    item = items.find { |entry| entry[:cell_width].positive? }
    item if item && item[:char].match?(/\A\p{P}+\z/)
  end
  private :punctuation_item_at_visual_edge

  # Paragraph base direction follows the first strong letter, not the presence
  # of any RTL character somewhere later in a mixed-direction string.
  def paragraph_direction(text)
    first_strong = text.to_s.scan(/\X/).lazy.map do |cluster|
      cluster.each_char.find do |char|
        char.match?(/\p{L}/) && !char.match?(/\p{M}/)
      end
    end.find(&:itself)

    first_strong && self.class.rtl_char?(first_strong) ? :rtl : :ltr
  end

  # This is a single-line field. Home and End target the paragraph's logical
  # start/end edges in visual order. In mixed-direction strings, these edge
  # boundaries need not be logical indices 0 or text.length.
  def visual_home_cursor
    positions = visual_caret_positions
    return 0 if positions.empty?

    edge = @direction == :rtl ? positions.last : positions.first
    edge[:logical_index]
  end

  def visual_end_cursor
    positions = visual_caret_positions
    return @text.length if positions.empty?

    edge = @direction == :rtl ? positions.first : positions.last
    edge[:logical_index]
  end

  # Choose alignment from the first strong character only once. After that,
  # adding text in the opposite script must not make the field jump sides.
  # The active editing direction is a separate state and is not re-detected
  # from every mutation.
  def sync_text_direction!
    if @text.empty?
      @direction = @alignment_override || @initial_direction
      @alignment_locked = !@alignment_override.nil?
      @editing_direction = @direction
      @editing_direction_manual = false
      return
    end

    unless @alignment_locked
      detected = first_strong_direction(@text)
      if detected
        @direction = detected
        @alignment_locked = true
      end
    end

    @editing_direction = @direction unless @editing_direction_manual
  end
  private :sync_text_direction!

  # Restore the same editor state after undo or redo.
  def restore_history_state(state)
    clear_visual_caret_position!
    @text = state[:text]
    sync_text_direction!
    @cursor_index = state[:cursor]
    @placeholder = @text.empty? ? @default_placeholder : ''
    clear_selection
    invalidate_bidi_cache!

    # Restore the same visual occurrence only if it still matches this state.
    restored_position = state[:visual_caret]
    positions = visual_caret_positions
    valid_visual_caret =
      restored_position.is_a?(Integer) &&
      restored_position >= 0 &&
      restored_position < positions.length &&
      positions[restored_position][:logical_index] == @cursor_index

    if valid_visual_caret
      remember_visual_caret_position!(restored_position)
    else
      clear_visual_caret_position!
    end
  end
  private :restore_history_state

  def text=(value)
    @history.clear
    clear_visual_caret_position!
    @text = value.to_s

    # Assigning a new complete value starts a fresh automatic alignment pass.
    # This differs from incremental typing, which must keep the chosen side.
    @direction = @alignment_override || @initial_direction
    @alignment_locked = !@alignment_override.nil?
    @editing_direction = @direction
    @editing_direction_manual = false
    sync_text_direction!

    # Start a newly assigned value with the logical caret at the text end.
    # The visual layout maps that logical boundary to its displayed position.
    @cursor_index = @text.length
    @selection_start = nil
    @visual_selection_anchor_position_index = nil

    invalidate_bidi_cache!
    @text
  end

  def copy_text_to_clipboard(text)
    direction = detect_direction(text)
    ClipboardManager.copy(text, direction)
  end
  private :copy_text_to_clipboard

  def detect_direction(text)
    first_strong_direction(strip_direction_marks(text)) || :ltr
  end

  def first_strong_direction(text)
    first_strong = text.to_s.scan(/\X/).lazy.map do |cluster|
      cluster.each_char.find do |char|
        char.match?(/\p{L}/) && !char.match?(/\p{M}/)
      end
    end.find(&:itself)

    return nil unless first_strong

    self.class.rtl_char?(first_strong) ? :rtl : :ltr
  end
  private :first_strong_direction

  # --- Visual caret bookkeeping -------------------------------------------
  # Forget the active visual caret occurrence when another operation relocates it.

  def clear_visual_caret_position!
    @active_visual_caret_position_index = nil
  end
  private :clear_visual_caret_position!

  def remember_visual_caret_position!(position)
    @active_visual_caret_position_index = position
  end
  private :remember_visual_caret_position!

  def active_visual_caret_position(positions)
    position = @active_visual_caret_position_index

    return nil unless position.is_a?(Integer)
    return nil unless position.between?(0, positions.length - 1)
    return nil unless positions[position][:logical_index] == @cursor_index

    position
  end
  private :active_visual_caret_position

  def remember_visual_caret_near!(target_column, preferred_level)
    positions = visual_caret_positions
    if positions.empty?
      clear_visual_caret_position!
      return
    end

    candidates = positions.each_index.select do |index|
      positions[index][:logical_index] == @cursor_index
    end

    if candidates.empty?
      clear_visual_caret_position!
      return
    end

    preferred_parity = preferred_level.to_i.odd?
    chosen = candidates.min_by do |index|
      position = positions[index]
      [
        (position[:visual_column] - target_column).abs,
        position[:bidi_level].to_i.odd? == preferred_parity ? 0 : 1,
        index
      ]
    end

    remember_visual_caret_position!(chosen)
  end
  private :remember_visual_caret_near!

  # Preserve the active visual occurrence in undo/redo snapshots.
  def current_visual_caret_position_index
    active_visual_caret_position(visual_caret_positions)
  end
  private :current_visual_caret_position_index

  # Each stop retains both its logical boundary and its visual terminal column.
  # Repeated logical indices at bidi-run boundaries represent distinct positions.
  def visual_caret_positions
    layout = editor_visual_layout
    return [] if layout.empty?

    positions = []
    # Process layout items in visual order, from left to right.
    layout.sort_by { |item| item[:visual_index] }.each do |item|
      first = item[:logical_index]
      last = item[:logical_end]

      boundaries = if item[:bidi_level].odd?
                     [last, first]
                   else
                     [first, last]
                   end

      boundaries.each do |boundary|
        visual_column = if item[:bidi_level].to_i.odd?
                          boundary == first ? item[:cell_end] : item[:cell_start]
                        else
                          boundary == first ? item[:cell_start] : item[:cell_end]
                        end

        cursor_visual_index =
          if visual_column >= item[:cell_end]
            item[:visual_index] + 1
          else
            item[:visual_index]
          end

        # Directional controls such as RLM affect FriBidi's ordering but have
        # no terminal cell. Attach their caret edges to the next visible item
        # so arrows never stop on an invisible control instead of punctuation.
        while cursor_visual_index < layout.length &&
              layout[cursor_visual_index][:cell_width].zero?
          cursor_visual_index += 1
        end

        stop = {
          logical_index: boundary,
          visual_column: visual_column,
          bidi_level: item[:bidi_level],
          visual_index: cursor_visual_index
        }

        previous = positions.last

        if previous &&
           previous[:visual_column] == stop[:visual_column] &&
           previous[:visual_index] == stop[:visual_index] &&
           previous[:logical_index] == stop[:logical_index]
          positions[-1] = stop
        else
          positions << stop
        end
      end
    end

    positions
  end
  private :visual_caret_positions

  # Public compatibility API: return logical boundaries in visual order.
  def visual_caret_boundaries(_map = nil)
    visual_caret_positions.map { |position| position[:logical_index] }
  end

  # Moves the caret one visual stop for Left/Right navigation.
  # @cursor_index remains the authoritative logical text position:
  # each visual stop is mapped back to its corresponding logical index.
  # The active visual stop is only navigation/display affinity.
  def move_cursor_visual(nav_direction, with_shift = false)
    return if @text.empty?

    normalize_cursor_and_selection!
    positions = visual_caret_positions
    return if positions.empty?

    current_pos = @active_visual_caret_position_index

    unless current_pos && positions[current_pos] && positions[current_pos][:logical_index] == @cursor_index
      current_pos = positions.each_index.min_by do |i|
        [(positions[i][:logical_index] - @cursor_index).abs, i]
      end || 0
    end

    step = nav_direction == :left ? -1 : 1
    target_pos = current_pos + step

    if target_pos.between?(0, positions.length - 1) &&
       positions[target_pos][:visual_column] == positions[current_pos][:visual_column]
      # A bidi boundary can have two logical caret stops at the same screen
      # column. Moving between those stops alone produces a dead keypress.
      current_column = positions[current_pos][:visual_column]
      target_pos += step
      while target_pos.between?(0, positions.length - 1) &&
            positions[target_pos][:visual_column] == current_column
        target_pos += step
      end
    end

    if target_pos.between?(0, positions.length - 1)
      # If the destination column itself has two bidi affinities, choose the
      # far side in the travel direction so one arrow press lands there.
      target_column = positions[target_pos][:visual_column]
      next_pos = target_pos + step
      while next_pos.between?(0, positions.length - 1) &&
            positions[next_pos][:visual_column] == target_column
        target_pos = next_pos
        next_pos += step
      end
    end

    if target_pos.between?(0, positions.length - 1)
      target_entry = positions[target_pos]
      @cursor_index = target_entry[:logical_index]
      @active_visual_caret_position_index = target_pos
    end

    @editing_direction = @direction
  end

  # Delete exactly one codepoint adjacent to the visual caret. In particular,
  # never delete an entire grapheme just because it contains niqqud.
  def delete_character_logical(direction, logical_direction: nil)
    return false if @text.empty?

    normalize_cursor_and_selection!
    layout = editor_visual_layout
    positions = visual_caret_positions
    stops = positions.map { |entry| entry[:logical_index] }
    return false if layout.empty? || stops.empty?

    cursor = @cursor_index
    logical_direction ||= (direction == :left ? :backward : :forward)
    position = active_visual_caret_position(positions)
    position ||= stops.index(cursor)
    position ||= stops.each_index.min_by { |i| [(stops[i] - cursor).abs, i] }

    step = case direction
           when :left then -1
           when :right then 1
           else return false
           end
    adjacent_position = position + step
    return false unless adjacent_position.between?(0, stops.length - 1)

    # Resolve the character to delete from the LOGICAL side requested by the
    # key, not from whichever grapheme happens to be visually adjacent after
    # bidi reordering. Otherwise Backspace next to a bidi boundary can delete
    # a niqqud from the Hebrew run instead of the logically preceding letter.
    logical_neighbor_index = logical_direction == :backward ? cursor - 1 : cursor
    return false unless logical_neighbor_index.between?(0, @text.length - 1)

    codepoint_index = logical_neighbor_index
    logical_neighbor = @text[logical_neighbor_index]

    if logical_neighbor&.match?(/\p{M}/)
      # If the logical neighbour is already a combining mark, remove exactly
      # that mark. Repeated presses naturally walk through the niqquds.
      codepoint_index = logical_neighbor_index
    end

    current_caret = positions[position]
    current_column = current_caret[:visual_column]

    # Use the visual run on the caret's right as the preferred bidi-level anchor.
    right_neighbor = layout.find do |entry|
      entry[:cell_start] == current_column
    end
    preferred_level = right_neighbor ? right_neighbor[:bidi_level] : current_caret[:bidi_level]

    deleted_item = layout.find do |entry|
      codepoint_index >= entry[:logical_index] &&
        codepoint_index < entry[:logical_end]
    end

    deleted_char = @text[codepoint_index]
    deleting_combining_mark = deleted_char&.match?(/\p{M}/)

    target_column = current_column

    if direction == :left &&
       !deleting_combining_mark &&
       deleted_item &&
       deleted_item[:cell_end] == current_column
      target_column -= deleted_item[:cell_width].to_i
    end

    target_column = [target_column, 0].max

    @history.save_state(@text, @cursor_index, visual_caret: position) if @history&.respond_to?(:save_state)

    replace_text_range(codepoint_index, codepoint_index + 1, '')
    sync_text_direction!

    cursor_after_delete = cursor
    cursor_after_delete -= 1 if codepoint_index < cursor

    @cursor_index = [
      [cursor_after_delete, 0].max,
      @text.length
    ].min
    @placeholder = @default_placeholder if @text.empty?
    clear_selection
    invalidate_bidi_cache!

    remaining_positions = visual_caret_positions

    if remaining_positions.empty?
      @cursor_index = 0
      clear_visual_caret_position!
    else
      selected_position = remaining_positions.each_index.min_by do |index|
        candidate = remaining_positions[index]

        logical_distance = (candidate[:logical_index] - cursor_after_delete).abs
        visual_distance = (candidate[:visual_column] - target_column).abs
        level_match =
          candidate[:bidi_level].to_i.odd? == preferred_level.to_i.odd?

        if logical_direction == :forward
          [
            candidate[:logical_index] == cursor_after_delete ? 0 : 1,
            level_match ? 0 : 1,
            visual_distance,
            logical_distance,
            index
          ]
        else
          [
            logical_distance,
            visual_distance,
            level_match ? 0 : 1,
            index
          ]
        end
      end

      @cursor_index = if logical_direction == :forward
                        cursor_after_delete
                      else
                        remaining_positions[selected_position][:logical_index]
                      end

      remember_visual_caret_position!(selected_position)
    end
    true
  end

  # --- Display and viewport rendering -------------------------------------

  def update_viewport(width, line_length)
    width = [width.to_i, 1].max
    line_length = [line_length.to_i, 0].max

    @viewport_start ||= 0

    cursor = [[visual_cursor_column.to_i, 0].max, line_length].min

    if cursor < @viewport_start
      @viewport_start = cursor
    elsif cursor >= @viewport_start + width
      @viewport_start = cursor - width + 1
    end

    max_start = [line_length - width, 0].max
    @viewport_start = [[@viewport_start, 0].max, max_start].min
  end

  def display_value(active_color, inactive_color)
    settings = AppConfig.settings

    cursor_fg_value = settings.theme_item(:cursor_text)
    cursor_bg_value = settings.theme_item(:cursor_color)
    selection_fg = settings.theme_item(:foreground)
    selection_background = settings.theme_item(:selection_background)

    active_lang = settings.language
    is_handwritten = settings.handwritten?(active_lang)

    is_latin_or_common = lambda do |cluster|
      cluster.to_s.match?(/\A[\p{Latin}0-9\s[:punct:]]+\z/)
    end

    parse_color = lambda do |val|
      val_str = val.to_s.strip
      if val.is_a?(Symbol)
        val
      elsif val_str.start_with?('#')
        val_str
      else
        val_str.to_sym
      end
    end

    cursor_fg = parse_color.call(cursor_fg_value)
    cursor_bg = parse_color.call(cursor_bg_value)
    s_fg      = parse_color.call(selection_fg)
    s_bg      = parse_color.call(selection_background)

    act_fg = active_color.is_a?(Symbol) ? active_color : active_color.to_s
    cursor_is_currently_visible = editor_cursor_visible?

    if @text.empty?
      placeholder = @placeholder.to_s
      placeholder_clusters = placeholder.scan(/\X/)

      first_cluster = placeholder_clusters.shift || ' '

      cursor_style =
        if @is_focused && cursor_is_currently_visible
          {
            fg: cursor_fg,
            bg: cursor_bg,
            modifiers: [:dim]
          }
        else
          {
            fg: inactive_color,
            bg: settings.theme_item(:background),
            modifiers: [:dim]
          }
        end

      spans = [
        RatatuiRuby::Text::Span.new(
          content: first_cluster,
          style: cursor_style
        )
      ]

      unless placeholder_clusters.empty?
        spans << RatatuiRuby::Text::Span.new(
          content: placeholder_clusters.join,
          style: {
            fg: inactive_color,
            bg: settings.theme_item(:background),
            modifiers: [:dim]
          }
        )
      end

      return RatatuiRuby::Text::Line.new(spans: spans)
    end

    ranges = selection_ranges
    layout = editor_visual_layout
    target_visual_index = visual_cursor_item_index

    spans = []

    # At the logical end of RTL text, the caret is after the last logical
    # character, which is the visual left edge. Render its insertion cell there.
    if @is_focused && target_visual_index == -1
      spans << RatatuiRuby::Text::Span.new(
        content: ' ',
        style: if cursor_is_currently_visible
                 { bg: cursor_bg, fg: cursor_fg }
               else
                 { fg: act_fg }
               end
      )
    end

    layout.each do |item|
      cluster = item[:char].to_s

      style = { fg: act_fg }

      item_selected =
        !item[:logical_index].nil? &&
        ranges.any? do |selected_range|
          item[:logical_index] < selected_range[1] &&
            item[:logical_end] > selected_range[0]
        end

      # Selection styling
      if item_selected
        style[:bg] = s_bg
        style[:fg] = s_fg
      end

      # Cursor styling
      if @is_focused &&
         item[:visual_index] == target_visual_index &&
         cursor_is_currently_visible

        style[:bg] = cursor_bg
        style[:fg] = cursor_fg
      end

      # Handwritten typography
      style[:modifiers] = Array(style[:modifiers]) | [:italic] if is_handwritten && !is_latin_or_common.call(cluster)

      spans << RatatuiRuby::Text::Span.new(
        content: cluster,
        style: style
      )
    end

    # Cursor after the last visual cluster
    if @is_focused && target_visual_index >= layout.length
      spans << (
        if cursor_is_currently_visible
          RatatuiRuby::Text::Span.new(
            content: ' ',
            style: {
              bg: cursor_bg,
              fg: cursor_fg
            }
          )
        else
          RatatuiRuby::Text::Span.new(
            content: ' ',
            style: { fg: act_fg }
          )
        end
      )
    end

    RatatuiRuby::Text::Line.new(spans: spans)
  end

  def visible_display_line(width, active_color, inactive_color, alignment: :left)
    width = [width.to_i, 1].max

    line = display_value(active_color, inactive_color)

    spans_with_clusters = line.spans.map do |span|
      clusters = span.content.to_s.scan(/\X/)
      widths = clusters.map { |cluster| terminal_cell_width(cluster) }
      [span, clusters, widths]
    end

    line_length = spans_with_clusters.sum do |_span, _clusters, widths|
      widths.sum
    end

    # When focused, keep the caret inside the viewport.
    # When unfocused, show the aligned edge and reserve space for an ellipsis.
    if @text.empty?
      # Always reserve an ellipsis cell for an empty-field placeholder.
      add_ellipsis = true
      visible_width = [width - 1, 0].max

      first =
        if alignment == :right
          [line_length - visible_width, 0].max
        else
          0
        end

    elsif @is_focused
      @viewport_start ||= 0
      update_viewport(width, line_length)
      first = @viewport_start
      visible_width = width
      add_ellipsis = false

    else
      add_ellipsis = line_length > width
      visible_width = add_ellipsis ? [width - 1, 0].max : width

      first =
        if alignment == :right
          [line_length - visible_width, 0].max
        else
          0
        end
    end

    last = first + visible_width
    column = 0
    visible_spans = []

    spans_with_clusters.each do |span, clusters, widths|
      visible_clusters = []

      clusters.each_with_index do |cluster, index|
        cluster_width = widths[index]
        cluster_start = column
        cluster_end = cluster_start + cluster_width

        if cluster_width.zero?
          visible_clusters << cluster if cluster_start >= first && cluster_start < last
        elsif cluster_start >= first && cluster_end <= last
          visible_clusters << cluster
        end

        column = cluster_end
      end

      unless visible_clusters.empty?
        visible_spans << RatatuiRuby::Text::Span.new(
          content: visible_clusters.join,
          style: span.style
        )
      end

      break if column >= last
    end

    if add_ellipsis
      ellipsis = RatatuiRuby::Text::Span.new(
        content: '…',
        style: {
          fg: inactive_color,
          bg: AppConfig.settings.theme_item(:background),
          modifiers: [:dim]
        }
      )

      if alignment == :right
        visible_spans.unshift(ellipsis)
      else
        visible_spans << ellipsis
      end
    end

    RatatuiRuby::Text::Line.new(spans: visible_spans)
  end

  def render_to_frame(frame, area, active_color = nil, inactive_color = nil, alignment: nil)
    settings = AppConfig.settings

    active_color ||= settings.theme_item(:foreground) # text in active or inactive input fields
    inactive_color ||= settings.theme_item(:foreground) # text of placeholder text in input fields

    alignment ||= direction == :rtl ? :right : :left

    line = visible_display_line(
      area.width,
      active_color,
      inactive_color,
      alignment: alignment
    )

    frame.render_widget(
      RatatuiRuby::Widgets::Paragraph.new(
        text: line,
        alignment: alignment,
        wrap: false
      ),
      area
    )

    nil
  end

  def render(area, buf, active_color = nil, inactive_color = nil)
    settings = AppConfig.settings

    # Use the same color defaults as render_to_frame.
    # This method writes directly to the supplied buffer instead of a frame.
    active_color ||= settings.theme_item(:foreground) # text in active or inactive input fields
    inactive_color ||= settings.theme_item(:foreground) # text of placeholder text in input fields

    line = visible_display_line(
      area.width,
      active_color,
      inactive_color,
      alignment: direction == :rtl ? :right : :left
    )

    buf.set_line(area.x, area.y, line, area.width)
    nil
  end

  # --- Focus and cursor visibility ----------------------------------------

  def set_editor_focus(focused)
    focused = !!focused
    previous_focus = @last_editor_focus

    if previous_focus == true && !focused
      clear_selection if respond_to?(:clear_selection)
      @force_cursor_visible = false

    elsif previous_focus != true && focused
      @force_cursor_visible = true
      @popup_rtl_edge_cursor_shown = false
    end

    @last_editor_focus = focused
    @is_focused = focused
  end

  def editor_cursor_visible?
    visible = App.software_cursor.visible

    if @force_cursor_visible
      @force_cursor_visible = false if visible
      return true
    end

    visible
  end
end
