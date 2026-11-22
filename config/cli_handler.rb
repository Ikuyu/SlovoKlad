require 'fileutils'
require 'optparse'
require 'yaml'
require 'ffi'
require_relative '../lib/ratin_field'

module CliHandler
  def self.options
    @options || {}
  end

  def self.handle_arguments
    # Read metadata and build the options and parser outside the main procedure.
    load_cli_app_info
    @options = default_options
    options = @options

    parser = build_option_parser(options)
    parse_cli_arguments!(parser)

    # Flexibele controle: alleen verplicht voor say/espeak, elders is {text} voldoende
    cmd = options[:speech_command].to_s
    unless cmd.empty?
      if cmd.include?('say') || cmd.include?('espeak')
        unless cmd.include?('{text}') && cmd.include?('{voice}')
          warn "\e[31mError:\e[0m Speech template for 'say' or 'espeak' must include both {text} and {voice}."
          exit(1)
        end
      else
        unless cmd.include?('{text}')
          warn "\e[31mError:\e[0m Speech template must include at least {text}."
          exit(1)
        end
      end
    end

    if options[:speech_command].to_s.empty? != options[:speech_voice].to_s.empty?
      warn "\e[31mError:\e[0m --speech-command and --speech-voice must be used together."
      puts "Type '#{@app_name} --help' for usage."
      exit(1)
    end

    target_file, options[:csv_files] = extract_target_file_and_csv_files(ARGV)

    # Determine whether a data action was requested and check for the required filename.
    has_data_action = data_action_requested?(options)
    validate_data_action_target!(has_data_action, target_file)

    validate_import_library_argument!(options, target_file) unless options[:import_apkg]

    # Validate an existing library file before the TUI or a data action starts.
    validate_existing_library_file!(target_file)

    if has_data_action
      execute_data_action(options, target_file)
      exit(0)
    end

    # If no terminal action was requested, return the filename to app.rb for the TUI.
    target_file
  end

  # Initialiseert alle CLI-opties op hun standaardwaarde.
  private_class_method def self.default_options
    {
      export: nil,
      reset: false,
      dedup: false,
      tree: false,
      import: false,
      import_to: nil,
      import_to_deck: nil,
      import_apkg: false,
      apkg_path: nil,
      skip_startup: false,
      speech_command: nil,
      speech_voice: nil,
      speech_lang: nil
    }
  end

  # Build the option parser from the metadata and shared options hash.
  private_class_method def self.build_option_parser(options)
    banner_text = <<~HEREDOC
      #{@app_name} [OPTIONS] [FILE]

      Usage:
        #{@app_name} [FILE]
            Open a library file.

        #{@app_name} --import-apkg APKG_FILE FILE
            Import an Anki package (.apkg) directly into FILE, rebuilding hierarchies.

        #{@app_name} --import CSV... FILE
            Import CSV files into a new Source in FILE.

        #{@app_name} --import-to INDEX CSV... FILE
            Import CSV files into an existing Source in FILE.

        #{@app_name} --import-to-deck INDEX CSV... FILE
            Import CSV files into an existing Deck in FILE.

      Options:

    HEREDOC

    OptionParser.new do |opts|
      opts.banner = banner_text
      opts.summary_width = 28

      opts.on('-v', '--version', 'Show version and website information') do
        puts "#{@app_name} v#{@app_version}"
        puts "Website: https://github.com/Ikuyu/#{@app_name}"
        exit(0)
      end

      opts.on('-a', '--about', 'Show application and author information') do
        puts <<~ABOUT
          #{@app_name} – TUI dashboard study aid
          Version #{@app_version}

          Built with Ruby #{@ruby_version}
          Powered by Ratatui Ruby #{@ratatui_ruby_version}

          Copyright (c) #{@app_copyright_year} Edwin H. Jonkvorst.
          All rights reserved.
        ABOUT
        exit(0)
      end

      opts.on('-h', '--help', 'Show this help message') do
        puts opts
        puts <<~FORMATS

          Formats:
              csv                          Comma-separated values
              xml                          Extensible Markup Language
        FORMATS
        exit(0)
      end

      opts.on('-s', '--skip-startup', 'Skip startup screen') do
        options[:skip_startup] = true
      end

      opts.on('--speech-command COMMAND',
              'Speech command template using {text} (and optionally {voice} for say/espeak)') do |command|
        options[:speech_command] = command
      end

      opts.on('--speech-voice VOICE', 'Name of the voice to use') do |voice|
        options[:speech_voice] = voice
      end

      opts.on('--speech-lang LANG', 'Speech language code (e.g. ru, en, nl)') do |lang|
        options[:speech_lang] = lang
      end

      opts.on('-t', '--tree', 'Print the library tree with Source and Deck indices') do
        options[:tree] = true
      end

      opts.on('-i', '--import', 'Import CSV files into a new Subject/Source/Deck hierarchy') do
        options[:import] = true
      end

      opts.on('--import-to INDEX', 'Import CSV files into an existing Source') do |index|
        options[:import] = true
        options[:import_to] = index.to_s.strip
      end

      opts.on('--import-to-deck INDEX', 'Import CSV files into an existing Deck') do |index|
        options[:import] = true
        options[:import_to_deck] = index.to_s.strip
      end

      opts.on('--import-apkg FILE', 'Import an Anki package (.apkg file)') do |file|
        options[:import_apkg] = true
        options[:apkg_path] = File.expand_path(file.to_s.strip.gsub(/["']/, ''), Dir.pwd)
      end

      opts.on('-e', '--export FORMAT', %w[csv xml], 'Export FILE as CSV or XML') do |format|
        options[:export] = format.downcase
      end

      opts.on('-r', '--reset', 'Reset FILE') do
        options[:reset] = true
      end

      opts.on('-d', '--dedup', 'Remove duplicate entries from FILE') do
        options[:dedup] = true
      end
    end
  end

  # Parse ARGV and show the existing error message for invalid CLI options.
  private_class_method def self.parse_cli_arguments!(parser)
    parser.parse!(ARGV)
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument, OptionParser::InvalidArgument => e
    warn "\e[31mError:\e[0m #{e.message}"
    puts "Type '#{@app_name} --help' for usage."
    exit(1)
  end

  # Treat the last argument as the library file and keep earlier arguments as CSV paths.
  private_class_method def self.extract_target_file_and_csv_files(argv)
    # Remove empty arguments and whitespace so shell wildcards are handled cleanly.
    remaining_args = argv.map(&:to_s).map(&:strip).reject(&:empty?)
    raw_target = remaining_args.pop.to_s.strip

    [normalize_target_file(raw_target), remaining_args]
  end

  # Normalize the filename, append .json if needed, and resolve the path from the working directory.
  private_class_method def self.normalize_target_file(raw_target)
    return '' if raw_target.empty?

    # Remove quotation marks that may have been included in the filename by mistake.
    clean_target = raw_target.gsub(/["']/, '')
    clean_target = "#{clean_target}.json" if File.extname(clean_target).empty?

    File.expand_path(clean_target, Dir.pwd)
  end

  # Return whether a CLI option requests a data action.
  private_class_method def self.data_action_requested?(options)
    options[:export] ||
      options[:reset] ||
      options[:dedup] ||
      options[:tree] ||
      options[:import] ||
      options[:import_to] ||
      options[:import_to_deck] ||
      options[:import_apkg]
  end

  private_class_method def self.validate_import_library_argument!(options, target_file)
    # 🎯 FIREWALL: Skip this CSV check immediately for an APKG import!
    return if options[:import_apkg]

    import_requested =
      options[:import] || options[:import_to] || options[:import_to_deck]

    return unless import_requested
    return if target_file.empty?
    return unless File.extname(target_file).casecmp('.csv').zero?

    warn "\e[31mError:\e[0m Library FILE argument is required for imports."
    puts "Usage: #{@app_name} [OPTIONS] CSV... FILE"
    exit(1)
  end

  # Stop with the existing error message if a data action has no target file.
  private_class_method def self.validate_data_action_target!(has_data_action, target_file)
    return unless has_data_action && target_file.empty?

    warn "\e[31mError:\e[0m FILE argument is required when performing data actions."
    puts "Usage: #{@app_name} [OPTIONS] [FILE]"
    exit(1)
  end

  private_class_method def self.prepare_data_action_library(options, target_file)
    db = Library.new([])

    target_directory = File.dirname(target_file)
    base_name = File.basename(target_file)

    if File.exist?(target_file)
      open_result = db.open(target_file)
      if open_result.is_a?(StandardError)
        # 🎯 FIX: Always mask the cryptic JSON error here as well.
        error_msg = if File.zero?(target_file) || open_result.message.include?('end of input')
                      'Empty data file (0 bytes).'
                    else
                      open_result.message
                    end

        warn "\e[31mError:\e[0m #{error_msg}."
        exit(1)
      end
    elsif options[:import] || options[:import_to]
      FileUtils.mkdir_p(target_directory) unless Dir.exist?(target_directory)
      puts "\e[34mNote:\e[0m Creating \"#{base_name}\"."
    else
      warn "\e[31mError:\e[0m File not found: #{base_name}"
      exit(1)
    end

    db
  end

  # Validate an existing library file and stop immediately if its JSON content is invalid.
  private_class_method def self.validate_existing_library_file!(target_file)
    return if target_file.empty? || !File.exist?(target_file)

    test_db = Library.new
    check_result = test_db.open(target_file)
    return unless check_result.is_a?(StandardError)

    # 🎯 FIX: Provide a clear English description for an empty file.
    error_msg = if File.zero?(target_file) || check_result.message.include?('end of input')
                  'Empty data file (0 bytes).'
                else
                  check_result.message
                end

    warn "\e[31mError:\e[0m #{error_msg}"
    exit(1)
  end

  # Prepare the library: load an existing file or create the import map.
  private_class_method def self.prepare_data_action_library(options, target_file)
    db = Library.new([])

    # UPDATED: Determine these values before the branches
    # so base_name is also available in the error message.
    target_directory = File.dirname(target_file)
    base_name = File.basename(target_file)

    if File.exist?(target_file)
      # Load the existing library and preserve the current error handling.
      open_result = db.open(target_file)
      if open_result.is_a?(StandardError)
        warn "\e[31mError:\e[0m #{open_result.message}."
        exit(1)
      end
    elsif options[:import] || options[:import_to]
      FileUtils.mkdir_p(target_directory) unless Dir.exist?(target_directory)
      puts "\e[34mNote:\e[0m Creating \"#{base_name}\"."
    else
      warn "\e[31mError:\e[0m File not found: #{base_name}."
      exit(1)
    end

    db
  end

  private_class_method def self.execute_data_action(options, target_file)
    db = prepare_data_action_library(options, target_file)

    # Display the tree separately so the main handler can manage the action choice.
    if options[:tree]
      print_library_tree(db)
      exit(0)
    end

    if options[:import] || options[:import_to] || options[:import_to_deck]
      execute_import_action(options, db, target_file)
      exit(0)
    end

    if options[:import_apkg]
      execute_apkg_import_action(options, db, target_file)
      exit(0)
    end

    # Run the export only when the user supplied the export argument.
    execute_export_action(options, db, target_file) if options[:export]

    # Keep the reset logic outside the central dispatcher.
    execute_reset_action(db, target_file) if options[:reset]

    # Deduplication is the final data task; stop if this option was not selected.
    return unless options[:dedup]

    execute_dedup_action(db, target_file)
  end

  private_class_method def self.execute_apkg_import_action(options, db, target_file)
    apkg_file = options[:apkg_path]

    if apkg_file.nil? || apkg_file.empty?
      warn "\e[31mError:\e[0m APKG file path is required. Use --import-apkg FILE."
      exit(1)
    elsif !File.file?(apkg_file)
      warn "\e[31mError:\e[0m The specified APKG file was not found: #{apkg_file}"
      exit(1)
    end

    result = db.import_apkg(apkg_file)

    if result.is_a?(StandardError)
      warn "\e[31mError parsing APKG:\e[0m #{result.message}"
      exit(1)
    else
      cards_imported, decks_imported = result

      if cards_imported.to_i.positive?
        db.save(target_file)

        # 🎯 FIXED: The 'into X decks' phrasing has now been added correctly.
        puts "\e[32mSuccess:\e[0m #{cards_imported} cards successfully imported into #{decks_imported} decks inside \"#{File.basename(target_file)}\"."
      else
        warn "\e[33mWarning:\e[0m No valid flashcard definitions extracted from package."
      end
    end
  end

  # Find an existing deck by the index displayed by print_library_tree.
  private_class_method def self.resolve_import_target_deck(target_input, db)
    unless target_input.to_s.match?(/\A\d+\z/) && target_input.to_i.positive?
      warn "\e[31mError:\e[0m Invalid Deck index: #{target_input}"
      exit(1)
    end

    target_idx = target_input.to_i
    current_idx = 0

    db.subjects.each do |subject|
      subject.sources.each do |source|
        source.decks.each do |deck|
          current_idx += 1
          return deck if current_idx == target_idx
        end
      end
    end

    warn "\e[31mError:\e[0m Deck index [#{target_idx}] not found in library tree."
    exit(1)
  end

  # Coordinate CSV import: find files, determine the target Source, import, and save.
  private_class_method def self.execute_import_action(options, db, target_file)
    target_deck = nil
    target_source = nil

    if options[:import_to_deck]
      target_deck =
        resolve_import_target_deck(options[:import_to_deck], db)
    elsif options[:import_to]
      # This index validation does not use the CSV list.
      target_source =
        resolve_import_target_source(options[:import_to], [], db)
    end

    raw_csv_list = options[:csv_files] || []
    if raw_csv_list.empty?
      warn "\e[31mError:\e[0m No CSV file(s) found or specified for import."
      exit(1)
    end

    csv_list = expand_import_csv_list(raw_csv_list)

    if options[:import_to_deck]
      target_subject = db.subjects.find do |subject|
        subject.sources.any? do |source|
          source.decks.any? { |deck| deck.equal?(target_deck) }
        end
      end

      unless target_subject
        warn "\e[31mError:\e[0m Could not find the Subject for the import Deck."
        exit(1)
      end

      target_source = target_subject.sources.find do |source|
        source.decks.any? { |deck| deck.equal?(target_deck) }
      end

      unless target_source
        warn "\e[31mError:\e[0m Could not find the Source for the import Deck."
        exit(1)
      end

      total_cards_imported =
        import_csv_files_into_deck(csv_list, target_deck)

      puts "\e[32mSuccess:\e[0m #{total_cards_imported} cards successfully imported into: " \
           "#{target_subject.name} > #{target_source.name} > #{target_deck.name}"

      save_imported_library(db, target_file, total_cards_imported)
      return
    end

    # Keep the existing Source route; use the Source found earlier.
    target_source ||= resolve_import_target_source(options[:import_to], csv_list, db)

    target_subject = db.subjects.find do |subject|
      subject.sources.any? { |source| source.equal?(target_source) }
    end

    unless target_subject
      warn "\e[31mError:\e[0m Could not find the Subject for the import Source."
      exit(1)
    end

    total_cards_imported, decks_imported =
      import_csv_files(csv_list, target_source)

    report_import_results(
      db,
      target_file,
      total_cards_imported,
      decks_imported
    )
  end

  private_class_method def self.import_csv_files_into_deck(csv_list, target_deck)
    total_cards_imported = 0

    csv_list.each do |csv_file|
      next unless File.exist?(csv_file)

      result = target_deck.import_csv(csv_file)

      if result.is_a?(StandardError)
        warn "\e[31mError processing #{csv_file}:\e[0m #{result.message}"
      else
        total_cards_imported += result.to_i
      end
    end

    total_cards_imported
  end

  private_class_method def self.save_imported_library(db, target_file, total_cards_imported)
    if total_cards_imported.positive?
      save_result = db.save(target_file)

      if save_result.is_a?(StandardError)
        warn "\e[31mError writing \"#{File.basename(target_file)}\":\e[0m #{save_result.message}"
        exit(1)
      end
    else
      warn "\e[33mWarning:\e[0m Invalid records found inside the CSV files."
    end
  end

  private_class_method def self.expand_import_csv_list(raw_csv_list)
    csv_list = []
    unmatched = []

    raw_csv_list.each do |path|
      matches = Dir.glob(path)
      unmatched << path if matches.empty?
      csv_list.concat(matches)
    end

    csv_list.uniq!
    csv_list.sort_by! do |path|
      path.to_s.downcase.gsub(/\d+/) do |digits|
        digits.to_i.to_s.rjust(6, '0')
      end
    end

    if csv_list.empty?
      warn "\e[31mError:\e[0m No matching CSV files found at path: #{raw_csv_list.join(', ')}"
      exit(1)
    end

    # Show warnings only if CSV files were found.
    unmatched.each do |path|
      warn "\e[33mWarning:\e[0m No matching CSV file: #{File.basename(path)}"
    end

    csv_list
  end

  # Choose an existing Source by index or create a new Subject/Source pair.
  private_class_method def self.resolve_import_target_source(target_input, csv_list, db)
    input = target_input.to_s.strip

    if input.empty?
      # Take the first valid CSV file from the list.
      first_valid_file = csv_list.find { |file| File.exist?(file) }

      if first_valid_file
        # Get the absolute path of the folder containing the CSV.
        absolute_dir_path = File.dirname(File.absolute_path(first_valid_file))

        # 'Turkish' (the subfolder) remains the parent SUBJECT.
        subject_name = File.basename(absolute_dir_path).to_s.strip.capitalize
      else
        subject_name = 'New Subject'
      end

      subject_name = 'New Subject' if subject_name.empty? || subject_name.include?('*')

      # 🎯 FIX: The source name is now always set to "CSV".
      source_name = 'CSV'

      # Check whether this Subject already exists in the database.
      existing_subject = db.subjects.find { |sub| sub.name.to_s.downcase == subject_name.downcase }

      if existing_subject
        # The Subject already exists; create only the new Source inside it.
        target_source = Source.new(source_name, [])
        existing_subject.sources << target_source
        return target_source
      else
        # New branch: create both the Subject and the Source.
        new_subject = Subject.new(subject_name, [])
        target_source = Source.new(source_name, [])
        new_subject.sources << target_source
        db.subjects << new_subject
        return target_source
      end
    end

    unless input.match?(/\A\d+\z/) && input.to_i.positive?
      warn "\e[31mError:\e[0m Invalid Source index: #{input}"
      exit(1)
    end

    target_idx = input.to_i
    current_idx = 0

    db.subjects.each do |subject|
      subject.sources.each do |source|
        current_idx += 1
        return source if current_idx == target_idx
      end
    end

    warn "\e[31mError:\e[0m Source index [#{target_idx}] not found in library tree."
    exit(1)
  end

  # Import CSV files as sequential Imported decks and return the totals.
  private_class_method def self.import_csv_files(csv_list, target_source)
    total_cards_imported = 0
    decks_imported = 0

    # Continue after the highest existing Imported number to avoid repeating names.
    existing_numbers = target_source.decks.map do |deck|
      deck.name.to_s.match(/\AImported\s+(\d+)\z/i) { |match| match[1].to_i }
    end.compact
    next_deck_number = existing_numbers.any? ? existing_numbers.max + 1 : 1

    csv_list.each do |csv_file|
      next unless File.exist?(csv_file)

      new_deck = Deck.new("Imported #{next_deck_number}", [])
      import_count = new_deck.import_csv(csv_file)

      if import_count.is_a?(StandardError)
        warn "\e[31mError processing #{csv_file}:\e[0m #{import_count.message}"
      elsif import_count.to_i > 0
        target_source.decks << new_deck
        decks_imported += 1
        next_deck_number += 1
        total_cards_imported += import_count.to_i
      end
    end

    [total_cards_imported, decks_imported]
  end

  # Save the library after successful imports and show the result to the user.
  private_class_method def self.report_import_results(db, target_file, total_cards_imported, decks_imported)
    base_name = File.basename(target_file)
    if total_cards_imported > 0
      save_result = db.save(target_file)
      if save_result.is_a?(StandardError)
        warn "\e[31mError writing \"#{base_name}\":\e[0m #{save_result.message}"
        exit(1)
      end

      puts "\e[32mSuccess:\e[0m #{decks_imported} decks (#{total_cards_imported} cards) successfully imported into \"#{base_name}\"."
    else
      warn "\e[33mWarning:\e[0m Invalid records found inside the CSV files."
    end
  end

  # Print the subject, source, and deck structure with continuous Source indices.
  private_class_method def self.print_library_tree(db)
    source_index = 0
    deck_index = 0

    cli_text = lambda do |value|
      text = value.to_s
      next text if text.empty?

      # Use the same FriBidi layout as the TUI.
      # Store the grapheme clusters in visual order.
      RatinField.app_visual_layout(text)
                .map { |item| item[:char] }
                .join
    end

    # Let the application manage the bidi order.
    $stdout.write("\e[8l")
    $stdout.flush

    begin
      db.subjects.each do |subject|
        puts "\e[1;35mSubject:\e[0m #{cli_text.call(subject.name)}"

        subject.sources.each do |source|
          source_index += 1

          puts "   \e[2m[#{source_index}]\e[0m " \
               "\e[0;33mSource:\e[0m #{cli_text.call(source.name)}"

          source.decks.each do |deck|
            deck_index += 1
            card_count = deck.cards ? deck.cards.length : 0

            puts "     \e[2m[#{deck_index}]\e[0m " \
                 "\e[0;32mDeck:\e[0m #{cli_text.call(deck.name)} " \
                 "\e[2m(#{card_count} cards)\e[0m"
          end
        end
      end
    ensure
      # Restore the terminal bidi processing.
      $stdout.write("\e[8h")
      $stdout.flush
    end
  end

  # Export the archive and report an error or the name of the created archive.
  private_class_method def self.execute_export_action(options, db, target_file)
    result = db.execute_tar_bulk_export(options[:export], true, '')
    base_name = File.basename(target_file)
    if result.is_a?(StandardError)
      warn "\e[31mError:\e[0m Could not export \"#{base_name}\": #{result.message}" # TODO
      exit(1)
    else
      archive_name = File.basename(result[:archive_path] || "#{base_name}.tar.gz")
      puts "\e[32mSuccess:\e[0m Exported: #{archive_name}"
    end
  end

  # Reset all decks and count only cards recorded as memorized.
  private_class_method def self.execute_reset_action(db, target_file)
    total_reset_cards = 0
    any_deck_found = false

    db.subjects.each do |subject|
      next if subject.sources.nil?

      subject.sources.each do |source|
        next if source.decks.nil?

        source.decks.each do |deck|
          next if deck.cards.nil? || deck.cards.empty?

          any_deck_found = true
          deck.cards.each do |card|
            next unless card.respond_to?(:study)

            val = card.study
            is_memorized = val == false || val.to_s.strip.downcase == 'false' || val == :false
            total_reset_cards += 1 if is_memorized
          end

          # Use the existing deck reset to actually reset the cards.
          deck.reset
        end
      end
    end

    if !any_deck_found || total_reset_cards.zero?
      warn "\e[33mWarning:\e[0m Nothing to reset."
    else
      db.save(target_file)
      puts "\e[32mSuccess:\e[0m Reset #{total_reset_cards} card(s)."
    end
  end

  # Remove duplicates per deck and save the library only if something changed.
  private_class_method def self.execute_dedup_action(db, target_file)
    total_duplicates_removed = 0

    db.subjects.each do |subject|
      next if subject.sources.nil?

      subject.sources.each do |source|
        next if source.decks.nil?

        source.decks.each do |deck|
          total_duplicates_removed += deck.remove_duplicates! if deck.cards && deck.respond_to?(:remove_duplicates!)
        end
      end
    end

    if total_duplicates_removed.zero?
      warn "\e[33mWarning:\e[0m No duplicates found."
    else
      db.save(target_file)
      puts "\e[32mSuccess:\e[0m Removed #{total_duplicates_removed} duplicate(s)."
    end
  end

  # Leest optionele applicatiemetadata en b उद्योग kogelvrij in module-instantievariabelen
  private_class_method def self.load_cli_app_info
    app_info_path = File.join(__dir__, '..', 'app_info.yml')

    app_info = YAML.safe_load(
      File.read(app_info_path),
      permitted_classes: [],
      aliases: false
    ) || {}

    @app_name           = app_info.fetch('app_name')
    @app_version        = app_info.fetch('app_version')
    @app_copyright_year = app_info.fetch('app_copyright_year')

    @ruby_version = RUBY_VERSION
    @ratatui_ruby_version = Gem.loaded_specs.fetch('ratatui_ruby').version.to_s

    app_info
  end
end
