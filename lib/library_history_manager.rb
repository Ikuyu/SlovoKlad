module LibraryHistoryManager
  def init_history
    @undo_stack = []
    @redo_stack = []
    @allow_next_snapshot = false
    @history_action_stack = []
    @history_redo_action_stack = []
  end

  def record_history_action(type)
    @history_action_stack ||= []
    @history_redo_action_stack ||= []

    @history_action_stack << type
    @history_redo_action_stack.clear

    @redo_stack.clear if @redo_stack
  end

  def allow_snapshot!
    @allow_next_snapshot = true
  end

  def save_history_snapshot(target: nil)
    return unless @library
    return unless @allow_next_snapshot

    @undo_stack << build_history_entry(target || current_history_target)
    record_history_action(:data)
    @allow_next_snapshot = false
  end

  # =========================================================================
  # TRANSACTIONEEL HISTORY BEHEER
  # =========================================================================
  def save_global_transaction_snapshot(target = nil)
    return unless @library && @undo_stack

    @undo_stack << {
      type: :global_replace_transaction,
      snapshot: library_snapshot,
      target: target || { type: :global_replace }
    }

    record_history_action(:data)
    @allow_next_snapshot = false
  end

  def execute_undo
    return false if @undo_stack.nil? || @undo_stack.empty?

    entry = @undo_stack.pop
    target = entry[:target]

    @allow_next_snapshot = false

    # 🎯 TRANSACTIE BRANDMUUR:
    # Als de entry een global replace transactie is, herstellen we de complete database
    if entry[:type] == :global_replace_transaction
      # Save the CURRENT state to the redo stack before rolling back.
      @redo_stack << { type: :global_replace_transaction, snapshot: library_snapshot, target: target }
      restore_snapshot(entry[:snapshot])
    else
      # Reguliere single-deck undo flow
      save_snapshot_to_stack(@redo_stack, entry[:redo_target] || target)
      @redo_stack.last[:undo_target] = target if @redo_stack.any?
      restore_snapshot(entry[:snapshot])
      realign_after_history(target)
    end

    true
  end

  def execute_redo
    return false if @redo_stack.nil? || @redo_stack.empty?

    entry = @redo_stack.pop
    target = entry[:target]

    @allow_next_snapshot = false

    # 🎯 TRANSACTIE BRANDMUUR:
    if entry[:type] == :global_replace_transaction
      @undo_stack << { type: :global_replace_transaction, snapshot: library_snapshot, target: target }
      restore_snapshot(entry[:snapshot])
    else
      # Reguliere single-deck redo flow
      save_snapshot_to_stack(@undo_stack, entry[:undo_target] || target)
      @undo_stack.last[:redo_target] = target if @undo_stack.any?
      restore_snapshot(entry[:snapshot])
      realign_after_history(target)
    end

    true
  end

  private

  def build_history_entry(target = current_history_target)
    {
      snapshot: library_snapshot,
      target: target
    }
  end

  def current_history_target
    if @active_focus == :tree || (@active_focus == :replace_mode && @tree_search_matches && @tree_search_matches.any?)
      path = @tree&.selected_path
      return { type: :tree, path: path.map(&:to_s) } if path && !path.empty?
    end

    # TableState stores a row number. Convert that row to the card's persistent id.
    if @table_state
      row = @table_state.respond_to?(:selected) ? @table_state.selected : nil
      s = @library.subjects[@current_subject_idx || 0]
      src = s&.sources&.[](@current_source_idx || 0)
      deck = src&.decks&.[](@current_deck_idx || 0)
      card = deck&.cards&.[](row) if row.is_a?(Integer)
      return { type: :card, id: card.id.to_s } if card
    end

    nil
  end

  def library_snapshot
    @library.subjects.map do |sub|
      {
        id: sub.id,
        name: sub.name,
        sources: sub.sources.map do |source|
          {
            id: source.id,
            name: source.name,
            decks: source.decks.map do |deck|
              {
                id: deck.id,
                name: deck.name,
                cards: deck.cards.map do |card|
                  {
                    id: card.id,
                    study: card.study,
                    term: card.term,
                    context: card.context,
                    meaning: card.meaning,
                    interval: card.interval,
                    next_review_at: card.next_review_at
                  }
                end
              }
            end
          }
        end
      }
    end
  end

  # Restore data while preserving the user's existing tree expansion state.
  # Only ancestors needed to reveal the history target are added afterwards.
  def realign_after_history(target)
    return unless @tree

    old_expanded = Array(@tree.expanded_paths).map { |path| Array(path).map(&:to_s) }
    valid_paths = valid_tree_paths
    preserved = old_expanded.select { |path| valid_paths.include?(path) }

    target_path = target_path_in_current_library(target)
    if target_path
      # The history target itself must be visible and, when it is a container,
      # open. This is intentional: after undo/redo the user should be taken to
      # the exact item and see the same branch that contains the changed item.
      # Only this target branch is opened; unrelated branches retain their state.
      target_path.each_index do |idx|
        # A subject/source is a container and must be opened when it is the
        # history target. A deck is a leaf, so only its parents are opened.
        next if idx == target_path.length - 1 && target_path.length == 3

        branch_path = target_path[0..idx]
        preserved << branch_path unless preserved.include?(branch_path)
      end
    end

    @tree.expanded_paths = preserved
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    if target && target[:type] == :tree
      visible_tree_nodes = @tree.respond_to?(:visible_nodes) ? @tree.visible_nodes : []
      apply_tree_history_target(visible_tree_nodes, target_path)
    elsif target && target[:type] == :card
      apply_card_history_target(target[:id])
    end

    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)

    # The final tree refresh/synchronisation can rebuild the visible-node list.
    # Re-apply the history target once more so the Ratatui ListState and the
    # tree's selected_path cannot drift apart after undo/redo.
    if target && target[:type] == :tree
      final_target_path = target_path_in_current_library(target)
      apply_tree_history_target(final_target_path) if final_target_path
    elsif target && target[:type] == :card
      apply_card_history_target(target[:id])
    end
  end

  def valid_tree_paths
    paths = []
    @library.subjects.each do |sub|
      sp = [sub.id.to_s]
      paths << sp
      sub.sources.each do |src|
        rp = sp + [src.id.to_s]
        paths << rp
        src.decks.each do |deck|
          paths << rp + [deck.id.to_s]
        end
      end
    end
    paths
  end

  def target_path_in_current_library(target)
    return nil unless target && target[:type] == :tree

    path = Array(target[:path]).map(&:to_s)
    valid = valid_tree_paths
    return path if valid.include?(path)

    # Resolve the target by its persistent id hierarchy when a snapshot has
    # recreated the Ruby objects. This deliberately does not use object_id or
    # the current screen row.
    if path.length >= 1
      subject = @library.subjects.find { |s| s.id.to_s == path[0] }
      if subject
        resolved = [subject.id.to_s]
        if path.length >= 2
          source = subject.sources.find { |src| src.id.to_s == path[1] }
          if source
            resolved << source.id.to_s
            if path.length >= 3
              deck = source.decks.find { |d| d.id.to_s == path[2] }
              resolved << deck.id.to_s if deck
            end
          end
        end
        return resolved if valid.include?(resolved)
        return resolved[0...-1] if resolved.length > 1 && valid.include?(resolved[0...-1])
        return resolved if valid.include?(resolved)
      end
    end

    # If an added item was undone, its exact path no longer exists. Select the
    # nearest surviving ancestor instead of opening unrelated branches.
    while path.length > 1
      path = path[0...-1]
      return path if valid.include?(path)
    end
    valid.include?(path) ? path : nil
  end

  def apply_tree_history_target(nodes = nil, target_path)
    return unless nodes && nodes.any?

    safe_path = Array(target_path).map(&:to_s)
    return if safe_path.empty?

    target_idx = nodes.index { |node| node[:path] == safe_path }

    # Use a geometric fallback index mapping if the folder has since been renamed or moved.
    target_idx ||= nodes.index do |node|
      node_path_arr = Array(node[:path]).map(&:to_s)
      node_path_arr.first(safe_path.length) == safe_path
    end

    return unless target_idx && @tree_state

    @tree_state.select(target_idx)
    @tree.selected_path = nodes[target_idx][:path] if @tree
  end

  def apply_card_history_target(card_id)
    return unless @table_state

    s = @library.subjects[@current_subject_idx || 0]
    src = s&.sources&.[](@current_source_idx || 0)
    deck = src&.decks&.[](@current_deck_idx || 0)
    return unless deck

    row = deck.cards.index { |card| card.id.to_s == card_id.to_s }
    @table_state.select(row) unless row.nil?
  end

  def save_snapshot_to_stack(stack, target = current_history_target)
    entry = build_history_entry(target)
    return if stack.any? && stack.last[:snapshot] == entry[:snapshot]

    stack << entry
  end

  def restore_snapshot(snapshot_data)
    @library.subjects = []

    snapshot_data.each do |sub_hash|
      subject = Subject.new(sub_hash[:name] || '')
      subject.id = sub_hash[:id] || subject.id
      subject.sources = []

      (sub_hash[:sources] || []).each do |source_hash|
        source = Source.new(source_hash[:name] || '')
        source.id = source_hash[:id] || source.id
        source.decks = []

        (source_hash[:decks] || []).each do |deck_hash|
          deck = Deck.new(deck_hash[:name] || '')
          deck.id = deck_hash[:id] || deck.id
          deck.cards = []

          (deck_hash[:cards] || []).each do |card_hash|
            card = Card.new(card_hash[:term] || '', card_hash[:context] || '', card_hash[:meaning] || '')
            card.id = card_hash[:id] || card.id
            card.study = card_hash[:study]
            card.study = card_hash[:memorised] if card_hash.key?(:memorised)
            card.interval = card_hash[:interval] if card_hash.key?(:interval)
            card.next_review_at = card_hash[:next_review_at] if card_hash.key?(:next_review_at)
            deck.cards << card
          end
          source.decks << deck
        end
        subject.sources << source
      end
      @library.subjects << subject
    end

    @search_matches = nil
  end
end
