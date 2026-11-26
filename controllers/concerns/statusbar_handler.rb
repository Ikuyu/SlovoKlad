require 'rbconfig'
require 'cgi'
require 'tmpdir'

module StatusbarInputHandler
  def execute_statusbar_command(command_string)
    return false if command_string.to_s.strip.empty?

    settings = AppConfig.settings

    if (defined?(@last_warned_file) && !@last_warned_file.nil?) ||
       (defined?(@awaiting_import_confirmation) && !@awaiting_import_confirmation.nil?) ||
       (defined?(@awaiting_export_format_selection) && !@awaiting_export_format_selection.nil?) ||
       (defined?(@awaiting_export_header_selection) && !@awaiting_export_header_selection.nil?) ||
       (defined?(@awaiting_duplicate_scope) && !@awaiting_duplicate_scope.nil?) ||
       (defined?(@awaiting_bulk_reset_confirm) && !@awaiting_bulk_reset_confirm.nil?) ||
       (defined?(@awaiting_duplicate_confirm) && !@awaiting_duplicate_confirm.nil?)
      return handle_yes_no(command_string)
    end

    # =========================================================================
    # 📑 STANDARD COMMAND MATRIX (for other commands such as :w, :q, :import)
    # =========================================================================
    raw_cmd = command_string.to_s.strip.sub(/\A:/, '')
    cmd_parts = raw_cmd.split(/\s+/)
    action = cmd_parts.first.to_s.downcase
    argument = cmd_parts[1..].join(' ').strip

    case action
    when 'an', 'add-nodes'
      add_tree_node_via_command
    when 'rn', 'rename-node'
      rename_tree_node_via_command
    when 'dn', 'delete-nodes'
      delete_tree_nodes_via_command
    when 'ac', 'add-card'
      add_table_card_via_command
    when 'ec', 'edit-card'
      edit_table_card_via_command
    when 'dc', 'delete-cards'
      delete_table_cards_via_command
    when 'se', 'sea', 'search'
      search_via_command
    when 'i', 'im', 'import'
      file_import_via_command(argument)
    when 'drl', 'qz', 'mc', 'pm', 'tk', 'duo', 'drill', 'quiz', 'play-memory', 'multiple-choice', 'toak', 'two-of-two_of_a_kind'
      return study_via_command(action)
    when 'exp', 'export'
      # Capture whatever the user typed. If left blank, it maps as an empty string.
      @pending_zip_custom_name = argument.to_s.strip

      # Activate the layered single-character choice prompt at app.rb's entry point.
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_choose_format)}: #{settings.language_string(:statusbar_format)}?", type: :warning, beep: settings.beeps,
                                                                                                                                            expires: false)
      end

      @awaiting_export_format_selection = { bulk_zip_routing: true }
      @active_focus = :command_mode
      return false
    when 'lct', 'load-custom-theme', 'loadtheme', 'load-theme'
      theme_name = cmd_parts[1].to_s.strip.downcase
      load_custom_theme_via_command(theme_name)
    when 'n', 'ne', 'new', 'n!', 'ne!', 'new!', 'nl'
      has_bang_override = action.end_with?('!') || raw_cmd.end_with?('!')
      new_library_via_command(has_bang_override)
    when 'o', 'op', 'open', 'lo', 'load'
      file_open_via_command(argument)
    when 'rs', 'res', 'reset', 'res!', 'reset!'
      has_bang_override = action.end_with?('!') || raw_cmd.end_with?('!')
      perform_reset(has_bang_override)
    when 'd', 'd!', 'de', 'de!', 'ded', 'ded!', 'dedup', 'dedup!'
      has_bang_override = action.end_with?('!') || raw_cmd.end_with?('!')
      perform_dedup(has_bang_override)
    when 'rp', 'rep', 'replace'
      replace_via_command
    when 'beep', 'beeps', 'be', 'bee'
      toggle_beeps_via_command
    when 'rotation-indicator', 'ri'
      toggle_rotation_indicator_via_command
    when 'markers', 'ms', 'mas'
      show_markers_via_command
    when 'marker', 'm', 'ma'
      set_marker_via_command(argument)
    when 'corners', 'cs', 'cos'
      show_corners_via_command
    when 'corner', 'c', 'co'
      set_corner_via_command(argument)
    when 'langs', 'ls', 'las'
      show_languages_via_command
    when 'lang', 'language', 'l', 'la'
      set_lang_via_command(argument)
    when 'themes', 'thms', 'ts', 'ths'
      show_themes_via_command
    when 'theme', 'them', 't', 'th'
      set_theme_via_command(argument)
    when '?', 'help', 'h', 'he', 'hlp'
      show_help
    when 'w', 'wr', 'write', 'wrt'
      file_write_via_command(argument, cmd_parts, false)
    when 's', 'sa', 'saveas'
      success = file_save_as(argument)

      if success
        # 🟢 SUCCESS: Everything has been saved persistently. Clear the status bar immediately.
        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)

        @command_mode_visible = false if defined?(@command_mode_visible)

        target_panel = defined?(@last_focus) && @last_focus && @last_focus != :popup ? @last_focus : :tree
        target_panel = :tree if target_panel == :command_mode

        @active_focus = target_panel
        @last_focus   = target_panel
        @menu_origin_focus = nil # Reset de kaper-pointer direct!
        @library_dirty = false

        if respond_to?(:trigger_statusbar_message, true)
          saved_filename = settings.last_opened_filename
          bytes_written = begin
            File.size(saved_filename)
          rescue StandardError
            0
          end
          lines_written = File.exist?(saved_filename) ? File.read(saved_filename).count("\n") : 0
          file_name = File.basename(saved_filename.to_s)
          # Display the clean confirmation.
          trigger_statusbar_message("#{settings.language_string(:statusbar_saved)}: \"#{file_name}\" [New] #{lines_written}L, #{bytes_written}B!", type: :info) #
        end
        return true
      else
        # If the method returned false (e.g. an empty argument), keep the bar open.
        @active_focus = :command_mode
        return false
      end
    when 'p', 'pr', 'print'
      print_via_command
    when 'pwd'
      pwd_via_command
    when 'q!', 'qu!', 'quit!', 'ex!', 'exit!', 'x!', 'qt!'
      @quit_requested = true
    when 'q', 'qu', 'quit', 'ex', 'exit', 'x', 'qt'
      quit_via_command
    when 'wq', 'sq', 'wrq', 'saq'
      file_write_via_command(argument, cmd_parts, true)
    else
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_unknown_command)}: #{action}!",
          type: :warning,
          beep: settings.beeps
        )
      end

      restore_command_mode_focus
      return false
    end
    if @active_focus != :command_mode && defined?(@statusbar_field) &&
       @statusbar_field &&
       @statusbar_field.respond_to?(:cursor_index=)
      @statusbar_field.cursor_index = 0
    end

    @active_focus != :command_mode || @quit_requested == true
  end

  private

  def generate_print_file(cards, subject_name, source_name, deck_name)
    settings = AppConfig.settings
    names = [subject_name, source_name, deck_name]
            .map { |name| name.to_s.strip }
            .reject(&:empty?)
            .join('/')

    header_text = "#{settings.language_string(:print_header)}: #{names}"
    safe_header = CGI.escapeHTML(header_text)

    html_content = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <title>#{safe_header}</title>
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            margin: 0;
            padding: 10mm;
            background-color: #ffffff;
            color: #000000;
          }
          h1 {
            border-bottom: 2px solid #333;
            padding-bottom: 10px;
            font-size: 22px;
            margin-bottom: 25px;
          }

            /* 🎯 CLEAN BLOCK WRAPPER */
          .card-container {
            display: block;
            width: 100%;
            text-align: left;
          }

          /* 🎯 UNBREAKABLE INLINE-FLEX CARDS
              Using inline-flex handles columns gracefully side-by-side on all platforms. */
          .card {
            display: inline-flex;
            flex-direction: column;
            border: 2px solid #000000;
            border-radius: 0px; /* Square corners */
            background: #ffffff;
            width: 320px;
            min-height: 240px; /* Base card layout size */
            margin: 10px;
            vertical-align: top;
            box-sizing: border-box;

            /* Rigid print commands to block vertical clipping */
            page-break-inside: avoid !important;
            break-inside: avoid-page !important;
          }

          /* 🎯 PERMANENT 50/50 VERTICAL ALIGNMENT (THE FOLD LOCK)
              Using flex: 1 0 50% guarantees that even if text auto-grows,
              both sections grow perfectly in tandem, locking the fold line in the dead center. */
          .front-side, .back-side {
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            flex: 1 0 50%;
            min-height: 118px; /* Half of card boundary */
            padding: 15px;
            text-align: center;
            box-sizing: border-box;
            word-wrap: break-word;
            overflow: hidden;
          }

          .term { font-weight: bold; font-size: 16px; color: #000000; line-height: 1.4; }
          .context { font-style: italic; color: #555555; font-size: 12px; margin-top: 6px; line-height: 1.3; }

          /* 🎯 MASTER FOLD LINE
              A solid, explicit block separating the fields natively. */
          .fold-line {
            border-top: 2px dashed #888888;
            width: 100%;
            height: 0;
            display: block;
            flex-shrink: 0;
          }

          .meaning { font-size: 15px; color: #111111; line-height: 1.4; }

          /* 🖨️ Universal Print Dialogue System Overrides */
          @media print {
          @page {
              size: auto;
              margin: 10mm;
          }
          body { padding: 0; background: #ffffff; }
          h1 { display: none; }

          .card-container {
            display: block !important;
          }

          .card {
            display: inline-flex !important;
            page-break-inside: avoid !important;
            break-inside: avoid-page !important;
          }
          }
        </style>
        </head>
        <body>
        <h1>#{safe_header}</h1>
        <div class="card-container">
    HTML

    cards.each do |card|
      html_content += <<~HTML
          <div class="card">
          <!-- Top Section: Front Side -->
          <div class="front-side">
          <div class="term">#{CGI.escapeHTML(card.term.to_s)}</div>
          #{'<div class="context">' + CGI.escapeHTML(card.context.to_s) + '</div>' if card.context && !card.context.to_s.strip.empty?}
          </div>

          <!-- Explicit Middle Fold Line Anchor -->
          <div class="fold-line"></div>

          <!-- Bottom Section: Back Side -->
          <div class="back-side">
          <div class="meaning">#{CGI.escapeHTML(card.meaning.to_s)}</div>
          </div>
        </div>
      HTML
    end

    html_content += '</div></body></html>'

    temp_file = File.join(Dir.tmpdir, 'flashcards_print.html')
    File.write(temp_file, html_content)
    temp_file
  end

  def print_via_command
    settings = AppConfig.settings

    is_deck_selected = @tree && @tree.respond_to?(:selected_path) && @tree.selected_path && @tree.selected_path.size == 3

    unless is_deck_selected
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_print_error)}: #{settings.language_string(:statusbar_no_deck_selected)}!", type: :warning
        )
      end
      return false
    end

    s_idx   = @current_subject_idx || 0
    src_idx = @current_source_idx || 0
    d_idx   = @current_deck_idx || 0

    active_subject = @library.subjects[s_idx] if defined?(@library) && @library.subjects
    active_source  = active_subject&.sources&.[](src_idx) if active_subject
    active_deck    = active_source&.decks&.[](d_idx) if active_source

    if active_deck.nil? || active_deck.cards.nil? || active_deck.cards.empty?
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_print_error)}: #{settings.language_string(:statusbar_no_cards_available)}!",
                                  type: :warning)
      end
      return false
    end

    # 3. Generate the HTML file.
    os = RbConfig::CONFIG['host_os']
    file_path = generate_print_file(active_deck.cards, active_subject.name, active_source.name, active_deck.name)

    # Hard check to ensure the file was actually written to the temp directory
    unless file_path && File.exist?(file_path) && File.size(file_path) > 0
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_print_error)}: #{settings.language_string(:statusbar_template_file_error)}!", type: :warning
        )
      end
      return false
    end

    # =========================================================================
    # 🚀 CROSS-PLATFORM BROWSER LAUNCHER
    # Open the file with the operating system's native command.
    # This launches the user's default browser.
    # =========================================================================
    case os
    when /mswin|msys|mingw|cygwin|bccwin|wince|emc/
      # 🪟 WINDOWS: Use the 'start' shell command.
      system("start \"\" \"#{file_path}\"")
    when /darwin/
      # 🍏 MACOS: Use the 'open' command.
      system("open '#{file_path}'")
    else
      # 🐧 LINUX / UNIX: Use the freedesktop xdg-open standard.
      system("xdg-open '#{file_path}'")
    end

    true
  end

  def load_custom_theme_via_command(argument)
    settings = AppConfig.settings

    if argument.empty?
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_argument_required)}: #{settings.language_string(:statusbar_theme_argument_required)}!", type: :error
      )
      return true
    end

    raw_path = argument

    # 1. NORMALIZE THE EXTENSION
    # If the user omitted the extension (.rb or .theme.rb), append .theme.rb.
    raw_path = "#{raw_path}.theme.rb" unless raw_path.end_with?('.theme.rb') || raw_path.end_with?('.rb')

    # SMART PATH ANALYSIS
    # File.dirname returns "." when the string contains no directory component or slash.
    target_theme_path = if File.dirname(raw_path) == '.'
                          # No folder name was supplied: prepend ./themes/.
                          File.join(Dir.pwd, 'themes', raw_path)
                        else
                          # A folder or subfolder was supplied: use the given relative or absolute path.
                          File.expand_path(raw_path)
                        end

    # 🔒 FILE EXISTENCE SAFETY CHECK GUARD
    unless File.exist?(target_theme_path)
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_theme_not_found)}: #{File.join('themes', raw_path)}",
        type: :error
      )
      return true
    end

    # 🟢 NUCLEAR ATOMIC EVALUATION TRANS-PIPELINE
    begin
      file_content_string = File.read(target_theme_path)

      # Precompile the code so strict Ruby 4 syntax checks can be handled safely.
      RubyVM::InstructionSequence.compile(file_content_string, target_theme_path)

      wrapped_expression = "(\n#{file_content_string}\n)"
      theme_payload_hash = eval(wrapped_expression, nil, target_theme_path)

      unless theme_payload_hash.is_a?(Hash) && !theme_payload_hash.empty?
        raise settings.language_string(:statusbar_theme_hash_error)
      end

      # 🟢 EXTRACT METADATA NAME
      # Extract the clean theme name if present; fall back to the cleaned filename capital if missing
      fallback_display_name = File.basename(target_theme_path, '.theme.rb').sub('.rb', '').capitalize
      theme_display_name = theme_payload_hash.delete(:name) || theme_payload_hash.delete('name') || fallback_display_name

      # Clear colors from any previously loaded custom theme.
      settings.theme_items.clear

      # Iterate over all TrueColor hexadecimal definitions and inject them live.
      theme_payload_hash.each do |theme_key, truecolor_hex_string|
        if settings.respond_to?(:set_theme_item)
          settings.set_theme_item(theme_key, truecolor_hex_string)
        elsif settings.respond_to?(:theme_items) && AppConfig.settings.theme_items
          settings.theme_items[theme_key] = truecolor_hex_string.to_s
        end
      end

      if settings.respond_to?(:custom_theme_name=)
        settings.custom_theme_name = theme_display_name.to_s
      else
        settings.instance_variable_set(:@custom_theme_name, theme_display_name.to_s)
      end

      # Persist the absolute path.
      if settings.respond_to?(:custom_theme_path=)
        settings.custom_theme_path = target_theme_path.to_s
      else
        settings.instance_variable_set(:@custom_theme_path, target_theme_path.to_s)
      end

      theme_symbol_name = File.basename(target_theme_path, '.theme.rb').sub('.rb', '')
      settings.theme = theme_symbol_name.to_sym if AppConfig.settings.respond_to?(:theme=)
      settings.save if AppConfig.settings.respond_to?(:save)

    # Explicitly rescue Exception here (the base class of SyntaxError)
    # so an invalid file cannot crash the TUI under any circumstances.
    rescue Exception => e
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_theme_error)}: #{settings.language_string(:statusbar_theme_syntax_error)}!", type: :error
      )
      return true # Slik de crash onvoorwaardelijk in en houd de TUI levend!
    end

    # Fully collapse and clean out the status bar console field registers
    clear_command_mode_visuals if respond_to?(:clear_command_mode_visuals)
    @command_mode_visible = false
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Return the window cursor focus parameters cleanly back onto your tree sidebar panel
    @active_focus = @menu_origin_focus || :tree
    @last_focus   = @active_focus
    @menu_origin_focus = nil

    # Force an instantaneous frame repaint across all active dashboard panels!
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  end

  def new_library_via_command(has_bang_override)
    settings = AppConfig.settings

    if @library_dirty == true && !has_bang_override
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_new_no_write_last_change)}!",
        type: :warning
      )
      @active_focus = :command_mode
      return false # Keeps the statusbar alive to allow user corrections
    end

    # 🟢 CLEAN PURGE PIPELINE: Reset memory records & initialize empty array graphs
    @library.subjects = []

    # Build the mandatory minimalist default hierarchy container track
    new_sub  = Subject.new('Subject')
    new_src  = Source.new('Source')
    new_deck = Deck.new('Deck')

    new_src.decks << new_deck
    new_sub.sources << new_src
    @library.subjects << new_sub

    if @tree && @tree.respond_to?(:expanded_paths) && @tree.expanded_paths
      @tree.expanded_paths = [] # Reset old view footprints entirely

      sub_id_path  = [new_sub.id.to_s]
      src_id_path  = [new_sub.id.to_s, new_src.id.to_s]
      deck_id_path = [new_sub.id.to_s, new_src.id.to_s, new_deck.id.to_s]

      @tree.expanded_paths << sub_id_path unless @tree.expanded_paths.include?(sub_id_path)
      @tree.expanded_paths << src_id_path unless @tree.expanded_paths.include?(src_id_path)
      @tree.expanded_paths << deck_id_path unless @tree.expanded_paths.include?(deck_id_path)
    end
    # =====================================================================

    # Discard all history undo/redo timeline snapshots to prevent memory leaks
    if respond_to?(:init_history, true)
      init_history
    elsif defined?(@undo_stack) && defined?(@redo_stack)
      @undo_stack = []
      @redo_stack = []
    end

    # Reset all core navigation indexes back to the absolute starting block anchors
    @current_subject_idx = 0
    @current_source_idx  = 0
    @current_deck_idx    = 0

    # Snap selection highlight states cleanly back onto the top row indices
    @table_state.select(0) if defined?(@table_state) && @table_state
    @tree_state.select(0)  if defined?(@tree_state) && @tree_state

    # Clean out old search and view caches
    @active_cards_cache_node  = nil if instance_variable_defined?(:@active_cards_cache_node)
    @active_cards_cache_cards = nil if instance_variable_defined?(:@active_cards_cache_cards)
    @table_visual_cache       = {}  if defined?(@table_visual_cache)

    # Sanitize file reference path properties back onto a standard default blank state
    fallback_filename = defined?(@app_name) && @app_name ? "#{@app_name.to_s.downcase}.json" : "#{@app_name}.json"
    settings.last_opened_filename = fallback_filename
    settings.save

    # Clear the console visuals and reset dirty flags completely.
    clear_command_mode_visuals if respond_to?(:clear_command_mode_visuals)
    @command_mode_visible = false
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @library_dirty = false

    # =========================================================================
    # 🎯 ABSOLUTE FOCUS LOCK & PIPELINE PURGE
    # 👉 Completely clear the historical origin registers before exiting.
    # This prevents input_controller from restoring focus to the table.
    # Return 'false' to block the automatic focus restoration rule.
    # =========================================================================
    @menu_origin_focus    = nil
    @cockpit_panel_anchor = :tree
    @active_focus         = :tree
    @last_focus           = :tree

    # Force the rendering engine to recalculate the frame immediately.

    # Refresh the tree structure.
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    @tree_state.select(0) if defined?(@tree_state) && @tree_state

    # 🎯 THE HOOK LOCK: Return false so input_controller does not restore focus to the table.
    false
  end

  def study_via_command(action)
    settings = AppConfig.settings

    # Synchronize the selected tree path with the current indices.
    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)

    subject_idx = @current_subject_idx || 0
    source_idx  = @current_source_idx || 0
    deck_idx    = @current_deck_idx || 0

    active_deck =
      @library.subjects[subject_idx]
              &.sources&.[](source_idx)
              &.decks&.[](deck_idx)

    cards = active_deck&.cards

    # Do not start a study session if the deck is missing or empty.
    if cards.nil? || cards.empty?
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_study_session_error)}: #{settings.language_string(:statusbar_min_req_cards)}!",
        type: :info
      )
      return true
    end

    chosen_mode = {
      'dr' => :drill,
      'drl' => :drill,
      'drill' => :drill,
      'qz' => :quiz,
      'quiz' => :quiz,
      'mc' => :multiple_choice,
      'multiple-choice' => :multiple_choice,
      'pm' => :memory,
      'play-memory' => :memory,
      'tk' => :two_of_a_kind,
      'toak' => :two_of_a_kind,
      'two-of-a-kind' => :two_of_a_kind,
      'duo' => :two_of_a_kind
    }[action.to_s]

    @selected_tree_paths = []
    @selected_table_rows = [] if defined?(@selected_table_rows)
    wipe_all_search_artifacts if respond_to?(:wipe_all_search_artifacts)

    study_strategy = settings.study_strategy || :fronts_random

    @cards_to_test =
      if active_deck.respond_to?(:study)
        active_deck.study(study_strategy)
      else
        cards.dup
      end

    if @cards_to_test.nil? || @cards_to_test.empty?
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_study_session_error)}: " \
        "#{settings.language_string(:statusbar_no_cards_available)}!",
        type: :info
      )
      return true
    end

    # Clear the command-mode interface.
    clear_command_mode_visuals if respond_to?(:clear_command_mode_visuals)
    @command_mode_visible = false

    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    @status_message = nil if instance_variable_defined?(:@status_message)

    # Set the study-mode state and move focus to the study view.
    @current_study_mode = chosen_mode
    @test_current_idx = 0
    @test_show_meaning = false
    @active_focus = :study_focus_mode
    @last_focus = :study_focus_mode

    # Initialize Two of a Kind game state when started via command mode.
    if (@current_study_mode == :two_of_a_kind) && !initialize_two_of_a_kind(@cards_to_test)
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_study_session_error)}: " \
        "#{settings.language_string(:statusbar_min_req_cards)}!",
        type: :info
      )

      @current_study_mode = nil
      return true
    end

    case @current_study_mode
    when :drill
      @test_awaiting_difficulty = false
      @test_progressbar_total = @cards_to_test.length
      @test_timer_paused = false
      @test_time_was_up_notified = false
      @test_drill_elapsed = 0
      @test_drill_timer_max = 2
      @test_drill_timed = false
      @test_time_left = @test_drill_timed ? @test_drill_timer_max : 0
      @test_last_tick_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    when :two_of_a_kind
      # Difficulty selection is not applicable.
      @test_awaiting_difficulty = false

    else
      # Quiz and multiple-choice modes require a difficulty level.
      @test_awaiting_difficulty = true

      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_difficulty)}: " \
        "#{settings.language_string(:statusbar_levels)}.",
        type: :warning,
        beep: settings.beeps,
        expires: false
      )
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    # Returning false keeps the focus on study_focus_mode.
    false
  end

  def pwd_via_command
    # 🎯 GET CURRENT WORKING DIRECTORY:
    # Retrieve the pure absolute system path via Ruby's native Dir.pwd module
    current_dir = Dir.pwd

    # Flush the path out into your status line with a neutral informational format
    trigger_statusbar_message("DIR: #{current_dir}.", type: :info, expires: false)

    # 🔒 KEEP BUFFER FOCUSED:
    # We utilize your central restorer to cleanly preserve command mode state
    # so the message remains visible until the user inputs another shortcut!
    restore_command_mode_focus
    false
  end

  def rename_tree_node_via_command
    settings = AppConfig.settings
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree

    unless origin == :tree
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_rename_can_only_be_used_in_tree)}!", type: :error,
                                                                                                              beep: settings.beeps)
      end
      @active_focus = :command_mode
      return false # Houdt de statusbalk open
    end

    # Record the status bar origin and lock the destination to :tree.
    @active_focus = :tree
    @menu_origin_focus = :tree
    @focus_before_help = :command_mode
    @last_focus        = :command_mode

    @command_mode_visible = false if defined?(@command_mode_visible)
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Smoothly redraw the tree panel.
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    # Route the action directly to the official tree handler.
    # Emulate the shortcut that normally starts renaming (e.g. 'r', 'R', or 'rename_node').
    # Call the handler with the appropriate key, based on TreeInputHandler:
    if respond_to?(:handle_tree_input, true)
      handle_tree_input('f2', []) # Verander 'r' naar jouw fysieke hernoemtoets mocht die afwijken
    end

    true
  end

  def add_table_card_via_command
    settings = AppConfig.settings
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree

    unless origin == :table
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_add_can_only_be_used_in_deck)}!", type: :error, beep: settings.beeps
        )
      end
      @active_focus = :command_mode
      return false
    end

    @active_focus = :table
    @menu_origin_focus = :table
    @focus_before_help = :command_mode
    @last_focus        = :command_mode
    @command_mode_visible = false if defined?(@command_mode_visible)
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Route the action directly to the official table handler to open the Add Card popup.
    if respond_to?(:handle_table_input, true)
      handle_table_input('a', :table, []) # Emuleert de 'a' (add) toetsdruk in de tabel
    end

    true
  end

  def add_tree_node_via_command
    settings = AppConfig.settings
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree

    unless origin == :tree
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message('Can only add tree nodes while inside the tree sidebar!', type: :error,
                                                                                            beep: settings.beeps)
      end
      @active_focus = :command_mode
      return false
    end

    # Return focus and clear the status bar.
    @active_focus = :tree
    @last_focus   = :tree
    @command_mode_visible = false
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Trigger the official tree handler's 'a' (add) action to open the popup.
    handle_tree_input('a', []) if respond_to?(:handle_tree_input, true)

    # 🎯 REPAINT SYNCHRONIZATION: Recalculate the tree structure live
    # and synchronize indices to prevent out-of-bounds table errors.
    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

    true
  end

  def delete_tree_nodes_via_command
    settings = AppConfig.settings
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree

    unless origin == :tree
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message('Can only delete tree nodes while inside the tree sidebar!', type: :error,
                                                                                               beep: settings.beeps)
      end
      @active_focus = :command_mode
      return false
    end

    # Prefer the early shadow backups from the handle_navigation_input boundary.
    active_tree_selection = nil
    if defined?(@statusbar_saved_tree_selection) && @statusbar_saved_tree_selection && !@statusbar_saved_tree_selection.empty?
      active_tree_selection = @statusbar_saved_tree_selection.dup
    elsif defined?(@statusbar_saved_tree_selection_backup) && @statusbar_saved_tree_selection_backup && !@statusbar_saved_tree_selection_backup.empty?
      active_tree_selection = @statusbar_saved_tree_selection_backup.dup
    end

    @active_focus = :tree
    @last_focus   = :tree
    @command_mode_visible = false
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Force the selection back into the tree panel's active array.
    @selected_tree_paths = active_tree_selection if active_tree_selection && active_tree_selection.any?

    if @selected_tree_paths && @selected_tree_paths.any? && respond_to?(:handle_selected_tree_multi_delete, true)
      handle_selected_tree_multi_delete(settings)
    elsif @selected_tree_paths && @selected_tree_paths.any? && respond_to?(:handle_tree_multi_delete, true)
      handle_tree_multi_delete(settings)
    elsif respond_to?(:handle_tree_input, true)
      handle_tree_input(:delete,
                        []) || handle_tree_input('delete',
                                                 []) || handle_tree_input('backspace',
                                                                          []) || handle_tree_input('d', [])
    end

    @selected_tree_paths = [] if defined?(@selected_tree_paths)
    @statusbar_saved_tree_selection = nil
    @statusbar_saved_tree_selection_backup = nil

    sync_indices_from_tree_path if respond_to?(:sync_indices_from_tree_path)
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    true
  end

  def delete_table_cards_via_command
    settings = AppConfig.settings
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree

    unless origin == :table
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message('Can only delete flashcards while inside the cards table!', type: :error,
                                                                                              beep: settings.beeps)
      end
      @active_focus = :command_mode
      return false
    end

    # Prefer the early shadow backups from the handle_navigation_input boundary.
    active_table_selection = nil
    if defined?(@statusbar_saved_table_selection) && @statusbar_saved_table_selection && !@statusbar_saved_table_selection.empty?
      active_table_selection = @statusbar_saved_table_selection.dup
    elsif defined?(@statusbar_saved_table_selection_backup) && @statusbar_saved_table_selection_backup && !@statusbar_saved_table_selection_backup.empty?
      active_table_selection = @statusbar_saved_table_selection_backup.dup
    end

    @active_focus = :table
    @last_focus   = :table
    @command_mode_visible = false
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Force the selection back into the table panel's active array.
    @selected_table_rows = active_table_selection if active_table_selection && active_table_selection.any?

    handle_card_deletion('backspace', false) if respond_to?(:handle_card_deletion, true)

    @statusbar_saved_table_selection = nil
    @statusbar_saved_table_selection_backup = nil
    true
  end

  def edit_table_card_via_command
    settings = AppConfig.settings
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree

    unless origin == :table
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_edit_can_only_be_used_in_deck)}!", type: :error, beep: settings.beeps
        )
      end
      @active_focus = :command_mode
      return false
    end

    @active_focus = :table
    @menu_origin_focus = :table
    @focus_before_help = :command_mode
    @last_focus        = :command_mode
    @command_mode_visible = false if defined?(@command_mode_visible)
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    # Route the action directly to the official table handler to open the Edit Card popup.
    if respond_to?(:handle_table_input, true)
      handle_table_input('e', :table, []) # Emuleert de 'e' (edit) toetsdruk in de tabel
    end

    true
  end

  # =========================================================================
  # 🎯 PRIVATE HELPER: HANDLE YES NO
  # 👉 FIXED: Typos, NameErrors, and argument mismatches have been resolved.
  # Route 'y' or 'n' to the corresponding model pipelines.
  # =========================================================================
  def handle_yes_no(command_text)
    settings = AppConfig.settings
    clean_input = command_text.to_s.strip.downcase

    # --------------------------------=========================================
    # SCENARIO A: SAVE EXTENSION WARNING (@last_warned_file)
    # --------------------------------=========================================
    if @last_warned_file
      case clean_input
      when 'y'
        # 🟢 USER CHOSE YES ➔ Save the file immediately.
        saved_target_file = @last_warned_file
        @last_warned_file = nil
        @status_message = nil if defined?(@status_message)

        clear_command_mode_visuals
        # Run the library write operation.
        @library.save(saved_target_file) if @library.respond_to?(:save)
        @library_dirty = false

        settings.last_opened_filename = saved_target_file
        settings.save

        if respond_to?(:trigger_statusbar_message, true)
          message_key = @save_operation_mode == :save_as ? :statusbar_saved : :statusbar_written

          trigger_statusbar_message(trigger_statusbar_message("#{message_key}: #{saved_target_file}!", type: :info), type: :info) #
        end

        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
        true

      when 'n'
        # ❌ USER CHOSE NO ➔ Cancel saving and close the status bar.
        @last_warned_file = nil
        @status_message = nil if defined?(@status_message)

        clear_command_mode_visuals

        true

      else
        # 🚨 INVALID KEY INTERCEPTED: Beep and keep the question active.
        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)

        if respond_to?(:trigger_statusbar_message, true)
          trigger_statusbar_message("#{settings.language_string(:statusbar_unexpected_extension)}!", type: :warning, beep: settings.beeps, expires: false) #
        end
        @active_focus = :command_mode
        false
      end

    # --------------------------------=========================================
    # SCENARIO B: CSV IMPORT WARNING (@awaiting_import_confirmation)
    # ------------------------------------------------=========================
    elsif defined?(@awaiting_import_confirmation) && !@awaiting_import_confirmation.nil?
      case clean_input
      when 'y'
        # 🟢 USER CHOSE YES ➔ Run the command again with the bypass enabled.
        ctx = @awaiting_import_confirmation
        @awaiting_import_confirmation = nil
        @status_message = nil if defined?(@status_message)

        # Restart the import pipeline with the bypass parameter enabled.
        file_import_via_command(ctx[:argument], ctx[:force_import_bypass] = true) if respond_to?(
          :file_import_via_command, true
        )

        true

      when 'n'
        # ❌ USER CHOSE NO ➔ Cancel the import and clear the status bar.
        @awaiting_import_confirmation = nil
        @status_message = nil if defined?(@status_message)

        clear_command_mode_visuals

        true

      else
        # 🚨 INVALID KEY INTERCEPTED: Beep and keep the import question active.
        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)

        trigger_statusbar_message("#{settings.language_string(:statusbar_deck_not_empty)}!", type: :warning, beep: settings.beeps, expires: false) #
        @active_focus = :command_mode
        false
      end

    # =========================================================================
    # 🎯 SCENARIO C: EXPORT FORMAT SELECTION (1=CSV, 2=XML)
    # =========================================================================
    elsif defined?(@awaiting_export_format_selection) && !@awaiting_export_format_selection.nil?
      ctx = @awaiting_export_format_selection

      case clean_input
      when '1'
        @awaiting_export_format_selection = nil
        if respond_to?(
          :trigger_statusbar_message, true
        )
          trigger_statusbar_message(settings.language_string(:statusbar_include_header), type: :warning,
                                                                                         beep: settings.beeps, expires: false)
        end
        @awaiting_export_header_selection = { paths: ctx[:paths] }
        false
      when '2'
        @awaiting_export_format_selection = nil
        custom_name = defined?(@pending_zip_custom_name) ? @pending_zip_custom_name : ''
        @pending_zip_custom_name = nil

        # 🎯 FIXED: Call the method on the @library object.
        result = @library.execute_tar_bulk_export('xml', false, custom_name)
        finalize_tar_export_ui_message(result, 'xml', false)
        true
      else
        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)
        if respond_to?(
          :trigger_statusbar_message, true
        )
          trigger_statusbar_message("#{settings.language_string(:statusbar_choose_format)}: #{settings.language_string(:statusbar_format)}", type: :warning, beep: settings.beeps,
                                                                                                                                             expires: false)
        end
        @active_focus = :command_mode
        false
      end

    # =========================================================================
    # 🎯 SCENARIO D: CSV HEADER SELECTION (y=With header, n=Without header)
    # =========================================================================
    elsif defined?(@awaiting_export_header_selection) && !@awaiting_export_header_selection.nil?
      ctx = @awaiting_export_header_selection

      custom_name = defined?(@pending_zip_custom_name) ? @pending_zip_custom_name : ''

      case clean_input
      when 'y', 'n'
        @awaiting_export_header_selection = nil
        @pending_zip_custom_name = nil

        include_header = clean_input == 'y'
        result = @library.execute_tar_bulk_export(
          'csv',
          include_header,
          custom_name
        )

        finalize_tar_export_ui_message(result, 'csv', include_header)
        true
      else
        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)
        if respond_to?(
          :trigger_statusbar_message, true
        )
          trigger_statusbar_message(settings.language_string(:statusbar_include_header), type: :warning,
                                                                                         beep: settings.beeps, expires: false)
        end
        @active_focus = :command_mode
        false
      end
    end
  end

  def replace_via_command
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree
    origin = :tree if %i[menu popup command_mode].include?(origin)

    # 🎯 PANEL PARITY: Record the origin and set @last_focus to :command_mode.
    @active_focus = origin
    @menu_origin_focus = origin
    @focus_before_help = :command_mode
    @last_focus        = :command_mode

    # 🎯 THE MINIMAL FIX: Fully close the status bar immediately.
    @command_mode_visible = false if defined?(@command_mode_visible)
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    @tree.refresh_nodes if origin == :tree && @tree.refresh_nodes

    if origin == :tree && respond_to?(:handle_tree_input, true)
      handle_tree_input('\\', [])
    elsif origin == :table && respond_to?(:handle_table_input, true)
      handle_table_input('\\', :table, [])
    end

    true
  end

  def file_import_via_command(argument, bypass_override = false)
    settings = AppConfig.settings
    argument_file = argument.to_s.strip

    force_import_bypass = (bypass_override == true) ||
                          (defined?(@awaiting_import_confirmation_bypass) && @awaiting_import_confirmation_bypass == true) ||
                          argument_file.end_with?('!') ||
                          (defined?(@has_bang_command_override) && @has_bang_command_override == true)

    argument_file = argument_file.sub(/!\z/, '').strip

    if argument_file.empty?
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_argument_required)}: #{settings.language_string(:statusbar_import_argument_required)}!", type: :error, beep: settings.beeps
        )
      end
      restore_command_mode_focus
      return false
    end

    argument_file = "#{argument_file}.csv" if File.extname(argument_file).empty?

    unless File.exist?(argument_file)
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_file_not_found)}: #{argument_file}!",
                                  type: :error)
      end
      restore_command_mode_focus
      return false
    end

    selected_path = @tree.respond_to?(:selected_path) ? @tree.selected_path : nil
    path_length = selected_path.is_a?(Array) ? selected_path.length : 0

    unless [2, 3].include?(path_length)
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_import_error)}: #{settings.language_string(:statusbar_not_a_source_or_deck)}!", type: :error, beep: true
        )
      end
      restore_command_mode_focus
      return false
    end

    active_subject = @library.subjects[@current_subject_idx || 0]
    active_source = active_subject&.sources&.[](@current_source_idx || 0)
    return false if active_source.nil?

    target_deck = nil

    if path_length == 2
      existing_numbers = active_source.decks.map do |d|
        d.name.to_s.match(/\AImported\s+(\d+)\z/i) { |m| m[1].to_i }
      end.compact

      next_number = existing_numbers.any? ? existing_numbers.max + 1 : 1
      new_deck_name = "Imported #{next_number}"

      target_deck = Deck.new(new_deck_name, [])
      active_source.decks << target_deck
      @current_deck_idx = active_source.decks.length - 1
    else
      target_deck = active_source.decks[@current_deck_idx || 0]
      return false if target_deck.nil?

      if target_deck.cards && !target_deck.cards.empty? && !force_import_bypass
        if respond_to?(:trigger_statusbar_message, true)
          trigger_statusbar_message("#{settings.language_string(:statusbar_deck_not_empty)}!",
                                    type: :warning,
                                    beep: settings.beeps,
                                    expires: false)
        end
        @awaiting_import_confirmation = { argument: argument, force_import_bypass: true }
        @active_focus = :command_mode
        return false
      end
    end

    # =========================================================================
    # 🎯 COUPLING FIX: TARGET THE DECK DIRECTLY.
    # 👉 Avoid the confusing @cards controller variable. Let import_csv
    # put the cards directly into 'target_deck.cards'.
    # =========================================================================
    begin
      target_deck.cards ||= []

      # Call the import. Because import_csv stores the cards directly
      # in '@cards' (the deck instance's array), this now works reliably.
      import_result = target_deck.import_csv(argument_file)
    rescue StandardError => e
      import_result = e
    end

    # 4. HANDLE SUCCESS OR FAILURE
    if import_result.is_a?(StandardError) || import_result.nil? || import_result.to_i.zero?
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_import_no_valid_csv)}!", type: :error,
                                                                                                  beep: true)
      end
      restore_command_mode_focus
      false
    else
      # 🟢 PANEL SUCCESS PIPELINE:
      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)
      @command_mode_visible = false if defined?(@command_mode_visible)

      @active_focus = @menu_origin_focus || :tree
      @last_focus = @active_focus
      @menu_origin_focus = nil
      @library_dirty = true

      trigger_statusbar_message("#{settings.language_string(:statusbar_imported)}: #{import_result} #{settings.language_string(:statusbar_imported_into)} '#{target_deck.name}'!",
                                type: :info)

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      true
    end
  end

  def file_export
    settings = AppConfig.settings
    paths_to_export = if defined?(@selected_tree_paths) && @selected_tree_paths && !@selected_tree_paths.empty?
                        @selected_tree_paths.dup
                      elsif @tree.respond_to?(:selected_path) && @tree.selected_path
                        [@tree.selected_path]
                      else
                        []
                      end

    if paths_to_export.empty?
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_export_error)}: #{settings.language_string(:statusbar_not_a_source_or_deck)}!", type: :error, beep: true
      )
      restore_command_mode_focus
      return false
    end

    # Activate the first layered prompt.
    trigger_statusbar_message(settings.language_string(:statusbar_export_to), type: :warning, beep: settings.beeps)

    @awaiting_export_format_selection = { paths: paths_to_export }
    @active_focus = :command_mode
    false
  end

  def file_open_via_command(argument)
    settings = AppConfig.settings
    argument_file = argument.to_s.strip

    # 🔒 GUARD A: An argument/filename is required.
    if argument_file.empty?
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_argument_required)}: #{settings.language_string(:statusbar_open_argument_required)}!",
                                  type: :error)

      end
      restore_command_mode_focus
      return false
    end

    # 🔒 GUARD B: Append the extension if the user omitted it.
    argument_file = "#{argument_file}.json" if File.extname(argument_file).empty?

    # 🔒 GUARD C: Check that the file actually exists.
    unless File.exist?(argument_file)
      trigger_statusbar_message("#{settings.language_string(:statusbar_file_not_found)}: #{argument_file}!",
                                type: :error)

      restore_command_mode_focus
      return false
    end

    # 4. Run the open pipeline through a StandardError guard.
    temp_db = Library.new
    open_result = begin
      temp_db.open(argument_file) if temp_db.respond_to?(:open)
    rescue StandardError => e
      e
    end

    if open_result.is_a?(StandardError)
      clean_error = if File.zero?(argument_file) || open_result.message.include?('end of input')
                      settings.language_string(:statusbar_empty_file_error)
                    else
                      open_result.message
                    end

      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_open_error)}: #{clean_error}!",
                                  type: :error, beep: true)
      end
      restore_command_mode_focus
      false
    else
      # 🟢 SUCCESS: The new library was loaded successfully.
      # Immediately update the last-opened filename in AppConfig settings.
      @library.subjects = temp_db.subjects
      settings.last_opened_filename = argument_file
      settings.save

      # This blows open every branch level unconditionally upon file ingestion!
      if @tree && @tree.respond_to?(:expanded_paths)
        @tree.expanded_paths = [] # Clean out any verouderde view footprints entirely

        (@library.subjects || []).each do |subject|
          sub_path = [subject.id.to_s]
          @tree.expanded_paths << sub_path unless @tree.expanded_paths.include?(sub_path)

          (subject.sources || []).each do |source|
            src_path = sub_path + [source.id.to_s]
            @tree.expanded_paths << src_path unless @tree.expanded_paths.include?(src_path)

            (source.decks || []).each do |deck|
              deck_path = src_path + [deck.id.to_s]
              @tree.expanded_paths << deck_path unless @tree.expanded_paths.include?(deck_path)
            end
          end
        end
      end

      # Reset navigation indices to prevent array overflows in the new table.
      @current_subject_idx = 0
      @current_source_idx  = 0
      @current_deck_idx    = 0
      @table_state.select(0) if defined?(@table_state) && @table_state
      @tree_state.select(0)  if defined?(@tree_state) && @tree_state

      # Reset the panel's dirty state.
      @library_dirty = false

      # Clear the status bar completely (including the prompt and cursor).
      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)
      @command_mode_visible = false if defined?(@command_mode_visible)

      # Restore focus to the main window.
      @active_focus = @menu_origin_focus || :tree
      @last_focus = @active_focus
      @menu_origin_focus = nil

      trigger_statusbar_message("#{settings.language_string(:statusbar_opened)}: #{argument_file}!", type: :info)

      # Force all panels and the tree to refresh immediately.
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
      true
    end
  end

  def quit_via_command
    settings = AppConfig.settings

    if defined?(@library_dirty) && @library_dirty == true
      trigger_statusbar_message(settings.language_string(:statusbar_quit_warning), type: :warning,
                                                                                   beep: settings.beeps)
      @active_focus = :command_mode
    else
      @quit_requested = true
    end
  end

  def show_help
    if defined?(@active_focus) && @active_focus == :command_mode
    # Leave @menu_origin_focus unchanged; it is already set to :table.
    else
      @menu_origin_focus = defined?(@active_focus) && %i[tree table].include?(@active_focus) ? @active_focus : :tree
    end

    @focus_before_help = :command_mode
    @last_focus        = :command_mode

    open_help_popup

    @command_mode_visible = false
    if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.text = ''
      @statusbar_field.is_focused = false
      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=)
    end

    @active_focus = :popup
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def search_via_command
    origin = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree
    origin = :tree if %i[menu popup command_mode].include?(origin)

    # 🎯 COCKPIT PARITEIT: Sla de herkomst op en zet @last_focus correct op :command_mode
    @active_focus = origin
    @menu_origin_focus = origin
    @focus_before_help = :command_mode
    @last_focus        = :command_mode

    @command_mode_visible = false if defined?(@command_mode_visible)
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field

    @tree.refresh_nodes if origin == :tree && @tree.respond_to?(:refresh_nodes)

    if origin == :tree && respond_to?(:handle_tree_input, true)
      handle_tree_input('/', [])
    elsif origin == :table && respond_to?(:handle_table_input, true)
      handle_table_input('/', :table, [])
    end
    true
  end

  def file_save_as(argument)
    settings = AppConfig.settings
    argument_file = argument.to_s.strip

    # 🔒 BRANDMUUR A: Er MOET verplicht een argument/bestandsnaam worden opgegeven!
    if argument_file.empty?
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_argument_required)}: #{settings.language_string(:statusbar_saveas_argument_required)}!", type: :error,
                                                                                                                                                                  beep: settings.beeps)
      end
      @active_focus = :command_mode
      return false
    end

    has_bang_override = argument_file.end_with?('!')
    argument_file = argument_file.chop if has_bang_override

    argument_file = "#{argument_file}.json" if File.extname(argument_file).empty?

    target_directory = File.dirname(argument_file)
    if target_directory != '.' && target_directory != '/' && !Dir.exist?(target_directory)
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_save_error)}: #{settings.language_string(:statusbar_dir_not_exists)}: #{target_directory}!", type: :error, beep: true) #
      end
      @active_focus = :command_mode
      return false
    end

    active_ext = File.extname(argument_file).to_s.downcase
    is_invalid_extension = !active_ext.empty? && active_ext != '.json'
    file_already_exists = File.exist?(argument_file)

    unless has_bang_override
      if file_already_exists
        if respond_to?(:trigger_statusbar_message, true)
          trigger_statusbar_message("#{settings.language_string(:statusbar_already_exists)}!", type: :warning,
                                                                                               beep: settings.beeps)
        end
        @active_focus = :command_mode
        return false
      elsif is_invalid_extension
        if respond_to?(:trigger_statusbar_message, true)
          trigger_statusbar_message("#{settings.language_string(:statusbar_unexpected_extension)}!", type: :warning,
                                                                                                     beep: settings.beeps)
        end
        @active_focus = :command_mode
        return false
      end
    end

    # 1. Store the old filename in case saving fails or is cancelled.
    old_filename = @library.respond_to?(:last_opened_filename) ? settings.last_opened_filename : nil

    # 2. Point the library to the new name first so the entire
    # save pipeline (including extension handling and the 'y' branch) uses it.
    settings.last_opened_filename = argument_file
    settings.save

    # 3. Call the proven save method with an empty argument because the pointer is already set.
    # This triggers automatic .json extension handling and the Y/N warning.
    begin
      save_success = @library.save(argument_file)

      if save_success == false
        # The library rejected the save internally (e.g. during validation).
        if defined?(@last_warned_file) && @last_warned_file.nil? && settings.respond_to?(:last_opened_filename=)
          settings.last_opened_filename = old_filename
        end
        @save_operation_mode = nil
        return false
      end
    rescue StandardError => e
      # 🚨 AN I/O, PERMISSION, OR CRASH ERROR OCCURRED WHILE WRITING.
      # Restore the library pointer to the original file immediately.
      settings.last_opened_filename = old_filename if @library.respond_to?(:last_opened_filename=)

      # Show the exact error in the status bar with an audible beep.
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_save_error)}: #{e.message}!", type: :error,
                                                                                                       beep: settings.beeps)
      end

      # Keep focus on the status bar so the user can correct the text.
      restore_command_mode_focus
      @save_operation_mode = nil
      return false # Blokkeer de succes-afhandeling onvoorwaardelijk!
    end
    # =========================================================================

    @save_operation_mode = nil

    true
  end

  def file_write_via_command(argument, cmd_parts, force_quit = false, force_bypass: false)
    settings = AppConfig.settings
    raw_action = cmd_parts.first.to_s.downcase
    has_bang_override = raw_action.end_with?('!')

    # 1. Determine the filename and clean up the input.
    argument_file = argument.to_s.strip
    has_custom_argument = !argument_file.empty?

    argument_file = argument_file.chop if has_bang_override && argument_file.end_with?('!')

    target_filename = has_custom_argument ? argument_file : (settings.last_opened_filename || "#{@app_name}.json")
    target_filename = target_filename.chop if target_filename.end_with?('!')

    # 2. Automatic extension handling.
    if !target_filename.empty? && File.extname(target_filename).empty?
      target_filename = "#{target_filename}.json"
      argument_file = "#{argument_file}.json" if has_custom_argument
    end

    # =========================================================================
    # 🎯 1. PRIORITY GUARD: VIM-STYLE "NOT DIRTY" CHECK
    # 👉 If no new argument was supplied and the library is clean,
    # do not write anything; stop immediately.
    # =========================================================================
    if @library_dirty == false && !has_custom_argument && respond_to?(:trigger_statusbar_message, true)
      if force_quit
        @quit_requested = true
        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
        return true
      else
        trigger_statusbar_message("#{settings.language_string(:statusbar_save_not_dirty)}: #{target_filename}!",
                                  type: :info)
        restore_command_mode_focus
        return false
      end
    end

    target_directory = File.dirname(target_filename)
    if target_directory != '.' && target_directory != '/' && !Dir.exist?(target_directory)
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_save_error)}: #{settings.language_string(:statusbar_dir_not_exists)}: #{target_directory}!", type: :error, beep: true
        )
      end
      restore_command_mode_focus
      return false # Blokkeer de schrijfoperatie en houd de statusbalk open voor correctie!
    end

    # =========================================================================
    # 🎯 EXTENSION GUARD
    # =========================================================================
    if has_custom_argument && !has_bang_override && !force_bypass
      active_ext = File.extname(target_filename).to_s.downcase
      is_invalid_extension = !active_ext.empty? && active_ext != '.json'
      file_already_exists = File.exist?(target_filename)

      if file_already_exists
        # 🔒 SCENARIO A: The file already exists on disk.
        if respond_to?(:trigger_statusbar_message, true)
          trigger_statusbar_message("#{settings.language_string(:statusbar_already_exists)}!", type: :warning,
                                                                                               beep: settings.beeps)
        end
        @active_focus = :command_mode
        return false
      elsif is_invalid_extension
        # 🔒 SCENARIO B: The file does not exist and the extension is not .json.
        if respond_to?(:trigger_statusbar_message, true)
          trigger_statusbar_message("#{settings.language_string(:statusbar_unexpected_extension)}!", type: :warning,
                                                                                                     beep: settings.beeps)
        end
        @active_focus = :command_mode
        return false
      end
    end

    # 4. Run the save pipeline.
    save_result = begin
      if respond_to?(:execute_library_save, true)
        execute_library_save(cmd_parts[1..])
      elsif @library.respond_to?(:save)
        @library.save(argument_file.empty? ? nil : target_filename)
      end
    rescue StandardError => e
      e
    end

    # 5. Error guard.
    if save_result.is_a?(StandardError)
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_write_error)}: #{save_result.message}!",
                                  type: :error, beep: true)
      end
      restore_command_mode_focus
      false
    elsif save_result == false
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_no_filename_known)}!", type: :error,
                                                                                                beep: true)
      end
      restore_command_mode_focus
      false
    else
      # 🟢 SUCCESS: VIM-STYLE FEEDBACK
      bytes_written = begin; File.size(target_filename); rescue StandardError; 0; end
      lines_written = File.exist?(target_filename) ? File.read(target_filename).count("\n") : 0

      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
      @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)
      @library_dirty = false

      if respond_to?(:trigger_statusbar_message, true)
        file_name = File.basename(target_filename.to_s)
        if force_quit
          @quit_requested = true
        else
          # Determine whether this was a rename/save_as by checking for argument_file.
          if !argument_file.empty?
            trigger_statusbar_message("#{settings.language_string(:statusbar_saved)}: \"#{file_name}\" #{settings.language_string(:statusbar_new_file)} #{lines_written}L, #{bytes_written}B!",
                                      type: :info)
          else
            trigger_statusbar_message("#{settings.language_string(:statusbar_written)}: \"#{file_name}\" #{lines_written}L, #{bytes_written}B!",
                                      type: :info)
          end
        end
      end
      @save_operation_mode = nil
      true
    end
  end

  # =========================================================================
  # 🎯 REUSABLE HELPER 1: EXTENSION SANITIZER
  # Append .json to the filename if no extension is present.
  # =========================================================================
  def sanitize_json_extension(target_filename, argument_file)
    if !target_filename.empty? && File.extname(target_filename).empty?
      target_filename = "#{target_filename}.json"
      argument_file = "#{argument_file}.json" unless argument_file.empty?
    end
    [target_filename, argument_file]
  end

  def toggle_beeps_via_command
    return unless respond_to?(:trigger_statusbar_message)

    settings = AppConfig.settings
    current_state = settings.respond_to?(:beeps) ? settings.beeps : true
    target_state  = !current_state

    # 1. Update the active configuration in the settings class [3].
    settings.beeps = target_state if settings.respond_to?(:beeps=)

    # 2. Persist the new state immediately [3].
    settings.save if settings.respond_to?(:save)

    # 4. Show a clear, dynamic confirmation in the status bar.
    if respond_to?(:trigger_statusbar_message)
      state_label = target_state ? settings.language_string(:statusbar_beeps_on) : settings.language_string(:statusbar_beeps_off)
      trigger_statusbar_message("#{state_label}!", type: :info)
    end

    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @active_focus = :command_mode
  end

  def toggle_rotation_indicator_via_command
    return unless respond_to?(:trigger_statusbar_message)

    settings = AppConfig.settings
    current_state = settings.respond_to?(:rotation_indicator_enabled) ? settings.rotation_indicator_enabled : true
    target_state = !current_state

    settings.rotation_indicator_enabled = target_state if settings.respond_to?(:rotation_indicator_enabled=)

    if target_state
      activate_rotation_indicator(play_sound: false)
    else
      @rotation_indicator_countdown = 0
    end

    settings.save if settings.respond_to?(:save)

    state_label = target_state ? settings.language_string(:statusbar_rotation_indicator_on) : settings.language_string(:statusbar_rotation_indicator_off)
    trigger_statusbar_message("#{state_label}!", type: :info)

    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @active_focus = :command_mode
  end

  def show_markers_via_command
    settings = AppConfig.settings

    trigger_statusbar_message("#{settings.language_string(:statusbar_markers)}: #{settings.language_string(:statusbar_available_markers)}",
                              type: :info, expires: false)

    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @active_focus = :command_mode
  end

  def set_marker_via_command(argument)
    settings = AppConfig.settings

    current_marker = settings.respond_to?(:marker_symbol) ? settings.marker_symbol[:label] : 'cross'

    if argument.empty?
      if respond_to?(:trigger_statusbar_message)
        trigger_statusbar_message("#{settings.language_string(:statusbar_show_active_marker)}: #{current_marker.to_s.downcase}.",
                                  type: :info)
      end

      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @active_focus = :command_mode
    else
      marker_aliases = {
        'x' => :cross,
        'c' => :cross,
        '+' => :plus,
        'p' => :plus,
        'b' => :block,
        '*' => :asterisk,
        'a' => :asterisk
      }

      normalized_input = argument.strip.downcase
      marker_sym = marker_aliases.fetch(normalized_input, normalized_input.to_sym)

      if AppConfig::MARKERS.key?(marker_sym)
        return false if setting_already_in_use?(:marker_symbol, marker_sym.to_s)

        settings.selected_marker = marker_sym
        settings.save

        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

        selected_marker = settings.respond_to?(:marker_symbol) && settings.marker_symbol.is_a?(Hash) ? settings.marker_symbol[:label] : argument

        if respond_to?(:trigger_statusbar_message)
          trigger_statusbar_message("#{settings.language_string(:statusbar_marker_succes)}: #{selected_marker.to_s.downcase}!",
                                    type: :info)
        end

        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @active_focus = :command_mode
      else
        if respond_to?(:trigger_statusbar_message)
          trigger_statusbar_message(
            "#{settings.language_string(:statusbar_marker_not_available)}: #{argument}.", type: :error, beep: settings.beeps
          )
        end
        @active_focus = :command_mode
      end
    end
  end

  def show_corners_via_command
    return unless respond_to?(:trigger_statusbar_message)

    settings = AppConfig.settings

    trigger_statusbar_message("#{settings.language_string(:statusbar_corners)}: #{settings.language_string(:statusbar_available_corners)}",
                              type: :info, expires: false)

    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @active_focus = :command_mode
  end

  def set_corner_via_command(argument)
    settings = AppConfig.settings

    normalized_corner = argument.strip.downcase

    if normalized_corner.empty?
      # If the user enters only ':corner', show the active corner style.
      current_corner = settings.respond_to?(:corner) ? settings.corner : 'rounded'

      if respond_to?(:trigger_statusbar_message)
        trigger_statusbar_message("#{settings.language_string(:statusbar_show_active_corner)}: #{current_corner}",
                                  type: :info)
      end

      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @active_focus = :command_mode
    else
      # 🎯 THE CORNER ALIASES MATRIX:
      # Map quick terminal abbreviations or common design terms to your exact keys!
      corner_aliases = {
        'plain' => :plain,
        'p' => :plain,
        'sharp' => :plain,
        'square' => :plain,
        'box' => :plain,
        'classic' => :plain,

        'rounded' => :rounded,
        'r' => :rounded,
        'round' => :rounded,
        'smooth' => :rounded,
        'curved' => :rounded
      }

      corner_sym = corner_aliases.fetch(normalized_corner, normalized_corner.to_sym)

      # Validate explicitly against your structural configurations
      if AppConfig::CORNERS.key?(corner_sym)
        return false if setting_already_in_use?(:corner, corner_sym.to_s)

        if settings.respond_to?(:corner=)
          settings.corner = corner_sym
        elsif settings.respond_to?(:set_corner)
          settings.set_corner(corner_sym)
        end

        settings.save if settings.respond_to?(:save)

        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

        if respond_to?(:trigger_statusbar_message)
          trigger_statusbar_message("#{settings.language_string(:statusbar_corner_succes)}: #{corner_sym}!",
                                    type: :info)
        end

        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @active_focus = :command_mode
      else
        # Fault: Unknown style. Drop warning, KEEP TEXT IN LINE BUFFER, and retain focus state!
        if respond_to?(:trigger_statusbar_message)
          trigger_statusbar_message(
            "#{settings.language_string(:statusbar_corner_not_available)}: #{argument}.", type: :error, beep: settings.beeps
          )
        end
        @active_focus = :command_mode
      end
    end
  end

  def show_languages_via_command
    return unless respond_to?(:trigger_statusbar_message)

    settings = AppConfig.settings

    trigger_statusbar_message("#{settings.language_string(:statusbar_languages)}: #{settings.language_string(:statusbar_available_languages)}",
                              type: :info, expires: false)

    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @active_focus = :command_mode
  end

  def set_lang_via_command(argument)
    settings = AppConfig.settings

    normalized_lang = argument.strip.downcase

    if normalized_lang.empty?
      lang_key = settings.respond_to?(:language) ? settings.language : :en
      lang_key = lang_key.to_s.gsub(/\A:/, '').to_sym
      lang_data = AppConfig::LANGUAGES[lang_key]
      display_label = lang_data.is_a?(Hash) ? (lang_data[:label] || lang_key.to_s.upcase) : lang_key.to_s.upcase

      if respond_to?(:trigger_statusbar_message)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_show_active_lang)}: #{display_label}", type: :info
        )
      end

      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @active_focus = :command_mode
    elsif %w[nl en].include?(normalized_lang)
      lang_sym = normalized_lang.to_sym

      return false if setting_already_in_use?(:language, lang_sym.to_s)

      # 1. Update the active language configuration in the central settings.
      if settings.respond_to?(:language=)
        settings.language = lang_sym
      elsif settings.respond_to?(:set_language)
        settings.set_theme(lang_sym) # Mocht je interne methode zo heten
      end

      # 2. Persist the new language preference in config/settings.yml.
      settings.save if settings.respond_to?(:save)

      # 3. Force the entire dashboard and sidebar to synchronize with a live frame.
      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

      if respond_to?(:trigger_statusbar_message)
        trigger_statusbar_message("#{settings.language_string(:statusbar_lang_succes)}!", type: :info)
      end

      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @active_focus = :command_mode
    else
      # Error: Invalid language entered. Show the message, keep the text, and retain focus.
      if respond_to?(:trigger_statusbar_message)
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_lang_not_available)}: #{argument}.",
          type: :error, beep: settings.beeps
        )
      end
      @active_focus = :command_mode
    end
  end

  def show_themes_via_command
    return unless respond_to?(:trigger_statusbar_message)

    settings = AppConfig.settings

    trigger_statusbar_message("#{settings.language_string(:statusbar_themes)}: #{settings.language_string(:statusbar_available_themes)}",
                              type: :info, expires: false)

    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @active_focus = :command_mode
  end

  def set_theme_via_command(argument)
    settings = AppConfig.settings
    normalized_theme = argument.to_s.strip.downcase

    if normalized_theme.empty?
      active_theme = settings.theme.to_s.gsub(/\A:/, '').to_sym

      active_name =
        if settings.custom_theme_name && !settings.custom_theme_name.to_s.strip.empty?
          settings.custom_theme_name
        elsif AppConfig::THEMES.key?(active_theme)
          AppConfig::THEMES.dig(active_theme, :label)
        else
          active_theme.to_s
        end

      trigger_statusbar_message(
        "Active theme: #{active_name}.",
        type: :info
      )

      @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
      @active_focus = :command_mode
      true
    else
      theme_aliases = {
        'default' => :dark,
        'classic' => :dark,
        'standard' => :dark,
        'monochrome' => :bw,
        'blackwhite' => :bw,
        'mono' => :bw,
        'ibm' => :cga,
        'retro' => :cga,
        'green' => :crt,
        'blue' => :borland,
        'lila' => :c64,
        'brown' => :amber,
        'yellow' => :amber,
        'orange' => :amber,
        'teletext' => :ttx,
        'atari' => :tos,
        'gray' => :tos
      }

      theme_sym = theme_aliases.fetch(
        normalized_theme,
        normalized_theme.to_sym
      )

      theme_exists =
        defined?(AppThemes) &&
        defined?(AppThemes::THEME_DATA) &&
        AppThemes::THEME_DATA.key?(theme_sym)

      theme_exists ||= AppConfig::THEMES.key?(theme_sym)

      if theme_exists
        return false if setting_already_in_use?(:theme, theme_sym.to_s)

        settings.theme = theme_sym
        settings.custom_theme_name = nil
        settings.custom_theme_path = nil
        settings.save

        @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)

        theme_label = AppConfig::THEMES.dig(theme_sym, :label) || theme_sym.to_s

        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_theme_succes)}: #{theme_label}!",
          type: :info
        )

        @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
        @active_focus = :command_mode
        true
      else
        trigger_statusbar_message(
          "#{settings.language_string(:statusbar_theme_not_available)}: #{argument}!",
          type: :error,
          beep: settings.beeps
        )

        @active_focus = :command_mode
        false
      end
    end
  end

  def clear_command_mode_visuals
    @statusbar_field.text = '' if defined?(@statusbar_field) && @statusbar_field
    @statusbar_field.is_focused = false if defined?(@statusbar_field) && @statusbar_field
    @statusbar_field.cursor_index = 0 if @statusbar_field.respond_to?(:cursor_index=, true)
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  def finalize_tar_export_ui_message(result, format_choice, include_header)
    settings = AppConfig.settings

    clear_command_mode_visuals

    return unless respond_to?(:trigger_statusbar_message, true)

    if result.is_a?(StandardError)
      trigger_statusbar_message("#{settings.language_string(:statusbar_export_error)}: #{result.message}",
                                type: :error, beep: true)
    else
      header_msg = if format_choice == 'csv'
                     " (header: #{include_header ? 'yes' : 'no'})"
                   else
                     ''
                   end
      trigger_statusbar_message(
        "#{settings.language_string(:statusbar_export_success)}: #{result[:files_count]} #{settings.language_string(:statusbar_exported_decks)} (#{result[:cards_count]} #{settings.language_string(:statusbar_exported_cards)}) #{settings.language_string(:statusbar_exported_into)}: #{result[:archive_path]}#{header_msg}!", type: :info
      )
    end
  end

  def setting_already_in_use?(setting_key, new_value)
    settings = AppConfig.settings

    # 1. Read the current active value from the central settings.
    current_value = case setting_key
                    when :marker_symbol then settings.respond_to?(:selected_marker) ? settings.selected_marker : settings.marker_symbol
                    when :language      then settings.language
                    when :theme         then settings.theme
                    when :corner        then settings.corner
                    end

    # 2. Normalize the value and remove brackets [], whitespace, and capitalization.
    clean_current = current_value.to_s.strip.downcase.gsub(/[\[\]]/, '')
    clean_new     = new_value.to_s.strip.downcase.gsub(/[\[\]]/, '')

    if setting_key == :marker_symbol
      marker_aliases = {
        'x' => 'cross', 'c' => 'cross', '+' => 'plus', 'p' => 'plus',
        'b' => 'block', '*' => 'asterisk', 'a' => 'asterisk'
      }
      clean_new = marker_aliases.fetch(clean_new, clean_new)
    end

    # 🎯 DUPLICATE SETTING GUARD:
    # Compare the normalized characters directly ("x" == "x").
    if clean_current == clean_new
      if respond_to?(:trigger_statusbar_message, true)
        trigger_statusbar_message("#{settings.language_string(:statusbar_no_change)}: #{settings.language_string(:statusbar_already_set)}!", type: :warning,
                                                                                                                                             beep: settings.beeps)
      end
      return true # 🔒 Ja, deze is al in gebruik!
    end

    false
  end

  def restore_command_mode_focus
    @active_focus = :command_mode

    # Bewaar de oorspronkelijke focus (:tree of :table).
    # Overschrijf deze niet met :command_mode.
    @menu_origin_focus ||= @last_focus if %i[tree table].include?(@last_focus)

    return unless defined?(@statusbar_field) && @statusbar_field

    @statusbar_field.is_focused = true
  end
end
