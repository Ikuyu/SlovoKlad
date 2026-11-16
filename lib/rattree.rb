class RatTree
  attr_accessor :selected_path, :expanded_paths

  def initialize(library)
    @library = library
    @selected_path = nil
    @expanded_paths = []
    @visible_nodes_cache = nil

    # =========================================================================
    # FIX: FORCEER DIRECT VOLLEDIG UITGEKLAPTE STARTSTATUS VIA OBJECT_ID'S
    # =========================================================================
    @library.subjects.each do |subject|
      sub_path = [subject.id.to_s]
      @expanded_paths << sub_path unless @expanded_paths.include?(sub_path)

      subject.sources.each do |source|
        src_path = sub_path + [source.id.to_s]
        @expanded_paths << src_path unless @expanded_paths.include?(src_path)
      end
    end

    select_first_valid_node
  end

  # Rebuild the visible-node cache after a structural tree change.
  # Selection changes do not require a rebuild.
  def refresh_nodes
    @visible_nodes_cache = nil
    true
  end

  def expanded?(path)
    @expanded_paths.include?(path)
  end

  def toggle_expand(path, force_open: nil)
    return unless path.is_a?(Array) && !path.empty?

    should_open = force_open.nil? ? !@expanded_paths.include?(path) : force_open

    if should_open
      # Expanding a node must only expand that node. Descendants keep their
      # previous state. This is important for history/replace: opening one
      # branch must never fan out the entire subtree.
      @expanded_paths << path unless @expanded_paths.include?(path)
      refresh_nodes
    else
      # Closing a container only hides its descendants. Keep their expansion
      # flags intact so reopening the parent restores the exact previous tree
      # state (e.g. an expanded source remains expanded after its subject is
      # collapsed and reopened).
      @expanded_paths.delete(path)
      refresh_nodes
    end
  end

  # Return the complete tree hierarchy, including collapsed descendants.
  # Search uses this list so matches hidden by collapsed parents are not lost.
  def all_nodes
    nodes = []
    return nodes if @library.nil? || @library.subjects.nil?

    @library.subjects.each do |subject|
      sub_path = [subject.id.to_s]
      nodes << { type: :subject, name: subject.name, path: sub_path, depth: 0, object: subject }

      subject.sources.each do |source|
        src_path = sub_path + [source.id.to_s]
        nodes << { type: :source, name: source.name, path: src_path, depth: 1, object: source, parent: subject }

        source.decks.each do |deck|
          deck_path = src_path + [deck.id.to_s]
          nodes << { type: :deck, name: deck.name, path: deck_path, depth: 2, object: deck, parent: source,
                     grand_parent: subject }
        end
      end
    end
    nodes
  end

  def expand_ancestors(path)
    return unless path.is_a?(Array) && path.length > 1

    (1...path.length).each do |depth|
      ancestor = path[0...depth]
      @expanded_paths << ancestor unless @expanded_paths.include?(ancestor)
    end
    refresh_nodes
  end

  def visible_nodes
    return @visible_nodes_cache if @visible_nodes_cache

    nodes = []
    return nodes if @library.nil? || @library.subjects.nil?

    @library.subjects.each do |subject|
      sub_path = [subject.id.to_s]
      nodes << { type: :subject, name: subject.name, path: sub_path, depth: 0, object: subject }

      next unless @expanded_paths.include?(sub_path)

      subject.sources.each do |source|
        src_path = sub_path + [source.id.to_s]
        nodes << { type: :source, name: source.name, path: src_path, depth: 1, object: source, parent: subject }

        next unless @expanded_paths.include?(src_path)

        source.decks.each do |deck|
          deck_path = src_path + [deck.id.to_s]
          nodes << { type: :deck, name: deck.name, path: deck_path, depth: 2, object: deck, parent: source,
                     grand_parent: subject }
        end
      end
    end
    @visible_nodes_cache = nodes
  end

  def select_first_valid_node
    nodes = visible_nodes
    @selected_path = nodes.any? ? nodes.first[:path] : nil
  end

  def move_selection(direction)
    nodes = visible_nodes
    return if nodes.empty?

    current_idx = nodes.index { |n| n[:path] == @selected_path } || 0
    new_idx = direction == :down ? current_idx + 1 : current_idx - 1

    return unless new_idx >= 0 && new_idx < nodes.size

    @selected_path = nodes[new_idx][:path]
  end
end
