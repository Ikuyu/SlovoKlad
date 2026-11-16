# app.rb

require 'ratatui_ruby'
require 'clipboard'
require 'io/console'
require 'yaml'
require 'unicode/display_width'
require_relative 'models/library'
require_relative 'lib/library_history_manager'
require_relative 'lib/rattree'
require_relative 'config/software_cursor'
require_relative 'audio/sound_manager'
require_relative 'config/terminal_theme_resolver'

# 🎯 LOAD-BEARING INITIALIZATION: Load all configuration files FIRST, including AppConfig!
# This makes AppConfig available to the Library classes immediately.
Dir[File.join(__dir__, 'config', '*.rb')].sort.each { |file| require_relative file }

# 🚀 ACTIVATED: Only now enable the CLI handler gatekeeper.
require_relative 'config/cli_handler'
target_file = CliHandler.handle_arguments

# If a filename was passed through the terminal, persist it in the settings.
if target_file && !target_file.empty?
  target_file = "#{target_file}.json" if File.extname(target_file).empty?
  AppConfig.settings.last_opened_filename = target_file
  AppConfig.settings.save
end

begin
  Dir[File.join(__dir__, 'views', '*.rb')].sort.each do |file|
    require_relative file
  end

  search_handler_path = File.join(__dir__, 'controllers', 'search_input_handler.rb')
  require_relative search_handler_path if File.exist?(search_handler_path)

  Dir[File.join(__dir__, 'controllers', '*.rb')].sort.each do |file|
    require_relative file
  end
rescue FriBidiNative::Unavailable => e
  warn e.message
  exit 1
end

class RatatuiRubyApp
  EVENT_WAIT_TIMEOUT = 3600.0

  include LibraryHistoryManager
  include StartupView
  include NavigationInputHandler

  attr_reader :popup, :library_tree, :library, :software_cursor

  def initialize
    initialize_runtime_objects
    initialize_application_state
    initialize_initial_selection
    initialize_history
  end

  def initialize_runtime_objects
    @popup = PopupManager.new

    settings = AppConfig.settings
    initialize_corrupt_settings_warning(settings.load)

    load_app_info

    @library = load_library
    initialize_empty_library if @library.subjects.nil? || @library.subjects.empty?

    @tree_state = RatatuiRuby::ListState.new(0)
    @tree = RatTree.new(@library)
    @table_state = RatatuiRuby::TableState.new(0)

    # =========================================================================
    # 🎯 STARTUP GUARD THROUGH DIRECT PATH RELOAD AND FALLBACK (OPTIMIZED)
    # 👉 Open the saved path directly instead of searching by name.
    # If the file is missing or has a syntax error, restore :default.
    # =========================================================================
    saved_theme = settings.respond_to?(:theme) ? settings.theme : :default
    saved_theme_sym = saved_theme.to_s.strip.downcase.to_sym
    built_in_themes = %i[default cga julia crt amber borland dracula ttx c64 tos terminal]

    # Retrieve the saved path.
    saved_theme_path = if settings.respond_to?(:custom_theme_path)
                         settings.custom_theme_path
                       elsif settings.instance_variable_defined?(:@custom_theme_path)
                         settings.instance_variable_get(:@custom_theme_path)
                       end

    unless built_in_themes.include?(saved_theme_sym) || saved_theme_path.to_s.strip.empty?
      begin
        raise settings.language_string(:statusbar_file_removed_or_deleted) unless File.exist?(saved_theme_path.to_s)

        file_content = File.read(saved_theme_path.to_s)

        # Precompile to ensure compatibility with Ruby 4 syntax.
        RubyVM::InstructionSequence.compile(file_content, saved_theme_path.to_s)

        # Evaluate the expression directly into a populated hash.
        boot_payload = eval("(\n#{file_content}\n)", nil, __FILE__, __LINE__)

        unless boot_payload.is_a?(Hash) && !boot_payload.empty?
          raise setting.language_string(:statusbar_theme_hash_error)
        end

        # Restore the display-label metadata.
        fallback_label = saved_theme_sym.to_s.capitalize
        theme_label = boot_payload.delete(:name) || boot_payload.delete('name') || fallback_label

        if settings.respond_to?(:custom_theme_name=)
          settings.custom_theme_name = theme_label.to_s
        else
          settings.instance_variable_set(:@custom_theme_name, theme_label.to_s)
        end

        # Inject the TrueColor hex colors directly into the caches.
        boot_payload.each do |t_key, hex_str|
          if settings.respond_to?(:set_theme_item)
            settings.set_theme_item(t_key, hex_str)
          elsif settings.respond_to?(:theme_items) && AppConfig.settings.theme_items
            settings.theme_items[t_key] = hex_str.to_s
          end
        end
      rescue Exception
        # 🚨 EMERGENCY FALLBACK: If the file is corrupt, missing, or moved, restore :default unconditionally!
        if settings.respond_to?(:theme=)
          settings.theme = :default
        elsif settings.respond_to?(:set_theme)
          settings.set_theme(:default)
        end

        # Thoroughly clear the custom configuration caches.
        %i[@custom_theme_name @custom_theme_path].each do |var|
          settings.instance_variable_set(var, nil)
        end
        if settings.respond_to?(:custom_theme_name=)
          settings.custom_theme_name = nil
          settings.custom_theme_path = nil
        end
        settings.save
      end
    end
    sort_library_tree_layers!
  end

  def initialize_corrupt_settings_warning(settings_loaded)
    return unless !settings_loaded && AppConfig.settings.instance_variable_get(:@corrupt_on_load)

    current_lang = AppConfig::SETTINGS[:language]
    @popup.show(
      title: " #{AppTranslations::TRANSLATIONS[current_lang][:alert_title]} ",
      message: "#{AppTranslations::TRANSLATIONS[current_lang][:alert_config_err_msg]}.",
      type: :info
    )
  end

  def initialize_terminal_theme
    settings = AppConfig.settings
    return unless settings.theme.to_sym == :terminal

    resolver = TerminalThemeResolver.new
    terminal_colors = resolver.load_colors

    resolved = resolver.resolve(
      AppThemes::THEME_DATA[:terminal],
      AppThemes::THEME_DATA[:default]
    )

    resolved.each do |key, color|
      settings.set_theme_item(key, color)
    end
  end

  def load_app_info
    app_info_path = File.join(__dir__, 'app_info.yml')

    app_info = YAML.safe_load(
      File.read(app_info_path),
      permitted_classes: [],
      aliases: false
    ) || {}

    @app_name = app_info.fetch('app_name')
    @app_version = app_info.fetch('app_version')
    @app_copyright_year = app_info.fetch('app_copyright_year')
  end

  def load_library
    # 🎯 Retrieve the last-opened workspace directly from persistent settings.
    last_file = AppConfig.settings.last_opened_filename

    if last_file.nil? || last_file.to_s.strip.empty?
      fallback_name = defined?(@app_name) && @app_name ? "#{@app_name.to_s.downcase}.json" : "#{@app_name}.json"
      last_file = fallback_name
    end

    # =========================================================================
    # 🎯 MATCH THE STATUS BAR HANDLER (THE DEFINITIVE FIX)
    # 👉 Instead of using the unreliable 'Library.load' class loader,
    # instantiate a clean Library and call the proven '.open' method.
    # This is the same logic that works inside the app.
    # =========================================================================
    db = Library.new
    db.open(last_file) if File.exist?(last_file)
    db
  rescue StandardError
    Library.new
  end

  def initialize_empty_library
    # 1. Clear any damaged subjects array.
    @library.subjects = []

    # 2. Rebuild the required minimum hierarchy unconditionally.
    new_sub = Subject.new('Subject')
    new_src = Source.new('Source')
    new_deck = Deck.new('Deck')

    new_src.decks << new_deck
    new_sub.sources << new_src
    @library.subjects << new_sub

    # 3. 🎯 THE RECONSTRUCTION LOCK:
    # Try to open the file defensively. If opening fails or leaves the subjects array
    # completely empty, restore the default structure immediately.
    fallback_is_file = defined?(@app_name) && @app_name ? "#{@app_name.to_s.downcase}.json" : "#{@app_name}.json"

    return unless File.exist?(fallback_is_file)

    open_result = @library.open(fallback_is_file)

    # If the opened file contains corrupt JSON (StandardError) or no data at all:
    return unless open_result.is_a?(StandardError) || @library.subjects.nil? || @library.subjects.empty?

    # Remove the empty shell and restore the default structure permanently.
    @library.subjects = [new_sub]
  end

  def initialize_application_state
    @test_show_context = true
    @show_table_dividers = true
    @current_sort_col = :none
    @current_sort_dir = :asc
    @current_page = 1
    @edit_mode = false
    @search_query = ''
    @search_case_sensitive = false
    @search_regex = false
    @search_matches = []
    @search_current_match_idx = -1
    @selected_table_rows = []
    @selected_tree_paths = []

    @active_cards_cache_node = nil
    @active_cards_cache_cards = nil
    @table_visual_cache = {}
    @table_search_regex_signature = nil
    @table_search_regex_cache = nil

    @awaiting_save_confirmation = nil

    # @active_menu_keys = MenuBarView::MENU_DATA.keys # => ['App', 'File', 'Help']
    @active_menu_idx = 0
    @active_submenu_idx = 0
    @menu_dropdown_open = false
    @last_focus = :tree

    # Check whether the '--skip-startup' flag was passed through the terminal.
    if ARGV.include?('--skip-startup') || CliHandler.options[:skip_startup] == true
      @active_focus = :tree
      @last_focus   = :tree
    else
      @active_focus = :startup_screen
      @last_focus   = :startup_screen
    end

    @statusbar_field = ::RatinField.new
    @statusbar_field.placeholder = ''

    @quit_requested = false
    @beeps = true
    @command_mode_visible = false
    @library_dirty = false

    @software_cursor = SoftwareCursor.new

    @animation_tick = 0
    @rotation_indicator_countdown = 0

    @test_starting = false
    @test_start_sound = nil
    @test_start_sound_deadline = nil
  end

  def initialize_initial_selection
    first_subject = @library.subjects&.first
    first_source  = first_subject&.sources&.first
    first_deck    = first_source&.decks&.first

    # 🎯 FORCE INITIAL SAFE INTEGER STATE:
    @tree_state ||= RatatuiRuby::ListState.new(0)
    @table_state ||= RatatuiRuby::TableState.new(0)

    if first_subject && first_source && first_deck && @tree
      initialize_first_tree_selection(first_subject, first_source, first_deck)
    else
      @tree_state.select(0)
      @table_state.select(0)
      @active_focus = :tree
    end

    if ARGV.include?('--skip-startup') || (defined?(CliHandler) && CliHandler.respond_to?(:options) && CliHandler.options[:skip_startup] == true)
      @active_focus = :tree
      @last_focus   = :tree
    else
      @active_focus = :startup_screen
      @last_focus = :startup_screen
    end

    return unless @tree_state.selected.nil?

    @tree_state.select(0)
  end

  def initialize_first_tree_selection(first_subject, first_source, first_deck)
    sub_path = [first_subject.id.to_s]
    src_path = sub_path + [first_source.id.to_s]
    deck_path = src_path + [first_deck.id.to_s]

    @tree.expanded_paths ||= []
    @tree.expanded_paths << sub_path unless @tree.expanded_paths.include?(sub_path)
    @tree.expanded_paths << src_path unless @tree.expanded_paths.include?(src_path)

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    @tree.selected_path = sub_path
    @tree_state.select(0) # select_first_deck_row(deck_path)

    @current_subject_idx = 0
    @current_source_idx  = 0
    @current_deck_idx    = 0
    @active_focus = :tree
    @table_state.select(0)
  end

  def select_first_deck_row(deck_path)
    if @tree.respond_to?(:visible_nodes) && @tree.visible_nodes
      deck_row_idx = @tree.visible_nodes.index { |node| node[:path] == deck_path }
      @tree_state.select(deck_row_idx || 2)
    else
      @tree_state.select(2)
    end
  end

  def initialize_history
    return unless respond_to?(:init_history)

    init_history
    @allow_next_snapshot = true
    save_history_snapshot
  end

  def active_cards
    nodes = @tree&.visible_nodes || []
    selected_index = @tree_state&.selected || 0
    node = nodes[selected_index]

    unless node && node[:type] == :deck && node[:object]
      @active_cards_cache_node = nil
      @active_cards_cache_cards = nil
      return []
    end

    cards = node[:object].cards || []
    if @active_cards_cache_node.equal?(node[:object]) &&
       @active_cards_cache_cards.equal?(cards)
      return @active_cards_cache_cards
    end

    @active_cards_cache_node = node[:object]
    @active_cards_cache_cards = cards
  end

  def handle_two_of_a_kind_start_action
    return unless @current_study_mode == :two_of_a_kind
    return unless @two_of_a_kind_start_action_pending

    @two_of_a_kind_start_action_pending = false

    if @two_of_a_kind_waiting_for_answer
      process_two_of_a_kind_computer_question
    else
      execute_two_of_a_kind_ask_turn
    end
  end

  def terminal_check
    term_program = ENV['TERM_PROGRAM'].to_s.downcase
    term_version = ENV['TERM_PROGRAM_VERSION'].to_s

    if term_program.include?('apple_terminal')
      puts "\e[31mError:\e[0m #{@app_name} does not work in this terminal. Use a modern terminal emulator like Gostty or iTerm2."
      exit(1)
    end

    return unless term_program.include?('iterm') && term_version.empty?

    # Convert version strings safely into numerical arrays ("3.7.2" ->)
    current_version = term_version.split('.').map(&:to_i)
    minimum_required = [3, 7, 3]

    # Array comparison in Ruby evaluates element-by-element left-to-right natively
    return unless (current_version <=> minimum_required) < 0

    puts "\e[31mError:\e[0m #{@app_name} requires \e[33miTerm2 version 3.7.3\e[0m or higher."
    puts 'Reason: older versions have rendering bugs that affect pop-ups containing bidirectional (bidi) characters.'
    puts "Current detected version: #{term_version}"
    exit(1)
  end

  def run
    terminal_check

    initialize_terminal_theme

    @kitty_keyboard_enabled = false
    @mouse_capture_enabled = false
    # message = nil

    begin
      # Hide the system native cursor completely on boot
      print "\e[?25l"
      $stdout.flush

      enable_keyboard_and_mouse_capture

      RatatuiRuby.run do |tui|
        print "\e[8l" # app handles bidi, not the terminal.
        $stdout.flush

        # Consult iTerm2 BIDI support:
        # Terminals that don't support DECRQM won't reply at all, so use a timeout if you query it.
        # One caveat: the reply doesn't account for the Advanced setting that turns off reordering only in the alternate screen, so a TUI could see 1 even though nothing is being reordered there.

        # tty = File.open('/dev/tty', 'r+')
        # reply = +''

        # tty.raw do |io|
        #  io.write("\e[8$p")
        #  io.flush

        #  while IO.select([io], nil, nil, 1)
        #    reply << io.read(1)
        #    break if reply.end_with?('$y')
        #  end
        # end

        # message = case reply
        #          when "\e[8;1$y"
        #            'BIDI reordering is on (implicit mode, the default)'
        #          when "\e[8;2$y"
        #            'Bidi is turned off with \e[8l (explicit mode).' # this is replied when using iTerm2
        #          when "\e[8;4$y"
        #            "BIDI reordering can't be turned on; the escape sequence or RTL support is disabled."
        #          else
        #            "Unknown terminal reply: #{reply.inspect}"
        #         end

        # tty.puts message

        run_event_loop(tui)
      end
      # puts message
    ensure
      restore_terminal_state
    end
  end

  # 🎯 CENTRAL AUTOMATIC TIMER TICK (ACTIVE):
  # This method is called on every iteration of the run_event_loop.
  # It keeps the rotation indicator counting down smoothly.

  def handle_test_timer_tick
    return unless defined?(@rotation_indicator_countdown) && @rotation_indicator_countdown.to_i > 0

    @animation_tick ||= 0
    @animation_tick += 1
    @rotation_indicator_countdown -= 1

    return unless @rotation_indicator_countdown == 4
    return if @rotation_indicator_sound_played

    SoundManager.play(:switch) if @rotation_indicator_play_sound

    @rotation_indicator_sound_played = true
  end

  # 🎯 UNIVERSAL TRIGGER:
  def trigger_rotation_indicator
    return unless AppConfig.settings.rotation_indicator_enabled

    @rotation_indicator_countdown = 8
  end

  # 🎯 CONDITIONAL MENU BAR ROTATION INDICATOR:
  # Return the active character while the timer is running, or a blank space.
  def active_bar_rotation_indicator_symbol(force: false)
    return ' ' unless AppConfig.settings.rotation_indicator_enabled

    if !force && (!defined?(@rotation_indicator_countdown) ||
                    @rotation_indicator_countdown.to_i <= 0)
      return ' '
    end

    spin_chars = ['│', '/', '─', '\\']

    tick = if force
             (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 16).to_i
           else
             @animation_tick.to_i
           end

    spin_chars[tick % spin_chars.length]
  end

  def enable_keyboard_and_mouse_capture
    @kitty_keyboard_enabled = true
    $stdout.write("\e[>1u")
    $stdout.flush

    return unless RatatuiRuby.respond_to?(:enable_mouse_capture!)

    RatatuiRuby.enable_mouse_capture!
    @mouse_capture_enabled = true
  end

  def run_event_loop(tui)
    loop do
      handle_test_start_transition
      handle_test_timer_tick if respond_to?(:handle_test_timer_tick)
      handle_two_of_a_kind_pending_turn

      # 🎯 TRIGGER LIVE RE-RENDER TICK WHENEVER THE CURSOR TOGGLES STATE:
      # If the clock interval elapsed, it flips the visibility register and triggers
      # a clean interface update on the fly!
      if @software_cursor.update
        # Force a frame repaint event to loop the blink fluidly
        # (This is handled by your render cycle directly below)
      end

      # LIVE TIMER TICK:
      # Force a live refresh while the rotation indicator is active so it animates smoothly.
      if defined?(@rotation_indicator_countdown) && @rotation_indicator_countdown.to_i > 0
        # Keep the event loop running so it can advance the frames.
      end

      render_application(tui)

      handle_two_of_a_kind_start_action

      event = poll_application_event(tui)
      next unless event

      break if process_application_event(event)
      next if @popup.active?
    end
  end

  def render_application(tui)
    tui.draw do |frame|
      render_application_frame(tui, frame)
    end
  end

  def update_tree_visible_height(region)
    tree_region = region
    tree_inner_region = tree_region.inner(1)

    @tree_visible_height = [
      tree_inner_region.height.to_i,
      1
    ].max
  end

  def render_application_frame(tui, frame)
    frame.render_widget(RatatuiRuby::Widgets::Clear.new, frame.area)

    if @active_focus == :startup_screen
      render_startup_screen_view(tui, frame, frame.area)
      PopupView.draw(frame, @popup.active_popup, tui) if @popup.active? && !@popup.active_popup.nil?
      return
    end

    top_region, middle_region, bottom_region = tui.layout_split(
      frame.area,
      direction: :vertical,
      constraints: [
        tui.constraint(:length, 3),
        tui.constraint(:min, 1),
        tui.constraint(:length, 3)
      ]
    )

    draw_main_interface(tui, frame)
    update_tree_visible_height(middle_region)
    draw_bottom_region(tui, frame, bottom_region)

    if defined?(@current_study_mode) && @current_study_mode
      render_study_mode(tui, frame)
    else
      render_normal_mode(tui, frame, top_region, middle_region)
    end

    PopupView.draw(frame, @popup.active_popup, tui) if @popup.active? && !@popup.active_popup.nil?
  end

  def render_study_mode(tui, frame)
    study_canvas_height = frame.area.height - 3
    study_canvas_region = RatatuiRuby::Layout::Rect.new(0, 0, frame.area.width, study_canvas_height)
    study_title = study_mode_title

    is_popup_active = defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?

    title_style = if is_popup_active
                    { fg: AppConfig.settings.theme_item(:window_title),
                      bg: AppConfig.settings.theme_item(:background),
                      modifiers: [:dim] }
                  else
                    { fg: AppConfig.settings.theme_item(:window_title),
                      bg: AppConfig.settings.theme_item(:background) }
                  end

    border_style = if is_popup_active
                     { fg: AppConfig.settings.theme_item(:window_border),
                       bg: AppConfig.settings.theme_item(:background),
                       modifiers: [:dim] }
                   else
                     { fg: AppConfig.settings.theme_item(:window_border),
                       bg: AppConfig.settings.theme_item(:background) }
                   end

    study_block = tui.block(
      title: " #{study_title} ",
      title_style: title_style,
      border_style: border_style,
      style: { bg: AppConfig.settings.theme_item(:background) },
      borders: [:all],
      border_type: AppConfig.settings.corner
    )

    study_inner_region = study_block.inner(study_canvas_region) if study_block.respond_to?(:inner)
    study_inner_region ||= study_canvas_region
    frame.render_widget(study_block, study_canvas_region)

    # 🎯 RESTORED: Do not apply an outer dim_block here.
    # This keeps the uniform background beneath the popup fully opaque.

    render_study_content(tui, frame, study_inner_region)
  end

  def study_mode_title
    settings = AppConfig.settings
    case @current_study_mode
    when :drill then settings.language_string(:study_drill_title)
    when :quiz then settings.language_string(:study_quiz_title)
    when :multiple_choice then settings.language_string(:study_multiple_choice_title)
    when :memory then settings.language_string(:study_play_memory_title)
    when :two_of_a_kind then settings.language_string(:study_play_two_of_a_kind_title)
    end
  end

  def render_study_content(tui, frame, region)
    settings = AppConfig.settings
    if @test_starting
      render_test_status_screen(
        tui,
        frame,
        region,
        @test_start_countdown.to_s,
        [
          @current_study_mode == :quiz ? settings.language_string(:study_status_screen_quiz) : settings.language_string(:study_status_screen_multiple_choice),
          "#{settings.language_string(:statusbar_test_about_to_begin)}…",
          "#{settings.language_string(:statusbar_good_luck)}!"
        ]
      )

      return
    end

    case @current_study_mode
    when :drill
      render_drill_view(tui, frame, region) if respond_to?(:render_drill_view, true)
    when :quiz
      render_quiz_view(tui, frame, region) if respond_to?(:render_quiz_view, true)
    when :multiple_choice
      render_multiple_choice_view(tui, frame, region) if respond_to?(:render_multiple_choice_view, true)
    when :memory
      render_memory_view(tui, frame, region) if respond_to?(:render_memory_view, true)
    when :two_of_a_kind
      render_two_of_a_kind_view(tui, frame, region) if respond_to?(:render_two_of_a_kind_view, true)
    end
  end

  def render_normal_mode(tui, frame, top_region, middle_region)
    middle_left_region, _middle_buffer_region, middle_right_region = tui.layout_split(
      middle_region,
      direction: :horizontal,
      constraints: [
        tui.constraint(:percentage, 25),
        tui.constraint(:length, 1),
        tui.constraint(:percentage, 75)
      ]
    )

    draw_top_region(tui, frame, top_region)
    draw_middle_left_region(tui, frame, middle_left_region)
    draw_middle_right_region(tui, frame, middle_right_region)
  end

  def two_of_a_kind_draw_animation_active?
    return false unless @current_study_mode == :two_of_a_kind
    return false unless @two_of_a_kind_draw_animation_until

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    now < @two_of_a_kind_draw_animation_until
  end

  def handle_two_of_a_kind_pending_turn
    return unless @current_study_mode == :two_of_a_kind
    return if @two_of_a_kind_game_over
    return if @two_of_a_kind_waiting_for_answer

    # Wait for the current draw animation to finish.
    if @two_of_a_kind_draw_animation_until
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if now < @two_of_a_kind_draw_animation_until

      @two_of_a_kind_draw_animation_until = nil
      @two_of_a_kind_draw_animation_player = nil
    end

    @two_of_a_kind_pending_refills ||= []

    # Handle all required draws first.
    until @two_of_a_kind_pending_refills.empty?
      player = @two_of_a_kind_pending_refills.shift

      hand = player == :user ? @user_hand : @computer_hand

      next unless hand.empty?
      next if @two_of_a_kind_deck.empty?

      draw_card_and_check_pairs(hand, player)

      # log_two_of_a_kind_state(
      #  'AANVULLING AFGEROND',
      #  speler: player,
      #  beurt_behouden_door: @two_of_a_kind_active_player
      # )

      # Continue drawing if the card immediately forms a pair.
      queue_two_of_a_kind_empty_hand(hand, player)

      update_two_of_a_kind_header_and_context
      check_two_of_a_kind_game_over
      return
    end

    # The computer may start only when it is actually its turn.
    return unless @two_of_a_kind_computer_turn_pending
    return unless @two_of_a_kind_active_player == :computer

    execute_two_of_a_kind_computer_turn
  end

  def poll_application_event(tui)
    is_study_session_running = defined?(@current_study_mode) && %i[drill quiz multiple_choice
                                                                   memory two_of_a_kind].include?(@current_study_mode)

    is_input_active = %i[command_mode popup].include?(@active_focus) || (defined?(@popup) && @popup&.active?)

    if two_of_a_kind_draw_animation_active?
      # Render again every 40 ms while the timer is running.
      tui.poll_event(timeout: 0.04)
    elsif is_input_active || (defined?(@rotation_indicator_countdown) && @rotation_indicator_countdown.to_i > 0)
      # Poll at a 0.1-second fractional tick rate. This forces the loop to check
      # your SoftwareCursor monotonic clock continuously, rendering a perfectly
      # smooth, fluid 0.5-second blink cycle without delaying user keystrokes!
      tui.poll_event(timeout: 0.05)
    elsif is_study_session_running
      # High-speed clock tick: Refresh unconditionally every 1.0 second for the stopwatch
      tui.poll_event(timeout: 1.0)
    else
      # Idle energy-saving state (Library-tree/table): drop back to hours anchor
      current_timeout = @status_message ? 0.1 : 0.2
      tui.poll_event(timeout: current_timeout)
    end
  end

  def process_application_event(event)
    case event
    in { type: :key, code: key_code, modifiers: raw_mods }
      _consumed = process_key_input(
        key_code,
        Array(raw_mods).map(&:to_s)
      )

      if quit_requested?
        AppConfig.settings.save
        true
      else
        false
      end

    in { type: :key, code: key_code }
      _consumed = process_key_input(key_code, [])

      if quit_requested?
        AppConfig.settings.save
        true
      else
        false
      end

    else
      false
    end
  end

  def quit_requested?
    @quit_requested == true
  end

  def locked_input_session?
    has_table_search = @search_matches && @search_matches.any?
    has_tree_search = defined?(@tree_search_matches) && @tree_search_matches && @tree_search_matches.any?
    is_replace_mode = (@active_focus == :replace_mode) ||
                      (defined?(@interactively_replacing) && @interactively_replacing == true)
    is_study_focus = (@active_focus == :study_focus_mode)

    has_table_search || has_tree_search || is_replace_mode || is_study_focus
  end

  def handle_test_start_transition
    return unless @test_starting
    return unless @test_start_countdown_deadline

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    return if now < @test_start_countdown_deadline

    @test_start_countdown -= 1

    if @test_start_countdown <= 0
      # The countdown has ended; also wait for the sound to finish.
      return if @test_start_sound_deadline && now < @test_start_sound_deadline

      @test_last_tick_time = now

      @test_start_sound = nil
      @test_start_sound_deadline = nil
      @test_start_countdown_deadline = nil
      @test_starting = false
    else
      @test_start_countdown_deadline = now + 1.0
    end
  end

  def restore_terminal_state
    RatatuiRuby.disable_mouse_capture! if @mouse_capture_enabled && RatatuiRuby.respond_to?(:disable_mouse_capture!)
  rescue StandardError => e
    warn "\e[31mMouse cleanup failed:\e[0m #{e.message}"
  ensure
    sequences = +''

    # =========================================================================
    # 🎯 FINAL RESIZE CLEANUP
    # 👉 \e[2J clears the active screen.
    # 👉 \e[3J clears the terminal's entire scrollback buffer (iTerm2-safe!).
    # 👉 \e[H moves the cursor back to the top-left corner at position 0,0.
    # =========================================================================
    # sequences << "\e[2J\e[3J\e[H"

    sequences << "\e[<u" if @kitty_keyboard_enabled
    # Restore iTerm2/terminal settings.
    sequences << "\e[8h" # bidi-herordening bij afsluiten herstellen: terminal handles bidi, not the app
    # sequences << "\e[?2004l"  # Bracketed paste was not enabled here, so do not disable it unconditionally.
    # sequences << "\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1015l" # RatatuiRuby enables/disables mouse tracking. Use disable_mouse_capture! instead of unconditional reset sequences.
    # # 112 resets the cursor color to its default; it does not necessarily restore the color used before the app.
    # sequences << "\e]112\a"
    # Reset styles and make the cursor visible again.
    sequences << "\e[0m\e[?25h"

    $stdout.write(sequences)
    $stdout.flush

    @mouse_capture_enabled = false
    @kitty_keyboard_enabled = false
  end
end

# Start app
App = RatatuiRubyApp.new
App.run
