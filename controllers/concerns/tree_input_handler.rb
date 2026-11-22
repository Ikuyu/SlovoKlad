module TreeInputHandler
  include SearchInputHandler

  # Synchronize the active subject/source/deck indices with the persistent ID path.
  # Missing or invalid levels safely fall back to index 0.
  def sync_indices_from_tree_path
    if @tree.nil? || @tree.selected_path.nil? || @tree.selected_path.empty?
      @current_subject_idx = 0
      @current_source_idx  = 0
      @current_deck_idx    = 0
      return
    end

    # Extract only the levels that are actually available.
    sub_id_str  = @tree.selected_path[0]
    src_id_str  = @tree.selected_path[1]
    deck_id_str = @tree.selected_path[2]

    # 1. Always match the Subject by its persistent ID.
    s_idx = @library.subjects.index { |s| s.id.to_s == sub_id_str.to_s } || 0
    @current_subject_idx = s_idx

    # 2. Match the Source if present at level 2 or 3; otherwise fall back to 0.
    if src_id_str && @library.subjects[s_idx]
      src_idx = @library.subjects[s_idx].sources.index { |src| src.id.to_s == src_id_str.to_s } || 0
      @current_source_idx = src_idx
    else
      @current_source_idx = 0
    end

    # 3. Match the Deck if present at level 3; otherwise fall back to 0.
    if deck_id_str && @library.subjects[s_idx] && @library.subjects[s_idx].sources[@current_source_idx]
      d_idx = @library.subjects[s_idx].sources[@current_source_idx].decks.index do |d|
        d.id.to_s == deck_id_str.to_s
      end || 0
      @current_deck_idx = d_idx
    else
      @current_deck_idx = 0
    end
  end

  # Central tree-key router for normalization, focus gating, navigation, and mutations.
  # Preserve the existing order of shortcuts and mutations deliberately.
  def handle_tree_input(key, modifiers = [])
    mods = Array(modifiers).map { |m| m.to_s.downcase }
    has_alt = mods.include?('alt') || mods.include?('option') || mods.include?('meta')
    has_shift = mods.include?('shift')
    has_ctrl = mods.include?('ctrl') || mods.include?('control')

    # =========================================================================
    # 🎯 COUPLING GUARD: DIRECT RETROACTIVE RETENTION (ALT+SPACE FIX)
    # Use the reliable ASCII byte [32] check at the entry point.
    # This bypasses macOS interception before the focus checks.
    # =========================================================================
    is_pure_alt_space = (key.to_s == ' ' && has_alt) || (key.to_s.bytes == [32] && has_alt)

    if is_pure_alt_space
      before_state = capture_selection_state
      current_node = if defined?(@tree_state) && @tree_state && @tree.respond_to?(:visible_nodes)
                       @tree.visible_nodes[@tree_state.selected]
                     end
      current_path = current_node ? current_node[:path] : nil
      selected_idx = defined?(@tree_state) && @tree_state ? @tree_state.selected : 0

      if current_path
        @selected_tree_paths ||= []
        @tree_selection_anchor_index = selected_idx.to_i

        if @selected_tree_paths.include?(current_path)
          @selected_tree_paths.delete(current_path) # Backtracking -> wissen
        else
          @selected_tree_paths << current_path
        end

        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
        sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      end

      record_selection_change(before_state)

      return true # Consumeer het event direct en voorkom doorlekken!
    end

    # =========================================================================
    # 🎯 FIX: CTRL+N / CTRL+P AND SHIFT-ARROW ALIASES
    # Normalize input at the entry point for consistent handling.
    # =========================================================================
    check_key = key.to_s.strip.sub(/\A:/, '').downcase
    if has_shift && %w[up down].include?(check_key)
      key = check_key == 'up' ? 'K' : 'J'
    end

    if has_ctrl && %w[n p].include?(check_key)
      key = check_key == 'n' ? :down : :up
      has_ctrl = false
    end

    # Gate input by the active focus.
    return false unless @active_focus == :tree || @active_focus == :replace_mode

    raw_key = key.to_s.strip.sub(/\A:/, '')
    key_down = raw_key.downcase

    if @active_focus == :tree && has_ctrl && has_shift && key_down == 'a'
      before_state = capture_selection_state
      visible_nodes = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
      @selected_tree_paths = visible_nodes.filter_map { |n| n[:path] }.uniq
      reset_tree_shift_selection
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      record_selection_change(before_state)

      return true
    end

    # Named keys are case-insensitive:
    # :end, "End", and "END" all become "end".
    # Preserve the case of letter keys because "G" and "g", and "K" and "k",
    # may trigger different actions.
    key_str = if %w[home end page_up pageup page_down pagedown].include?(key_down)
                key_down
              else
                raw_key
              end

    if has_ctrl
      allowed_tree_ctrl_keys = %w[u d f h z y n p a]
      return false unless allowed_tree_ctrl_keys.include?(key_down)

      return true if key_down == 'a' && !has_shift
    end

    return true if trigger_search_replace_popups(key, has_ctrl, has_alt, has_shift)
    return true if handle_undo_redo_shortcuts(key, has_ctrl, has_shift)

    current_node = if defined?(@tree_state) && @tree_state && @tree.respond_to?(:visible_nodes)
                     @tree.visible_nodes[@tree_state.selected]
                   else
                     nil
                   end
    current_path = current_node ? current_node[:path] : nil
    selected_idx = defined?(@tree_state) && @tree_state ? @tree_state.selected : 0
    @selected_tree_paths ||= []

    case key_str

    # =========================================================================
    # VERTICAL NAVIGATION & BOUNDARY JUMPS (INDEX MAPPING)
    # =========================================================================
    when 'down', 'j'
      was_page_navigation_active = @tree_page_navigation_active
      before_state = capture_selection_state

      unless has_shift
        @selected_tree_paths = []
        reset_tree_shift_selection
      end

      retained_page_start = nil

      if @tree_state && @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && @tree.visible_nodes.any?
        current_idx = @tree_state.selected || 0
        next_idx = (current_idx + 1) % @tree.visible_nodes.length

        if was_page_navigation_active
          page_size = [(@tree_visible_height || 1).to_i, 1].max
          page_start = (@tree_page_viewport_start || @tree_state.offset || 0).to_i
          page_end = page_start + page_size - 1
          retained_page_start = page_start
          if next_idx > page_end
            retained_page_start += 1
          elsif next_idx == 0
            retained_page_start = 0
          end
        end

        @tree_state.select(next_idx)
        @tree.selected_path = @tree.visible_nodes[next_idx][:path]
      elsif @tree.respond_to?(:move_selection)
        @tree.move_selection(:down)
      end

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # refresh_nodes/ListState may pull the offset back to the selection.
      # Restore the page-jump viewport after refreshing.
      if was_page_navigation_active && !retained_page_start.nil?
        set_tree_page_offset(retained_page_start)
        @tree_page_viewport_start = retained_page_start
        @search_page_viewport_start = retained_page_start if defined?(@search_page_viewport_start)
        @tree_viewport_render_lock = retained_page_start
      end

      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      record_selection_change(before_state)

      return true

    when 'up', 'k'
      was_page_navigation_active = @tree_page_navigation_active
      before_state = capture_selection_state

      unless has_shift
        @selected_tree_paths = []
        reset_tree_shift_selection
      end

      retained_page_start = nil

      if @tree_state && @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && @tree.visible_nodes.any?
        current_idx = @tree_state.selected || 0
        prev_idx = (current_idx - 1) % @tree.visible_nodes.length

        if was_page_navigation_active
          page_size = [(@tree_visible_height || 1).to_i, 1].max
          page_start = (@tree_page_viewport_start || @tree_state.offset || 0).to_i
          retained_page_start = page_start
          if prev_idx < page_start
            retained_page_start -= 1
          elsif prev_idx == @tree.visible_nodes.length - 1
            retained_page_start = [@tree.visible_nodes.length - page_size, 0].max
          end
        end

        @tree_state.select(prev_idx)
        @tree.selected_path = @tree.visible_nodes[prev_idx][:path]
      elsif @tree.respond_to?(:move_selection)
        @tree.move_selection(:up)
      end

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # Again, set the viewport only after refreshing so the view is not
      # pulled back to the selection by ListState.
      if was_page_navigation_active && !retained_page_start.nil?
        set_tree_page_offset(retained_page_start)
        @tree_page_viewport_start = retained_page_start
        @search_page_viewport_start = retained_page_start if defined?(@search_page_viewport_start)
        @tree_viewport_render_lock = retained_page_start
      end

      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      record_selection_change(before_state)

      return true

    when 'M'
      before_state = capture_selection_state
      if current_path
        if @selected_tree_paths.include?(current_path)
          @selected_tree_paths.delete(current_path)
        else
          @selected_tree_paths << current_path
        end
        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

        # Synchronize the data axis immediately.
        sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
        record_selection_change(before_state)

        return true
      end

      # 2. Extend the multi-selection upward with uppercase K.
    when 'K', 'J'
      before_state = capture_selection_state
      visible_nodes = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
      return true if visible_nodes.nil? || visible_nodes.empty?

      target_idx = if key_str == 'K'
                     [selected_idx.to_i - 1, 0].max
                   else
                     [selected_idx.to_i + 1, visible_nodes.length - 1].min
                   end
      target_node = visible_nodes[target_idx]
      target_path = target_node && target_node[:path]

      if has_shift
        apply_tree_range_selection(visible_nodes, target_idx)
      else
        reset_tree_shift_selection
        if target_path
          if @selected_tree_paths.include?(target_path)
            @selected_tree_paths.delete(target_path)
          else
            @selected_tree_paths << target_path
          end
        end
      end

      if target_node
        @tree_state.select(target_idx) if @tree_state
        @tree.selected_path = target_path
      end
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      record_selection_change(before_state)

      return true

    # home & shift+home
    when 'home', 'g'
      before_state = capture_selection_state
      if @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && @tree.visible_nodes.any?
        visible_nodes = @tree.visible_nodes
        start_idx = @tree_state.selected || 0
        target_idx = 0

        is_home_shift = has_shift && %w[home g].include?(key_str)

        if is_home_shift
          update_tree_boundary_selection(visible_nodes, start_idx, target_idx)
        elsif !has_shift
          @selected_tree_paths = []
          reset_tree_shift_selection
        end

        @tree.selected_path = visible_nodes.first[:path]
        @tree_state.select(target_idx) if @tree_state

        @tree_page_viewport_start = 0
        set_tree_page_offset(0) if respond_to?(:set_tree_page_offset, true)
      else
        @tree.selected_path = nil
      end

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      @tree_page_viewport_start = 0
      set_tree_page_offset(0)
      @tree_viewport_render_lock = 0
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      record_selection_change(before_state)

      return true

    # end & shift+end
    when 'end', 'G'
      before_state = capture_selection_state
      if @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && @tree.visible_nodes.any?
        visible_nodes = @tree.visible_nodes
        start_idx = @tree_state.selected || 0
        total_count = visible_nodes.length
        target_idx = total_count - 1

        is_end_shift = has_shift && %w[end G].include?(key_str)

        if is_end_shift
          update_tree_boundary_selection(visible_nodes, start_idx, target_idx)
        elsif !has_shift
          @selected_tree_paths = []
          reset_tree_shift_selection
        end

        @tree.selected_path = visible_nodes.last[:path]
        @tree_state.select(target_idx) if @tree_state

        page_size = [(@tree_visible_height || 1).to_i, 1].max
        max_offset = [total_count - page_size, 0].max

        @tree_page_viewport_start = max_offset
        set_tree_page_offset(max_offset) if respond_to?(:set_tree_page_offset, true)
      else
        @tree.selected_path = nil
      end

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      total_count = @tree.visible_nodes.length
      page_size = [(@tree_visible_height || 1).to_i, 1].max
      max_offset = [total_count - page_size, 0].max

      set_tree_page_offset(max_offset)
      @tree_page_viewport_start = max_offset
      @tree_viewport_render_lock = max_offset
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      record_selection_change(before_state)

      return true

    when 'page_up', 'pageup', 'u', 'page_down', 'pagedown', 'd'
      page_consumed = handle_tree_page_navigation(key, key_str, has_ctrl, has_alt, has_shift)
      return false unless page_consumed

      # Ensure live synchronization after a page jump here as well.
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      return true

      # =========================================================================
      # EXPAND AND COLLAPSE WITH { AND } AND THE LEFT/RIGHT ARROWS (COUPLED FIX)
      # =========================================================================
    when '{', '}'
      return true unless @active_focus == :tree

      force_status = (key == '}')
      if current_node && current_node[:type] != :deck
        @tree.toggle_expand(current_node[:path],
                            force_open: force_status)
      end

      # FIX: Recalculate the indices immediately after the grid height changes.
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      return true

    when 'left', 'right', 'h', 'l'
      return true unless @active_focus == :tree

      key_str = key.to_s.strip.downcase
      is_expand_action = key == :right || %w[right l].include?(key_str)

      return true if has_alt || has_ctrl

      force_status = is_expand_action
      if current_node && current_node[:type] != :deck
        @tree.toggle_expand(current_node[:path],
                            force_open: force_status)
      end

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
      # =====================================================================
      return true

    # =========================================================================
    # COMBINED ENTER GATEWAY: ADD VS RENAME VS TREE MUTATIONS
    # =========================================================================
    when 'enter', 'Enter', "\r", "\n"
      wipe_all_search_artifacts
      sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)

      @last_focus = :tree
      @active_focus = :table

      return true

    when 'R', 'f2'
      wipe_all_search_artifacts

      trigger_rename_popup(key_str, current_node) if current_node && !has_alt
      return true

    # =========================================================================
    # ADD VIA 'A' (WITHOUT ALT MULTIPLEXING)
    # =========================================================================
    when 'a', '+', 'f7'
      wipe_all_search_artifacts

      execute_tree_add(current_node) unless has_alt || has_ctrl
      return true

    when 'backspace', "\x7f", '127', '-', 'f8'
      return true if has_alt || has_ctrl

      return handle_tree_delete_key

      # =========================================================================
      # Clear the table highlights and keep the app open.
      # FIX: SEARCH ESCAPE GUARD FOR THE TABLE (BASED ON REPLACE)
      # =========================================================================
    end

    false
  end

  private

  # Start a new Shift selection from the currently visible row.
  def begin_tree_shift_selection(start_idx)
    @tree_selection_anchor = start_idx.to_i
    @tree_selection_anchor_index = start_idx.to_i
    @tree_shift_selection_active = true
  end

  # Reset only the range-selection state.
  def reset_tree_shift_selection
    @tree_selection_anchor = nil
    @tree_selection_anchor_index = nil
    @tree_shift_selection_active = false
  end

  def update_tree_range_selection(visible_nodes, start_idx, target_idx)
    return if visible_nodes.nil? || visible_nodes.empty?

    last_idx = visible_nodes.length - 1
    start_idx = [[start_idx.to_i, 0].max, last_idx].min
    target_idx = [[target_idx.to_i, 0].max, last_idx].min

    begin_tree_shift_selection(start_idx) unless @tree_shift_selection_active && !@tree_selection_anchor.nil?

    anchor_idx = [[@tree_selection_anchor.to_i, 0].max, last_idx].min

    old_min, old_max = [anchor_idx, start_idx].minmax
    new_min, new_max = [anchor_idx, target_idx].minmax

    @selected_tree_paths ||= []

    (old_min..old_max).each do |idx|
      node = visible_nodes[idx]
      @selected_tree_paths.delete(node[:path]) if node && node[:path]
    end

    (new_min..new_max).each do |idx|
      node = visible_nodes[idx]
      @selected_tree_paths << node[:path] if node && node[:path] && !@selected_tree_paths.include?(node[:path])
    end
  end

  # Select exactly the visible range between the anchor and target.
  def apply_tree_range_selection(visible_nodes, target_idx)
    return if visible_nodes.nil? || visible_nodes.empty?

    target_idx = [[target_idx.to_i, 0].max, visible_nodes.length - 1].min

    unless @tree_shift_selection_active && !@tree_selection_anchor.nil?
      current_idx = @tree_state&.selected || target_idx
      begin_tree_shift_selection(current_idx)
    end

    update_tree_range_selection(visible_nodes, @tree_state&.selected || target_idx, target_idx)
  end

  # Restore the minimum structure: every subject has a source and every
  # source has a deck; create a base structure if the library becomes empty.
  def repair_tree_minimum_structure(subject_class, source_class, deck_class,
                                    lbl_subject, lbl_source, lbl_deck)
    # =====================================================================
    # SELF-HEALING ENGINE (Cross-Platform / Model Safe)
    # =====================================================================
    @library.subjects.each do |sub|
      if sub.sources.nil? || sub.sources.empty?
        # Build a lightweight, fresh object without altering the blueprints.
        new_deck = deck_class.new
        new_deck.name = lbl_deck.to_s.dup # Forceer een schone string-kopie
        new_deck.cards = []

        new_src = source_class.new
        new_src.name = lbl_source.to_s.dup
        new_src.decks = [new_deck]

        sub.sources = [new_src]
      else
        sub.sources.each do |src|
          next unless src.decks.nil? || src.decks.empty?

          new_deck = deck_class.new
          new_deck.name = lbl_deck.to_s.dup
          new_deck.cards = []

          src.decks = [new_deck]
        end
      end
    end

    return unless @library.subjects.empty?

    new_deck = deck_class.new
    new_deck.name = lbl_deck.to_s.dup
    new_deck.cards = []

    new_src = source_class.new
    new_src.name = lbl_source.to_s.dup
    new_src.decks = [new_deck]

    new_sub = subject_class.new
    new_sub.name = lbl_subject.to_s.dup
    new_sub.sources = [new_src]

    @library.subjects << new_sub
  end

  # Perform a bulk or single deletion and, if needed, determine the
  # persistent path to which the cursor should return afterward.
  def delete_selected_tree_objects(visible_nodes_list, active_node, deleted_node_type,
                                   blueprint_deck, deck_class, lbl_deck)
    # Target coordinates for precise cursor-bar restoration.
    target_rescue_path = nil

    # -----------------------------------------------------------------
    # CASE A: MULTI-SELECT BULK DELETION
    # -----------------------------------------------------------------
    if @selected_tree_paths && @selected_tree_paths.any?
      selected_nodes = visible_nodes_list.select do |n|
        @selected_tree_paths.include?(n[:path]) && n[:object]
      end
      selected_object_ids = selected_nodes.map { |n| n[:object].object_id }

      # Delete by object identity, never by display name: equal names may occur
      # in different branches and must not cause unrelated items to disappear.
      selected_nodes.select { |n| n[:type] == :subject }.each do |n|
        @library.subjects.delete_if { |sub| sub.equal?(n[:object]) }
      end

      @library.subjects.each do |sub|
        sub.sources.delete_if { |src| selected_object_ids.include?(src.object_id) }
        sub.sources.each do |src|
          src.decks.delete_if { |deck| selected_object_ids.include?(deck.object_id) }
        end
      end

      # Keep the invariant that every remaining source contains at least one deck.
      @library.subjects.each do |sub|
        sub.sources.each do |src|
          next unless src.decks.empty?

          fallback_deck = blueprint_deck ? blueprint_deck.dup : deck_class.new
          fallback_deck.name = lbl_deck.to_s
          fallback_deck.cards = [] if fallback_deck.respond_to?(:cards=)
          fallback_deck.id = SecureRandom.uuid if fallback_deck.respond_to?(:id=)
          src.decks << fallback_deck
          if target_rescue_path.nil? && sub.respond_to?(:id) && src.respond_to?(:id)
            target_rescue_path = [sub.id.to_s, src.id.to_s, fallback_deck.id.to_s]
          end
        end
      end

    # -----------------------------------------------------------------
    # CASE B: SINGLE DELETION (WITH INTELLIGENT ROW PRECALCULATION)
    # -----------------------------------------------------------------
    elsif active_node && active_node[:object]
      target_id = active_node[:object].object_id

      case deleted_node_type
      when :subject
        @library.subjects.reject! { |s| s.object_id == target_id }

      when :source
        @library.subjects.each do |sub|
          sub.sources.reject! { |src| src.object_id == target_id }
        end

      when :deck
        parent_src = active_node[:parent]
        parent_sub = active_node[:grand_parent]

        if parent_src
          old_deck_idx = parent_src.decks.index { |d| d.object_id == target_id } || 0
          parent_src.decks.reject! { |d| d.object_id == target_id }

          # If we just deleted the LAST deck in this source, add a replacement.
          if parent_src.decks.empty?
            fallback_deck = blueprint_deck ? blueprint_deck.dup : deck_class.new
            fallback_deck.name = lbl_deck
            fallback_deck.cards = []
            fallback_deck.id = SecureRandom.uuid if fallback_deck.respond_to?(:id=)
            parent_src.decks << fallback_deck

            # Construct the direct path to this new fallback deck.
            target_rescue_path = [parent_sub.id.to_s, parent_src.id.to_s, fallback_deck.id.to_s]
          else
            # Other decks remain. Select the deck immediately before the deleted one.
            target_deck_idx = [old_deck_idx - 1, 0].max
            target_deck_idx = [target_deck_idx, parent_src.decks.length - 1].min
            chosen_deck = parent_src.decks[target_deck_idx]

            target_rescue_path = [parent_sub.id.to_s, parent_src.id.to_s, chosen_deck.id.to_s]
          end
        end
      end
    end

    target_rescue_path
  end

  # Handle Backspace/Delete: remove the selection or active node, restore
  # the minimum tree structure, and realign the cursor and indices.
  def handle_tree_delete_key
    lbl_subject = begin
      'Subject'
    rescue StandardError
      'Subject'
    end

    lbl_source = begin
      'Source'
    rescue StandardError
      'Source'
    end

    lbl_deck = begin
      'Deck'
    rescue StandardError
      'Deck'
    end

    blueprint_sub  = @library.subjects.compact.first
    blueprint_src  = @library.subjects.map(&:sources).flatten.compact.first
    blueprint_deck = blueprint_src ? blueprint_src.decks.compact.first : nil

    subject_class = if blueprint_sub
                      blueprint_sub.class
                    else
                      (if defined?(MySubjectClass)
                         MySubjectClass
                       else
                         Struct.new(
                           :name, :sources
                         )
                       end)
                    end
    source_class  = if blueprint_src
                      blueprint_src.class
                    else
                      (if defined?(MySourceClass)
                         MySourceClass
                       else
                         Struct.new(
                           :name, :decks
                         )
                       end)
                    end
    deck_class    = if blueprint_deck
                      blueprint_deck.class
                    else
                      (if defined?(MyDeckClass)
                         MyDeckClass
                       else
                         Struct.new(:name,
                                    :cards)
                       end)
                    end

    # Capture the unique active node and position before deletion.
    current_cursor_row = defined?(@tree_state) && @tree_state ? @tree_state.selected : 0
    visible_nodes_list = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
    active_node = visible_nodes_list[current_cursor_row]
    return true if active_node.nil?

    deleted_node_type = active_node[:type]

    # Ignore stale multi-selection paths: nothing valid can be deleted.
    if @selected_tree_paths && @selected_tree_paths.any?
      valid_selected_nodes = visible_nodes_list.select do |n|
        @selected_tree_paths.include?(n[:path]) && n[:object]
      end

      if valid_selected_nodes.empty?
        @selected_tree_paths = []
        return true
      end
    end

    allow_snapshot! if respond_to?(:allow_snapshot!)
    save_history_snapshot if respond_to?(:save_history_snapshot)

    target_rescue_path = delete_selected_tree_objects(
      visible_nodes_list, active_node, deleted_node_type,
      blueprint_deck, deck_class, lbl_deck
    )

    if deleted_node_type == :deck &&
       target_rescue_path &&
       @undo_stack && !@undo_stack.empty?
      @undo_stack.last[:redo_target] = {
        type: :tree,
        path: target_rescue_path.map(&:to_s)
      }
    end

    repair_tree_minimum_structure(
      subject_class, source_class, deck_class,
      lbl_subject, lbl_source, lbl_deck
    )

    @library_dirty = true

    @selected_tree_paths = []
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    if @tree && @tree.respond_to?(:expanded_paths)
      @tree.expanded_paths ||= []
      @library.subjects.each do |sub|
        sub_path = [sub.id.to_s]
        @tree.expanded_paths << sub_path unless @tree.expanded_paths.include?(sub_path)

        sub.sources.each do |src|
          src_path = [sub.id.to_s, src.id.to_s]
          @tree.expanded_paths << src_path unless @tree.expanded_paths.include?(src_path)
        end
      end
    end

    # Ask Rattree to recalculate the nodes.
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    # =====================================================================
    # ROBUST CURSOR REALIGNMENT MATRIX (CONSISTENT AT EVERY LEVEL)
    # =====================================================================
    nodes_pool = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
    if nodes_pool.any?
      target_idx = [current_cursor_row, nodes_pool.length - 1].min
      target_idx = [target_idx, 0].max

      # A. DECK DELETED (Move the selection to the calculated neighboring deck).
      if deleted_node_type == :deck && target_rescue_path
        @tree.selected_path = target_rescue_path
        matched_row = nodes_pool.index { |n| n[:path] == target_rescue_path }
        target_idx = matched_row if matched_row

      # B. SOURCE OR SUBJECT DELETED (Preserve the level by finding the same tier).
      elsif %i[source subject].include?(deleted_node_type)
        nearest_node = nodes_pool[0..target_idx].reverse.find { |n| n[:type] == deleted_node_type } ||
                       nodes_pool[target_idx..-1].find { |n| n[:type] == deleted_node_type }

        target_idx = nodes_pool.index(nearest_node) || target_idx if nearest_node
        @tree.selected_path = nodes_pool[target_idx][:path]
      else
        @tree.selected_path = nodes_pool[target_idx][:path]
      end

      # Always activate the row index in the TUI state.
      @tree_state.select(target_idx) if defined?(@tree_state) && @tree_state
    end

    # Keep folders open through persistent ID paths if self-healing was triggered.
    @library.subjects.each do |sub|
      next unless @tree.respond_to?(:expanded_paths) && @tree.expanded_paths

      s_p = [sub.id.to_s]
      @tree.expanded_paths << s_p unless @tree.expanded_paths.include?(s_p)
      if sub.sources.any?
        src_p = s_p + [sub.sources.first.id.to_s]
        @tree.expanded_paths << src_p unless @tree.expanded_paths.include?(src_p)
      end
    end

    # =====================================================================
    # STRICT INDEX OVERRIDE (PREVENTS SYNCHRONIZATION LEAKS)
    # =====================================================================
    if nodes_pool.any? && defined?(@tree_state) && @tree_state
      active_row_node = nodes_pool[@tree_state.selected || 0]
      if active_row_node && active_row_node[:type] == :deck
        @library.subjects.each_with_index do |sub, sub_i|
          sub.sources.each_with_index do |src, src_i|
            deck_i = src.decks.index(active_row_node[:object])
            next unless deck_i

            @current_subject_idx = sub_i
            @current_source_idx  = src_i
            @current_deck_idx    = deck_i
            break
          end
        end
      end
    end

    # =====================================================================

    true
  end

  # Update the Shift selection as a continuous range between the anchor and target.
  def update_tree_boundary_selection(visible_nodes, start_idx, target_idx)
    update_tree_range_selection(visible_nodes, start_idx, target_idx)
  end

  # Open all intermediate paths so a deeply nested selected item is visible.
  def force_expand_tree_path(path)
    return unless @tree && @tree.respond_to?(:expanded_paths) && path.is_a?(Array)

    # Walk through the path depth (e.g. ["Languages"], then ["Languages", "Spanish"]).
    (1..path.length).each do |len|
      sub_path = path[0...len]

      if @tree.expanded_paths.is_a?(Set)
        @tree.expanded_paths.add(sub_path)
      elsif @tree.expanded_paths.is_a?(Array)
        @tree.expanded_paths << sub_path unless @tree.expanded_paths.include?(sub_path)
      end
    end

    # Refresh the visual nodes so expanded branches are drawn immediately.
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  # Generate a unique name with an incrementing numeric suffix.
  def generate_unique_name(existing_objects, base_placeholder)
    highest_num = 1
    found_base = false

    # Escape special characters in the regex placeholder.
    escaped_base = Regexp.escape(base_placeholder)

    # The regex looks for a space followed by a number at the end.
    pattern = /\A#{escaped_base}(?:\s+(\d+))?\z/

    existing_objects.each do |obj|
      name_str = obj.name.to_s.strip
      if name_str == base_placeholder
        found_base = true
      elsif name_str =~ pattern
        num = ::Regexp.last_match(1).to_i
        highest_num = num if num > highest_num
      end
    end

    if !found_base
      base_placeholder
    else
      "#{base_placeholder} #{highest_num + 1}"
    end
  end

  # Move the viewport using APIs supported by multiple RatatuiRuby versions.
  # Preserve the absolute selection while changing only the scroll offset.
  def set_tree_page_offset(offset)
    return unless defined?(@tree_state) && @tree_state

    desired = [offset.to_i, 0].max
    current = @tree_state.respond_to?(:offset) ? @tree_state.offset.to_i : 0
    saved_selection = @tree_state.respond_to?(:selected) ? @tree_state.selected : nil

    # ListState in RatatuiRuby is reliably moved with scroll_down_by /
    # scroll_up_by. set_offset/offset= are not available on all supported
    # versions. Preserve the absolute selection while moving the viewport.
    if desired > current && @tree_state.respond_to?(:scroll_down_by)
      @tree_state.scroll_down_by(desired - current)
    elsif desired < current && @tree_state.respond_to?(:scroll_up_by)
      @tree_state.scroll_up_by(current - desired)
    elsif @tree_state.respond_to?(:set_offset)
      @tree_state.set_offset(desired)
    elsif @tree_state.respond_to?(:offset=)
      @tree_state.offset = desired
    end

    @tree_state.select(saved_selection) unless saved_selection.nil?
  end

  # Handle page movement and keep the selection, viewport, and Shift range in sync.
  def handle_tree_page_navigation(key, key_str, has_ctrl, has_alt, has_shift)
    normalized_key = key_str.to_s.strip.sub(/\A:/, '').downcase

    is_page_up =
      (has_ctrl && normalized_key == 'u') ||
      %i[page_up pageup].include?(key) ||
      %w[page_up pageup].include?(normalized_key)

    is_page_down =
      (has_ctrl && normalized_key == 'd') ||
      %i[page_down pagedown].include?(key) ||
      %w[page_down pagedown].include?(normalized_key)

    return false unless is_page_up || is_page_down

    before_state = capture_selection_state
    visible_nodes = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
    return true if visible_nodes.nil? || visible_nodes.empty?

    page_size = [(@tree_visible_height || 1).to_i, 1].max
    total_rows = visible_nodes.length
    visible_rows = [page_size, total_rows].min
    last_index = total_rows - 1

    selected = defined?(@tree_state) && @tree_state && @tree_state.respond_to?(:selected) ? @tree_state.selected : 0
    selected = [[selected.to_i, 0].max, last_index].min

    current_offset = if defined?(@tree_page_viewport_start) && !@tree_page_viewport_start.nil?
                       @tree_page_viewport_start.to_i
                     elsif defined?(@tree_state) && @tree_state && @tree_state.respond_to?(:offset)
                       @tree_state.offset.to_i
                     else
                       0
                     end

    max_offset = [total_rows - visible_rows, 0].max
    current_offset = [[current_offset, 0].max, max_offset].min

    unless selected >= current_offset && selected < current_offset + visible_rows
      current_offset = selected < current_offset ? selected : [selected - visible_rows + 1, max_offset].min
    end

    screen_row = selected - current_offset
    page_starts = (0...max_offset).step(visible_rows).to_a
    page_starts << max_offset unless page_starts.include?(max_offset)

    current_page = page_starts.rindex { |page_start| page_start <= current_offset } || 0

    target_page = is_page_down ? [current_page + 1, page_starts.length - 1].min : [current_page - 1, 0].max
    target_offset = page_starts[target_page]

    if has_shift
      # Select exactly as many nodes as the visible page size.
      # The starting node is included, so the index jump is one smaller.
      selection_step = [visible_rows - 1, 0].max

      target_selected = if is_page_down
                          [selected + selection_step, last_index].min
                        else
                          [selected - selection_step, 0].max
                        end

      # Keep the cursor on the same visible screen row.
      target_offset = [[target_selected - screen_row, 0].max, max_offset].min
    else
      # Preserve the existing normal page navigation.
      if target_page == current_page
        target_selected = is_page_down ? last_index : 0
      else
        target_selected = target_offset + screen_row
        target_selected = [target_selected, target_offset + visible_rows - 1].min
        target_selected = [target_selected, last_index].min
      end
    end

    target_selected = [[target_selected, 0].max, last_index].min

    if has_shift
      update_tree_range_selection(visible_nodes, selected, target_selected)
    else
      @selected_tree_paths = []
      reset_tree_shift_selection
    end

    target_node = visible_nodes[target_selected]
    return true unless target_node

    @tree_state.select(target_selected) if defined?(@tree_state) && @tree_state
    @tree_page_viewport_start = target_offset
    @tree_page_navigation_active = true
    @tree.selected_path = target_node[:path]

    # Refresh the tree first, then restore the viewport offset.
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    set_tree_page_offset(target_offset)
    @tree_page_viewport_start = target_offset
    @search_page_viewport_start = target_offset if defined?(@search_page_viewport_start)
    @tree_viewport_render_lock = target_offset

    record_selection_change(before_state)

    true
  end

  # =========================================================================
  # SUB-HANDLER 1: ADD A TREE ITEM WITH AUTOMATIC TIME TRACKING
  # =========================================================================
  # Add a subject, source, or deck and select the newly created item.
  def execute_tree_add(node)
    wipe_all_search_artifacts

    @previous_valid_tree_path = @tree.selected_path ? @tree.selected_path.dup : nil

    if node.nil? || node[:type] == :subject
      # =========================================================================
      # CASE A: ADD SUBJECT (must be selected; path length is 1).
      # =========================================================================
      base_name = 'Subject'
      unique_sub_name = generate_unique_name(@library.subjects, base_name)

      new_sub = Subject.new(unique_sub_name)
      new_src = Source.new('Source')
      new_deck = Deck.new('Deck')

      allow_snapshot! if respond_to?(:allow_snapshot!)
      save_history_snapshot if respond_to?(:save_history_snapshot)

      new_src.decks << new_deck
      new_sub.sources << new_src
      @library.subjects << new_sub

      # Add the folders to expanded_paths so they appear in visible_nodes.
      if @tree && @tree.respond_to?(:expanded_paths) && @tree.expanded_paths
        sub_id_path = [new_sub.id.to_s]
        src_id_path = [new_sub.id.to_s, new_src.id.to_s]

        @tree.expanded_paths << sub_id_path unless @tree.expanded_paths.include?(sub_id_path)
        @tree.expanded_paths << src_id_path unless @tree.expanded_paths.include?(src_id_path)
      end

      # Generate the new visual nodes through Rattree.
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # BASED DIRECTLY ON RATTREE: the selected path has length 1 (Subject).
      @tree.selected_path = [new_sub.id.to_s]

    elsif node[:type] == :source
      # =========================================================================
      # CASE B: ADD SOURCE (must be selected; path length is 2).
      # =========================================================================
      subject = node[:parent]

      return true if subject.nil?

      base_name = 'Source'
      unique_src_name = generate_unique_name(subject.sources, base_name)
      new_src = Source.new(unique_src_name)

      new_deck = Deck.new('Deck')

      # Always activate history before adding the item.
      allow_snapshot! if respond_to?(:allow_snapshot!)
      save_history_snapshot if respond_to?(:save_history_snapshot)

      new_src.decks << new_deck
      subject.sources << new_src

      if @tree && @tree.respond_to?(:expanded_paths) && @tree.expanded_paths
        parent_id_path = [subject.id.to_s]
        new_src_id_path = [subject.id.to_s, new_src.id.to_s]

        @tree.expanded_paths << parent_id_path unless @tree.expanded_paths.include?(parent_id_path)
        @tree.expanded_paths << new_src_id_path unless @tree.expanded_paths.include?(new_src_id_path)
      end

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # BASED DIRECTLY ON RATTREE: the selected path has length 2 (Source).
      @tree.selected_path = [subject.id.to_s, new_src.id.to_s]

    elsif node[:type] == :deck
      # =========================================================================
      # CASE C: ADD DECK (must be selected; path length is 3).
      # =========================================================================
      source = node[:parent]
      subject = node[:grand_parent]
      base_name = 'Deck'
      unique_deck_name = generate_unique_name(source.decks, base_name)

      new_deck = Deck.new(unique_deck_name)

      allow_snapshot! if respond_to?(:allow_snapshot!)
      save_history_snapshot if respond_to?(:save_history_snapshot)

      source.decks << new_deck

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # BASED DIRECTLY ON RATTREE: the selected path has length 3 (Deck).
      @tree.selected_path = [subject.id.to_s, source.id.to_s, new_deck.id.to_s]
    end

    # =========================================================================
    # FULL COORDINATE SYNC (ALWAYS AFTER ADDING AN ITEM)
    # =========================================================================
    sort_library_tree_layers! if respond_to?(:sort_library_tree_layers!)

    @library_dirty = true

    # Refresh the nodes after sorting so the displayed order is correct.
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    # CURSOR + VIEWPORT SYNC
    if @tree.respond_to?(:visible_nodes) &&
       @tree.visible_nodes &&
       defined?(@tree_state) &&
       @tree_state

      new_row_idx = @tree.visible_nodes.index do |n|
        n[:path] == @tree.selected_path
      end

      if new_row_idx
        @tree_state.select(new_row_idx)

        visible_height = [(@tree_visible_height || 1).to_i, 1].max
        current_offset = (@tree_page_viewport_start || 0).to_i

        # Scroll only when the new selection is outside the visible area.
        if new_row_idx < current_offset
          current_offset = new_row_idx
        elsif new_row_idx >= current_offset + visible_height
          current_offset = new_row_idx - visible_height + 1
        end

        max_offset = [
          @tree.visible_nodes.length - visible_height,
          0
        ].max

        current_offset = [[current_offset, 0].max, max_offset].min

        @tree_page_viewport_start = current_offset

        set_tree_page_offset(current_offset) if respond_to?(:set_tree_page_offset)
      end
    end

    # Synchronize the library pointers and refresh the data table immediately.
    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
  end

  # =========================================================================
  # SUB-HANDLER 2: DELETE A TREE ITEM WITH RELIABLE STACK UNDO
  # =========================================================================
  # Delete a tree item, restore an empty deck if needed, and realign the selection.
  def execute_tree_delete(node)
    return true if node.nil?

    object = node[:object]

    valid_node = case node[:type]
                 when :subject
                   object && @library.subjects.any? { |s| s.equal?(object) }
                 when :source
                   parent = node[:parent]
                   parent &&
                   @library.subjects.any? { |s| s.equal?(parent) } &&
                   parent.sources.any? { |s| s.equal?(object) }
                 when :deck
                   parent = node[:parent]
                   grand_parent = node[:grand_parent]
                   grand_parent &&
                   @library.subjects.any? { |s| s.equal?(grand_parent) } &&
                   grand_parent.sources.any? { |s| s.equal?(parent) } &&
                   parent.decks.any? { |d| d.equal?(object) }
                 else
                   false
                 end

    return true unless valid_node

    wipe_all_search_artifacts

    # 1. Store the parameters and exact visual row before deletion.
    saved_cursor_row = defined?(@tree_state) && @tree_state ? @tree_state.selected : 0
    deleted_node_type = node[:type]

    allow_snapshot! if respond_to?(:allow_snapshot!)
    save_history_snapshot if respond_to?(:save_history_snapshot)

    forced_new_deck_path = nil

    # -----------------------------------------------------------------
    # 2. CORE DELETION LOGIC
    # -----------------------------------------------------------------
    case deleted_node_type
    when :subject
      subject = node[:object]
      @library.subjects.delete(subject) if subject

    when :source
      source = node[:object]
      parent_sub = node[:parent]
      parent_sub.sources.delete(source) if parent_sub && source

    when :deck
      deck = node[:object]
      parent_src = node[:parent]
      parent_sub = node[:grand_parent]

      if parent_src && deck
        old_deck_idx = parent_src.decks.index(deck) || 0
        parent_src.decks.delete(deck)

        # =========================================================================
        # CRITICAL CASE: THE LAST DECK IN THIS SOURCE WAS DELETED.
        # =========================================================================
        if parent_src.decks.empty?
          # Create the new fallback deck immediately.
          fallback_deck = Deck.new('Deck')
          parent_src.decks << fallback_deck

          # Construct the exact new object_id path immediately.
          forced_new_deck_path = [
            parent_sub.id.to_s,
            parent_src.id.to_s,
            fallback_deck.id.to_s
          ]

          # EXTRA GUARANTEE: Keep the folders open for this ID in the expander matrix.
          if @tree && @tree.respond_to?(:expanded_paths)
            @tree.expanded_paths ||= []
            sub_p = [parent_sub.id.to_s]
            src_p = [parent_sub.id.to_s, parent_src.id.to_s]

            @tree.expanded_paths << sub_p unless @tree.expanded_paths.include?(sub_p)
            @tree.expanded_paths << src_p unless @tree.expanded_paths.include?(src_p)
          end
        else
          # CASE B: Other decks remain. Select the deck immediately before the deleted one.
          target_deck_idx = [old_deck_idx - 1, 0].max
          target_deck_idx = [target_deck_idx, parent_src.decks.length - 1].min
          chosen_deck = parent_src.decks[target_deck_idx]

          forced_new_deck_path = [
            parent_sub.id.to_s,
            parent_src.id.to_s,
            chosen_deck.id.to_s
          ]
        end
      end
    end

    # Save the library and recalculate the view rows in the model immediately.
    @library_dirty = true

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    # =========================================================================
    # 3. FORCED VISUAL ROW POSITIONING (DECK LOCK AND LEVEL PRESERVATION)
    # =========================================================================
    if @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && @tree.visible_nodes.any?
      nodes_pool = @tree.visible_nodes

      target_idx = [saved_cursor_row, nodes_pool.length - 1].min
      target_idx = [target_idx, 0].max

      # A. DECK DELETED (Move the cursor directly to the calculated or new deck).
      if deleted_node_type == :deck && forced_new_deck_path
        @tree.selected_path = forced_new_deck_path
        matched_row = nodes_pool.index { |n| n[:path] == forced_new_deck_path }

        # If the index is not found directly, locate the first :deck row in this source.
        matched_row ||= nodes_pool.index { |n| n[:type] == :deck && n[:path][0..1] == forced_new_deck_path[0..1] }

        @tree_state.select(matched_row || target_idx)

      # B. SOURCE DELETED (Preserve the level by finding the nearest Source row).
      elsif deleted_node_type == :source
        nearest_source = nodes_pool[0..target_idx].reverse.find { |n| n[:type] == :source } ||
                         nodes_pool[target_idx..-1].find { |n| n[:type] == :source }

        if nearest_source
          @tree.selected_path = nearest_source[:path]
          @tree_state.select(nodes_pool.index(nearest_source) || target_idx)
        else
          @tree.selected_path = nodes_pool[target_idx][:path]
          @tree_state.select(target_idx)
        end

      # C. SUBJECT DELETED (Preserve the level by finding the nearest Subject row).
      elsif deleted_node_type == :subject
        nearest_subject = nodes_pool[0..target_idx].reverse.find { |n| n[:subject] || n[:type] == :subject } ||
                          nodes_pool[target_idx..-1].find { |n| n[:type] == :subject }

        if nearest_subject
          @tree.selected_path = nearest_subject[:path]
          @tree_state.select(nodes_pool.index(nearest_subject) || target_idx)
        else
          @tree.selected_path = nodes_pool[target_idx][:path]
          @tree_state.select(target_idx)
        end
      end
    else
      @tree.selected_path = nil
      @tree_state.select(0) if defined?(@tree_state) && @tree_state
    end
    # =========================================================================

    # 4. EXPLICIT DATABASE INDEX OVERRIDE AFTER SELECTION
    if @tree.selected_path && defined?(nodes_pool) && nodes_pool
      active_node = nodes_pool[@tree_state.selected || 0]
      if active_node
        if active_node[:type] == :deck
          @library.subjects.each_with_index do |sub, sub_i|
            sub.sources.each_with_index do |src, src_i|
              deck_i = src.decks.index(active_node[:object])
              next unless deck_i

              @current_subject_idx = sub_i
              @current_source_idx  = src_i
              @current_deck_idx    = deck_i
              break
            end
          end
        elsif active_node[:type] == :source
          @library.subjects.each_with_index do |sub, sub_i|
            src_i = sub.sources.index(active_node[:object])
            next unless src_i

            @current_subject_idx = sub_i
            @current_source_idx  = src_i
            @current_deck_idx    = 0
            break
          end
        elsif active_node[:type] == :subject
          sub_i = @library.subjects.index(active_node[:object])
          if sub_i
            @current_subject_idx = sub_i
            @current_source_idx  = 0
            @current_deck_idx    = 0
          end
        end
      end
    elsif respond_to?(:sync_indices_from_tree_path)
      sync_indices_from_tree_path
    end

    # Refresh the data table so it loads the selected deck's cards.
    true
  end

  # =========================================================================
  # SUB-HANDLER 3: INTERACTIVE RATINFIELD POPUP FOR RENAMING A TREE ITEM
  # =========================================================================
  # Open the rename form and, after confirmation, preserve the model, history, and tree selection.
  def trigger_rename_popup(key_str, node)
    if key_str
      key_str = key_str.to_s.strip
      lang = begin
        AppConfig.settings.language.to_sym
      rescue StandardError
        :en
      end

      # Universele basistoetsen die ALTIJD geldig zijn ongeacht de taal
      is_universal_rename_key = %w[R f2].include?(key_str)

      is_allowed = if lang == :nl
                     is_universal_rename_key
                   else # Standaard fallback is Engels (:en)
                     is_universal_rename_key
                   end

      # Sla de popup-activatie direct over als de toets niet bij de taal hoort!
      return false unless is_allowed
    end

    wipe_all_search_artifacts

    return unless node && node[:object]

    @selected_tree_paths = []
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    @previous_valid_tree_path = node[:path] ? node[:path].dup : nil

    active_object = node[:object]
    old_path = node[:path] ? node[:path].dup : nil

    placeholder_text = case node[:type]
                       when :subject
                         begin
                           'Subject'
                         rescue StandardError
                           AppConfig.settings.language_string(:error)
                         end
                       when :source
                         begin
                           'Source'
                         rescue StandardError
                           AppConfig.settings.language_string(:error)
                         end
                       when :deck
                         begin
                           'Deck'
                         rescue StandardError
                           AppConfig.settings.language_string(:error)
                         end
                       else
                         AppConfig.settings.language_string(:error)
                       end

    # Bouw het invoerveld correct op met de huidige naam van het object
    name_field = RatinField.new(placeholder: placeholder_text)
    name_field.text = active_object.name.to_s.dup
    name_field.cursor_index = name_field.text.length

    # Bewaar de huidige focus (:tree) voor de brandmuur
    @last_focus = :tree

    @popup.show(
      type: :form,
      title: " #{AppConfig.settings.language_string(:tree_title_rename)} ",
      fields: { name: name_field }
    ) do |form_data|
      settings = AppConfig.settings
      # Extract en strip de nieuw ingevoerde naam uit het popup-veld
      new_name = form_data[:name].respond_to?(:text) ? form_data[:name].text.to_s.strip : form_data[:name].to_s.strip

      if new_name.empty?
        if respond_to?(:trigger_statusbar_message, true)
          trigger_statusbar_message(
            "#{settings.language_string(:statusbar_form_error)}: #{settings.language_string(:statusbar_name_required)}!",
            type: :error,
            beep: settings.beeps
          )
        end
        next false
      end

      next true if new_name == active_object.name.to_s

      allow_snapshot! if respond_to?(:allow_snapshot!)
      # The rename callback runs while the form popup owns focus. Capture the
      # tree target explicitly; otherwise history inspects :popup focus and can
      # fall back to the table selection instead of the renamed source/deck.
      if respond_to?(:save_history_snapshot)
        rename_history_target = old_path && { type: :tree, path: old_path.map(&:to_s) }
        save_history_snapshot(target: rename_history_target)
      end

      # =========================================================================
      # REPARATIE: OUDE DYNAMISCHE STRIP- EN VERVANG-AS VOLLEDIG WEGGEBROKEN!
      # Omdat expanded_paths nu op basis van UNIEKE persistente id-paden werkt, blijft de ID
      # van dit object exact hetzelfde na een rename. We hoeven de array dus NIET
      # te muteren, waardoor de map gegarandeerd wagenwijd OPEN blijft staan!
      # =========================================================================

      # Wijzig nu pas de daadwerkelijke naam in het library-object
      active_object.name = new_name

      sort_library_tree_layers! if respond_to?(:sort_library_tree_layers!)

      @library_dirty = true

      # Herlaad de nodes van de boomstructuur
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      # =========================================================================
      # REPARATIE: BEHOUD DE EXACTE RECHTSTREEKSE REGEL SELECTIE
      # Het unieke object_id pad (old_path) blijft ongewijzigd, dus we dwingen
      # de selectie direct terug op exact hetzelfde ID-pad!
      # =========================================================================
      if old_path
        @tree.selected_path = old_path

        if @tree.respond_to?(:visible_nodes) && @tree.visible_nodes && defined?(@tree_state) && @tree_state
          matched_row = @tree.visible_nodes.index { |n| n[:path] == old_path }
          @tree_state.select(matched_row) if matched_row
        end
      end

      @active_focus = :tree
      @last_focus   = :tree

      # Herbereken de library pointers direct vanaf de actieve regel ter voorkoming van || 0 resets
      if defined?(@tree_state) && @tree_state && @tree.respond_to?(:visible_nodes)
        active_row_node = @tree.visible_nodes[@tree_state.selected || 0]
        if active_row_node && active_row_node[:type] == :deck
          @library.subjects.each_with_index do |sub, sub_i|
            sub.sources.each_with_index do |src, src_i|
              deck_i = src.decks.index(active_row_node[:object])
              next unless deck_i

              @current_subject_idx = sub_i
              @current_source_idx  = src_i
              @current_deck_idx    = deck_i
              break
            end
          end
        elsif respond_to?(:sync_indices_from_tree_path)
          sync_indices_from_tree_path
        end
      elsif respond_to?(:sync_indices_from_tree_path)
        sync_indices_from_tree_path
      end

      true # Vertel de manager dat alles is goedgekeurd!
    end

    # Activeer de popup focus-poort
    mark_popup_for_input_indicators
    @active_focus = :popup
    true
  end
end
