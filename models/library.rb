require 'csv'
require 'zip'
require 'sqlite3'
require 'json'
require 'securerandom'
require 'rexml/document'
require 'fileutils'
require 'tmpdir'
require 'cgi'
require 'set'
require 'shellwords' # Veiligheidsgrendel voor mappen met spaties op de Mac

module Mode
  ALL_MODES = [
    # :fronts_sorted,                       # Show fronts first, sorted on term
    :fronts_random, # Show fronts first, shuffled cards
    # :backs_sorted,                        # Show backs first, sorted on term
    :backs_random, # Show backs first, shuffled cards
    # :alternately_fronts_and_backs_sorted, # Alternately front/back, sorted on term
    :alternately_fronts_and_backs_random, # Alternately front/back, shuffled cards
    :everything_random # Randomly show fronts and backs, shuffled cards
  ].freeze
end

class Library
  attr_accessor :subjects

  def initialize(subjects = [])
    @subjects = subjects # '@' means: instance variable; no need for 'self'
    @last_opened_filename = nil # Start als nil
  end

  def inspect_db
    @subjects.each do |subject|
      puts subject.name
      subject.sources.each do |source|
        puts " #{source.name}"
        source.decks.each do |deck|
          puts "  #{deck.name}"
          deck.cards.each do |card|
            puts "   #{card.study} #{card.term} #{card.context} #{card.meaning}"
          end
        end
      end
    end
  end

  def sort!
    return if @subjects.nil? || @subjects.empty?

    # 1. Sort the parent Subject array
    @subjects.sort_by! { |sub| sub.name.to_s.downcase }

    # 2. Sort child Sources and nested Decks
    @subjects.each do |subject|
      next if subject.sources.nil?

      subject.sources.sort_by! { |src| src.name.to_s.downcase }

      subject.sources.each do |source|
        next if source.decks.nil?

        source.decks.sort_by! { |deck| deck.name.to_s.downcase }
      end
    end
    true
  end

  def save(filename = nil)
    target_file = filename || AppConfig.settings.last_opened_filename

    return false if target_file.nil? || target_file.empty?

    data = {
      subjects: @subjects.map do |sub|
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
                      next_review_at: card.next_review_at.to_s
                    }
                  end
                }
              end
            }
          end
        }
      end
    }

    File.write(
      target_file,
      JSON.pretty_generate(data),
      encoding: 'utf-8'
    )

    true
  rescue StandardError => e
    e
  end

  def open(filename)
    settings = AppConfig.settings
    file_content = File.read(filename, encoding: 'utf-8')
    raw_data = JSON.parse(file_content)

    settings.last_opened_filename = filename
    settings.save

    @subjects = [] # Clear library; clear the subjects instance variable

    subjects_data = raw_data['subjects'] || []
    subjects_data.each do |sub_hash|
      subject = Subject.new(sub_hash['name'] || '')
      subject.id = sub_hash['id'] || subject.id
      subject.sources = []

      (sub_hash['sources'] || []).each do |source_hash|
        source = Source.new(source_hash['name'] || '')
        source.id = source_hash['id'] || source.id
        source.decks = []

        (source_hash['decks'] || []).each do |deck_hash|
          deck = Deck.new(deck_hash['name'] || '')
          deck.id = deck_hash['id'] || deck.id
          deck.cards = []

          (deck_hash['cards'] || []).each do |card_hash|
            card = Card.new(
              card_hash['term'] || '',
              card_hash['context'] || '',
              card_hash['meaning'] || ''
            )
            card.id = card_hash['id'] || card.id
            # Zorg dat nil resulteert in true (default)
            card.study = card_hash.key?('study') ? card_hash['study'] : true

            # =========================================================================
            # 🎯 SPACED REPETITION TYPE-BRANDMUUR (NIEUW):
            # 👉 Eis 1: Zet de interval-fallback standaard netjes op 1 (Integer) in plaats van true!
            # 👉 Eis 2: Vertaal de platte JSON-string van next_review_at terug naar een echt Ruby Time-object!
            # =========================================================================
            card.interval = card_hash.key?('interval') ? card_hash['interval'].to_i : 1

            card.next_review_at = if card_hash.key?('next_review_at')
                                    begin
                                      Time.parse(card_hash['next_review_at'])
                                    rescue StandardError
                                      Time.now
                                    end
                                  else
                                    Time.now
                                  end

            deck.cards << card
          end
          source.decks << deck
        end
        subject.sources << source
      end
      @subjects << subject
    end

    if @subjects.nil? || @subjects.empty?
      @subjects = []

      default_deck   = Deck.new('Deck', [])
      default_source = Source.new('Source', [default_deck])
      default_sub    = Subject.new('Subject', [default_source])

      @subjects << default_sub
    end

    nil # return nil at succes as with Python
  rescue StandardError => e
    e
  end

  def import_apkg(apkg_path)
    return ArgumentError.new('APKG file path is required.') if
      apkg_path.nil? || apkg_path.to_s.strip.empty?

    apkg_path = File.expand_path(apkg_path.to_s)
    return Errno::ENOENT.new("APKG file not found: #{apkg_path}") unless
      File.file?(apkg_path)

    total_cards_imported = 0
    processed_decks = Set.new
    @subjects ||= []

    scrub_html = lambda do |value|
      text = value.to_s
      text = text.gsub(/\[sound:[^\]]*\]/i, ' ')
      text = text.gsub(/\[image:[^\]]*\]/i, ' ')

      text = text.gsub(%r{<(script|style)\b[^>]*>.*?</\1\s*>}im, ' ')
      text = text.gsub(%r{<br\s*/?>|</(?:div|p|li|h[1-6])\s*>}i, ' ')
      text = text.gsub(/<[^>]*>/, ' ')
      CGI.unescapeHTML(text).gsub(/\s+/, ' ').strip
    end

    begin
      Dir.mktmpdir('anki_unzip_') do |temp_dir|
        db = nil

        begin
          db_path = nil

          Zip::File.open(apkg_path) do |zip_file|
            entry =
              zip_file.find { |item| File.basename(item.name) == 'collection.anki21' } ||
              zip_file.find { |item| File.basename(item.name) == 'collection.anki2' }

            raise 'No collection.anki2 or collection.anki21 found in the APKG file.' unless entry

            db_path = File.join(temp_dir, File.basename(entry.name))
            File.binwrite(db_path, entry.get_input_stream.read)
          end

          unless db_path && File.file?(db_path) && File.size?(db_path)
            raise "Failed to extract the Anki database to: #{db_path}"
          end

          db = SQLite3::Database.new(db_path)

          collection_row = db.get_first_row(
            'SELECT decks, models FROM col LIMIT 1'
          )
          raise 'Anki collection metadata is missing.' unless collection_row

          decks_json, models_json = collection_row
          anki_decks = JSON.parse(decks_json.to_s)
          anki_models = JSON.parse(models_json.to_s)

          # 🎯 STAP 1: SCHONE TEMPLATE FIELD-MAPPING ENGINE
          model_field_indices = {}

          anki_models.each do |model_id, model|
            model_fields = Array(model['flds'])
            field_names = model_fields.map { |f| f['name'].to_s }

            template = Array(model['tmpls']).first || {}
            qfmt = template['qfmt'].to_s
            afmt = template['afmt'].to_s

            # 🟢 GECORRIGEERD: Loepzuivere en geldige Ruby-regex voor de {{veldnaam}} extractie!
            q_fields = qfmt.scan(%r{\{\{([^#/\}]+)\}\}}).flatten.map(&:strip)
            a_fields = afmt.scan(%r{\{\{([^#/\}]+)\}\}}).flatten.map(&:strip)

            ignore_tags = %w[frontside type tags hint text clozeprocessor]
            q_fields.reject! { |f| ignore_tags.any? { |tag| f.downcase.include?(tag) } }
            a_fields.reject! { |f| ignore_tags.any? { |tag| f.downcase.include?(tag) } }

            target_term_field = q_fields.first || field_names.first
            target_meaning_field = a_fields.find do |f|
              f != target_term_field
            end || a_fields.first || field_names[1] || field_names.first

            term_idx = field_names.index(target_term_field) || 0
            meaning_idx = field_names.index(target_meaning_field) || (field_names.length > 1 ? 1 : 0)

            model_field_indices[model_id.to_s] = { term: term_idx, meaning: meaning_idx }
          end

          # Koppel Anki-deck-ID's aan de hiërarchie in de decknaam.
          decks_configured = {}
          anki_decks.each do |deck_id, config|
            full_deck_name = config['name'].to_s.strip
            next if full_deck_name.empty?

            segments = full_deck_name.split('::').map(&:strip).reject(&:empty?)
            next if segments.empty?

            subject_name = segments.length >= 2 ? segments[-2] : segments.first

            decks_configured[deck_id.to_s] = {
              subject: subject_name,
              source: 'Anki',
              deck: full_deck_name
            }
          end

          # 🎯 STAP 2: GESYNCHRONISEERDE 4-KOLOMS SQL INGESTIE
          query = <<~SQL
            SELECT cards.did, notes.mid, notes.flds, notes.tags
            FROM cards
            INNER JOIN notes ON cards.nid = notes.id
          SQL

          deck_card_counter = 0

          db.execute(query) do |row|
            deck_id, model_id, raw_fields, raw_tags = row

            deck_meta = decks_configured[deck_id.to_s]
            next unless deck_meta

            field_values = raw_fields.to_s.split("\x1f", -1).map(&:strip)
            next if field_values.empty?

            # We behouden de herkomst voor de Subject en Source groepering
            actual_subject_name = deck_meta[:subject]

            mapping = model_field_indices[model_id.to_s] || { term: 0, meaning: 1 }

            t_idx = mapping[:term]
            m_idx = mapping[:meaning]

            t_idx = 0 if t_idx >= field_values.length
            m_idx = (field_values.length > 1 ? 1 : 0) if m_idx >= field_values.length

            term_clean = scrub_html.call(field_values[t_idx])
            meaning_clean = scrub_html.call(field_values[m_idx])

            next if term_clean.empty? || meaning_clean.empty?

            # 🎯 DE AUTOMATISCHE 50-KAARTEN BREEKHAMER MET SCHONE STRAKKE NAAMGEVING:
            deck_card_counter += 1

            # Bereken de actuele chunk index (1-50 = Deel 1, 51-100 = Deel 2, enz.)
            chunk_number = ((deck_card_counter - 1) / 50) + 1

            # 🚀 BUILD THE CLEAN, SHORT NAME HERE:
            fixed_chunk_deck_name = "Imported #{chunk_number}"

            # Subject selectie
            target_subject = @subjects.find { |subject| subject.name.to_s.casecmp?(actual_subject_name) }
            unless target_subject
              target_subject = Subject.new(actual_subject_name, [])
              @subjects << target_subject
            end

            # Source selectie
            target_subject.sources ||= []
            target_source = target_subject.sources.find do |source|
              source.name.to_s.casecmp?(deck_meta[:source])
            end
            unless target_source
              target_source = Source.new(deck_meta[:source], [])
              target_subject.sources << target_source
            end

            # Deck selectie gelockt op de schone 'Imported X' string
            target_source.decks ||= []
            target_deck = target_source.decks.find { |deck| deck.name.to_s.casecmp?(fixed_chunk_deck_name) }
            unless target_deck
              target_deck = Deck.new(fixed_chunk_deck_name, [])
              target_source.decks << target_deck
            end

            target_deck.cards ||= []
            target_deck.cards << Card.new(term_clean, nil, meaning_clean)

            processed_decks << "#{actual_subject_name}::#{fixed_chunk_deck_name}"
            total_cards_imported += 1
          end

          [total_cards_imported, processed_decks.length]
        ensure
          db&.close
        end
      end
    rescue StandardError => e
      e
    end
  end

  # =========================================================================
  # 📊 STANDAARD SINGLE-DECK / WORKSPACE EXPORTERS
  # 👉 GECENTREERD: Nu op de Library klasse zodat de controller er via @library bij kan!
  # =========================================================================
  def export_csv(filename, cards_array, include_header)
    CSV.open(filename, 'w:utf-8') do |csv|
      csv << %w[term context meaning] if include_header
      cards_array.each do |card|
        csv << [card.term, card.context, card.meaning]
      end
    end
    cards_array.length
  rescue StandardError => e
    e
  end

  def export_xml_selection(filename, cards_array, export_name = 'Exported Selection')
    doc = REXML::Document.new
    root = doc.add_element('deck', { 'name' => export_name.to_s })
    cards_array.each do |card|
      node = root.add_element('card')
      node.add_element('study').text = card.respond_to?(:study) ? card.study.to_s : 'false'
      node.add_element('term').text = card.term.to_s
      node.add_element('context').text = card.context.to_s
      node.add_element('meaning').text = card.meaning.to_s
    end
    File.open(filename, 'w:utf-8') do |file|
      doc.write(file, 2)
    end
    cards_array.length
  rescue StandardError => e
    e
  end

  # =========================================================================
  # 📦 UNIVERSELE MULTI-TIERED TAR.GZ BULK EXPORTER
  # 👉 OPGELOST: Gebruikt nu direct @subjects van de actieve Library-instantie.
  # Dit lost alle method mismatches en scope-crashes direct op!
  # =========================================================================
  def execute_tar_bulk_export(format_choice, include_header, custom_archive_name)
    base_archive_name = custom_archive_name.to_s.strip

    if base_archive_name.empty?
      base_archive_name = "#{@app_name}_#{format_choice}_export_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    end

    base_archive_name = base_archive_name.sub(/\.(zip|tar\.gz|tgz)\z/i, '')
    final_archive_path = "#{base_archive_name}.tar.gz"

    temp_dir = File.join(Dir.tmpdir, "#{@app_name}_export_#{SecureRandom.hex(8)}")
    FileUtils.mkdir_p(temp_dir)

    generated_files = []
    total_cards_processed = 0

    begin
      # 🎯 GEFIXT: Loopt nu viltstrak over de subjects van DEZE library instantie!
      @subjects.each do |subject|
        # \p{Alnum} matcht alle letters (ook Arabisch/Hebreeuws) en cijfers.
        sub_clean = subject.name.to_s.downcase.gsub(/[^\p{Alnum}\-_]/, '_').gsub(/_+/, '_')

        subject.sources.each do |source|
          src_clean = source.name.to_s.downcase.gsub(/[^\p{Alnum}\-_]/, '_').gsub(/_+/, '_')

          source.decks.each do |deck|
            next if deck.cards.nil? || deck.cards.empty?

            deck_clean = deck.name.to_s.downcase.gsub(/[^\p{Alnum}\-_]/, '_').gsub(/_+/, '_')

            # 👉 BLUEPRINT FILENAME GENERATION: subject_source_deck
            export_file_name = "#{sub_clean}_#{src_clean}_#{deck_clean}.#{format_choice}"
            staging_file_path = File.join(temp_dir, export_file_name)

            write_result = if format_choice == 'csv'
                             export_csv(staging_file_path, deck.cards, include_header)
                           else
                             export_xml_selection(staging_file_path, deck.cards, deck.name)
                           end

            return write_result if write_result.is_a?(StandardError)

            generated_files << staging_file_path
            total_cards_processed += deck.cards.length
          end
        end
      end

      return StandardError.new('No cards found across any decks to export.') if generated_files.empty?

      File.delete(final_archive_path) if File.exist?(final_archive_path)

      escaped_temp = Shellwords.escape(temp_dir)
      escaped_tar  = Shellwords.escape(File.expand_path(final_archive_path))

      system("tar -czf #{escaped_tar} -C #{escaped_temp} .")

      { archive_path: final_archive_path, cards_count: total_cards_processed, files_count: generated_files.length }
    ensure
      FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
    end
  rescue StandardError => e
    e
  end
end

class Subject
  attr_accessor :id, :name, :sources

  def initialize(name = '', sources = [])
    @id = SecureRandom.uuid
    @name = name
    @sources = sources
  end

  def memorised? # all cards memorized?
    @sources.each do |source|
      source.decks.each do |deck|
        deck.cards.each do |card|
          return false if card.study == false
        end
      end
    end
    true
  end
end

class Source
  attr_accessor :id, :name, :decks

  def initialize(name = '', decks = [])
    @id = SecureRandom.uuid
    @name = name
    @decks = decks
  end

  def memorised? # all cards memorized?
    @decks.each do |deck|
      deck.cards.each do |card|
        return false if card.study == false
      end
    end
    true
  end
end

class Deck
  attr_accessor :id, :name, :cards

  def initialize(name = '', cards = [])
    @id = SecureRandom.uuid
    @name = name
    @cards = cards
  end

  # 1. Sorteer de interne @cards array direct in-place
  def sort!(column = :term, direction = :asc)
    return if @cards.nil? || @cards.empty?

    # Lambda om de tekst bidi-schoon te maken voor een eerlijke vergelijking
    clean_bidi_string = lambda do |raw_str|
      # We strippen de directional marks (\u200E, \u200F, \u202A-\u202E) en normaliseren naar NFC
      raw_str.to_s.gsub(/[\u200E\u200F\u202A\u202B\u202C\u202D\u202E]/, '').strip.unicode_normalize(:nfc).downcase
    end

    @cards.sort_by! do |card|
      case column.to_sym
      when :term
        clean_bidi_string.call(card.term)
      when :context
        clean_bidi_string.call(card.context)
      when :meaning
        clean_bidi_string.call(card.meaning)
      when :study
        # Sorteer op studiestatus (ongeleerd vòòr geleerd)
        card.study ? 1 : 0
      else
        0
      end
    end

    # Reverse the array in place when descending order is requested.
    @cards.reverse! if direction == :desc || direction.to_s.downcase == 'desc'
    nil
  end

  # Return a sorted or shuffled array of cards that have not yet been memorized
  def study(order)
    # 1. Definieer de transformatie-strategie direct via een lambda
    cards = case order.to_sym
              # when :fronts_sorted, :backs_sorted, :alternately_fronts_and_backs_sorted
              #  ->(cards) { cards.sort_by { |card| card.term.to_s.downcase } }
            when :fronts_random, :backs_random, :alternately_fronts_and_backs_random, :everything_random
              ->(cards) { cards.shuffle }
            else
              ->(cards) { cards } # Fallback: return array unchanged
            end

    # 🎯 INTELLIGENT ROTATION FILTER:
    # 1. Filter out already learned cards (study == false)
    active_pool = @cards.select { |card| card.study }

    # 2. Sort the pool so cards with the oldest 'next_review_at' or the
    # smallest interval (worst performance) appear first in the session!
    sorted_pool = active_pool.sort_by do |card|
      [card.next_review_at || Time.now, card.interval || 1]
    end

    # 3. Pass the prioritized selection through the shuffle strategy
    cards.call(sorted_pool)
  end

  def nothing_memorised? # no cards memorized? (Oftewel: alles staat nog in de beginstand!)
    return true if @cards.nil? || @cards.empty?

    @cards.each do |card|
      next unless card.respond_to?(:study)

      val = card.study
      # Een kaart is gememoriseerd/afgevinkt als study explicit FALSE (of "false") is!
      is_memorized = val == false || val.to_s.strip.downcase == 'false' || val == :false

      # Zodra we ook maar ÉÉN kaart tegenkomen die is afgevinkt, valt er wat te resetten!
      return false if is_memorized
    end

    # 🟢 Als we hier belanden, staat elke kaart nog op true; er is NIETS veranderd!
    true
  end

  def memorised? # all cards memorized?
    # Brandmuur: Als er geen kaarten zijn, is er ook niets gememoriseerd!
    return false if @cards.nil? || @cards.empty?

    @cards.each do |card|
      next unless card.respond_to?(:study)

      val = card.study
      # Een kaart is pas gememoriseerd/klaar als study explicit FALSE (of "false") is!
      is_memorized = val == false || val.to_s.strip.downcase == 'false' || val == :false

      # If even one card still needs to be learned (true), return false immediately.
      return false unless is_memorized
    end
    true
  end

  def has_duplicates?
    seen = {}
    cards.each do |card|
      sig = "#{card.term.to_s.strip}|#{card.context.to_s.strip}|#{card.meaning.to_s.strip}"
      return true if seen[sig]

      seen[sig] = true
    end
    false
  end

  def remove_duplicates!
    initial_count = cards.length
    seen = {}

    cards.filter! do |card|
      sig = "#{card.term.to_s.strip}|#{card.context.to_s.strip}|#{card.meaning.to_s.strip}"
      if seen[sig]
        false # Duplicaat: gooi weg
      else
        seen[sig] = true
        true  # Uniek: behouden
      end
    end

    initial_count - cards.length
  end

  def get_index(id)
    # Get card index by id
    @cards.find_index { |card| card.id == id }
  end

  def reset
    @cards.each { |card| card.study = true }
  end

  def import_csv(filename)
    imported_count = 0

    # We read the file line-by-line as raw text to prevent RFC-4180 parsing crashes
    File.foreach(filename, encoding: 'utf-8') do |raw_line|
      clean_line = raw_line.strip
      next if clean_line.empty?

      # 🎯 1. ANKI TSV DETECTOR & SPLITTER:
      # Anki natively exports to TSV (tab-separated text) files.
      # We check for tab formatting first to perfectly isolate rows.
      row = clean_line.split("\t").map(&:strip)

      # Fallback to standard comma/quote regex scanning if no tabs are found
      row = clean_line.scan(/(?:"([^"]*)"|([^,]+))/).flatten.compact.map(&:strip) if row.length <= 1

      next if row.all?(&:empty?)

      # 🎯 2. ANKI HTML & QUOTE STRIPPING:
      # Filter out nested formatting, <div> structures, or wrapped double quotes
      row = row.map do |field|
        field.to_s
             .gsub(/<[^>]*>/, '')       # Eradicate HTML markup natively
             .gsub(/\A"+|"+~\z/, '')    # Scrub leading/trailing quotation marks
             .strip
      end

      # Skip Anki metadata header descriptions or commented configuration marks
      next if row.first.to_s.start_with?('#') || row.first.to_s.downcase.start_with?('anki')

      # 📊 CENTRALIZED FIELD RESOLUTION:
      term = ''
      context_value = nil
      meaning = ''
      valid_card = true

      case row.length
      when 2
        term    = row[0]
        meaning = row[1]
      when 3
        term = row[0]
        context_value = row[1].empty? || row[1] == '""' ? nil : row[1]
        meaning = row[2]
      else
        if row.length > 3
          # 🎯 ANKI MULTI-FIELD TAK: If an Anki file includes tags or optional columns,
          # we strictly capture Field 1 as the Term and Field 2 as the Meaning.
          term    = row[0]
          meaning = row[1]
        else
          # Fallback for unexpected or single-column structural line mismatches
          valid_card = false
        end
      end

      # 🎯 SINGLE-POINT ENTRY AND INCREMENTOR:
      if valid_card
        @cards << Card.new(term, context_value, meaning)
        imported_count += 1
      end
    end

    # Return the verified counter parameter seamlessly back to the controller pipeline
    imported_count
  rescue StandardError => e
    e
  end
end

class Card
  attr_accessor :id, :study, :term, :meaning, :context, :interval, :next_review_at

  def initialize(term = '', context = '', meaning = '')
    @id = SecureRandom.uuid
    @study = true
    @term = term
    @meaning = meaning
    @context = context
    @interval = 1 # Starts at 1. Higher number = comes back less often.
    @next_review_at = Time.now
  end

  def register_score(correct)
    @interval = if correct
                  # User knew it! Double the interval so it takes longer to reappear
                  [@interval * 2, 32].min # Cap at 32 days maximum
                else
                  # User forgot it. Drop it back to high-priority rotation immediately
                  1
                end
    @next_review_at = Time.now + (@interval * 86_400) # 86400 seconds = 1 day
  end
end
