# require 'yaml' # already required in app.rb
require 'yaml'
require 'fileutils'
require 'rbconfig'

module AppConfig
  MARKERS = {
    cross: { label: 'Cross', symbol: 'x' },
    block: { label: 'Block', symbol: '▪' },
    plus: { label: 'Plus', symbol: '+' },
    asterisk: { label: 'Asterisk', symbol: '*' }
  }.freeze

  LANGUAGES = {
    en: { label: 'English' },
    nl: { label: 'Nederlands' }
  }.freeze

  CORNERS = {
    plain: {
      label: 'Plain'
    },
    rounded: {
      label: 'Rounded'
    }
  }.freeze

  THEMES = {
    default: { label: 'Default' },
    bw: { label: 'Black & White' },
    cga: { label: 'Retro ANSI' },
    crt: { label: 'CRT' },
    amber: { label: 'Amber' },
    borland: { label: 'Borland' },
    ttx: { label: 'Teletext' },
    tos: { label: 'TOS' },
    c64: { label: 'c64' },
    terminal: { label: 'Terminal' }
  }.freeze

  # Defaults for marker_symbol, language and theme
  SETTINGS = {
    marker_symbol: :cross,
    language: :en,
    theme: :terminal,
    corner: :rounded,
    last_opened_filename: nil,
    startup_screen_font_name: 'tubes.flf',
    # collapsing_borders: true,
    study_strategy: :fronts_random # deze setting wordt niet opgeslagen; de gebruiker moet dit niet (nog) niet zelf kunnen aanpasen
  }.freeze

  APP_INFO_FILE = File.expand_path('../app_info.yml', __dir__).freeze
  APP_NAME = YAML.safe_load(
    File.read(APP_INFO_FILE),
    permitted_classes: [],
    aliases: false
  ).fetch('app_name').to_s.freeze
  LEGACY_CONFIG_FILE = File.expand_path('settings.yml', __dir__).freeze

  # Store user settings in the platform's standard per-user config directory.
  CONFIG_FILE = begin
    file_name = 'settings.yml'
    if Gem.win_platform?
      base_dir = ENV['APPDATA'] || File.join(Dir.home, 'AppData', 'Roaming')
      File.join(base_dir, APP_NAME, file_name)
    elsif RbConfig::CONFIG['host_os'] =~ /mac|darwin/i
      File.join(Dir.home, 'Library', 'Application Support', APP_NAME, file_name)
    else
      base_dir = ENV['XDG_CONFIG_HOME'] || File.join(Dir.home, '.config')
      File.join(base_dir, APP_NAME, file_name)
    end
  end.freeze

  # Ensure you can call AppConfig.settings from anywhere
  def self.settings
    @settings ||= Settings.new
  end
end

# The Settings class is only required for loading and saving the stettings
class Settings
  attr_accessor :selected_marker_symbol, :language, :theme, :corner, :collapsing_borders, :beeps,
                :rotation_indicator_enabled, :alternate_rows_enabled, :study_strategy, :last_opened_filename,
                :custom_theme_name, :custom_theme_path, :startup_screen_font_name
  attr_reader :corrupt_on_load

  def initialize
    @corrupt_on_load = false

    @selected_marker_symbol     = AppConfig::SETTINGS[:marker_symbol]
    @language                   = AppConfig::SETTINGS[:language]
    @theme                      = AppConfig::SETTINGS[:theme]
    @corner                     = AppConfig::SETTINGS[:corner]
    @collapsing_borders         = AppConfig::SETTINGS[:collapsing_borders]
    @beeps                      = true
    @rotation_indicator_enabled = true
    @alternate_rows_enabled     = true
    @study_strategy             = AppConfig::SETTINGS[:study_strategy]
    @last_opened_filename       = AppConfig::SETTINGS[:last_opened_filename]
    @startup_screen_font_name   = AppConfig::SETTINGS[:startup_screen_font_name]
    @handwritten_languages      = Hash.new(false) # begint leeg, maar ELKE taal die je opvraagt staat direct standaard op false!
    @custom_theme_name          = nil
    @custom_theme_path          = nil
    @dynamic_theme_items        = {} # Stores running hex updates in memory

    # Load existing settings (or migrate the old config/settings.yml file).
    load
    # Create the user config file on first launch so the platform folder exists
    # even when the user exits without changing a setting.
    save unless File.exist?(AppConfig::CONFIG_FILE)
  end

  def handwritten?(lang_key)
    @handwritten_languages ||= Hash.new(false)
    !!@handwritten_languages[lang_key.to_s.gsub(/\A:/, '').to_sym]
  end

  def toggle_handwritten(lang_key)
    @handwritten_languages ||= Hash.new(false)
    key = lang_key.to_s.gsub(/\A:/, '').to_sym
    @handwritten_languages[key] = !@handwritten_languages[key]
  end

  def corrupt_on_load=(value)
    @corrupt_on_load = !!value
  end

  def selected_marker=(value)
    @selected_marker_symbol = value.to_s.gsub(/\A:/, '').to_sym
  end

  def selected_marker
    @selected_marker_symbol
  end

  def marker_symbol
    AppConfig::MARKERS.fetch(
      @selected_marker_symbol,
      AppConfig::MARKERS.fetch(AppConfig::SETTINGS[:marker_symbol])
    )
  end

  def corner_type
    @corner
  end

  def set_theme_item(item_key, truecolor_hex)
    @dynamic_theme_items ||= {}
    @dynamic_theme_items[item_key.to_sym] = truecolor_hex.to_s
  end

  def theme_items
    @dynamic_theme_items ||= {}
  end

  def theme_item(item_key)
    raw_theme = @theme || :default
    theme_sym = raw_theme.to_s.gsub(/\A:/, '').to_sym

    # Terminal en custom themes gebruiken dynamische kleuren
    custom_theme = !AppConfig::THEMES.key?(theme_sym)

    if theme_sym == :terminal || custom_theme
      dynamic_value = @dynamic_theme_items&.[](item_key.to_sym)
      return dynamic_value if dynamic_value && !dynamic_value.empty?
    end

    theme_table = AppThemes::THEME_DATA.fetch(theme_sym) do
      AppThemes::THEME_DATA[:default]
    end

    key = item_key.to_sym
    value = theme_table.fetch(key)

    if key == :selection_background && (value.nil? || value.to_s.strip.empty?)
      @selection_shade_resolver ||= TerminalThemeResolver.new
      return @selection_shade_resolver.shade_selection(
        theme_table.fetch(:background)
      )
    end

    value
  end

  def language_string(key = nil)
    return '' if key.nil?

    translations = AppTranslations::TRANSLATIONS.fetch(@language, {})
    translations.fetch(key.to_sym, '')
  end

  # Save all current instance variables to a YAML file
  def save
    FileUtils.mkdir_p(File.dirname(AppConfig::CONFIG_FILE))

    data = {
      selected_marker: @selected_marker_symbol,
      language: @language,
      theme: @theme,
      corner: @corner,
      beeps: @beeps,
      rotation_indicator_enabled: @rotation_indicator_enabled,
      alternate_rows_enabled: @alternate_rows_enabled,
      last_opened_filename: @last_opened_filename,
      startup_screen_font_name: @startup_screen_font_name,
      # collapsing_borders: @collapsing_borders
      # study_strategy: @study_strategy
      custom_theme_name: @custom_theme_name,
      custom_theme_path: @custom_theme_path
    }

    File.write(AppConfig::CONFIG_FILE, YAML.dump(data))
    true
  rescue StandardError
    @corrupt_on_load = true
    false
  end

  # Load all settings from YAML-file (if the file exists)
  def load
    migrate_legacy_config unless File.exist?(AppConfig::CONFIG_FILE)
    return false unless File.exist?(AppConfig::CONFIG_FILE)

    raw_yaml = File.read(AppConfig::CONFIG_FILE)
    return false if raw_yaml.strip.empty? # Empty file

    loaded_data = YAML.safe_load(
      raw_yaml,
      permitted_classes: [Symbol],
      aliases: true,
      symbolize_names: true
    )
    raise AppConfig.settings.language_string(:statusbar_yaml_hash_error) if loaded_data.nil? || !loaded_data.is_a?(Hash)

    @selected_marker_symbol = valid_setting(
      loaded_data[:selected_marker], # Let op: in save schrijf je hem weg als :selected_marker!
      AppConfig::MARKERS.keys,
      AppConfig::SETTINGS[:marker_symbol]
    )

    @language = valid_setting(
      loaded_data[:language],
      AppConfig::LANGUAGES,
      AppConfig::SETTINGS[:language]
    )

    saved_theme_val = loaded_data[:theme]

    saved_theme_sym = saved_theme_val.to_s.gsub(/\A:/, '').to_sym unless saved_theme_val.nil?
    ingebouwde_themas = %i[default bw cga crt amber borland ttx c64 tos terminal]

    @theme = if saved_theme_sym && !ingebouwde_themas.include?(saved_theme_sym)
               saved_theme_sym # Retain the custom theme symbol cleanly
             else
               valid_setting(saved_theme_val, AppConfig::THEMES, AppConfig::SETTINGS[:theme])
             end

    @corner = valid_setting(
      loaded_data[:corner],
      AppConfig::CORNERS,
      AppConfig::SETTINGS[:corner]
    )

    @beeps = valid_boolean(loaded_data[:beeps], true)
    @rotation_indicator_enabled = valid_boolean(loaded_data[:rotation_indicator_enabled], true)
    @alternate_rows_enabled = valid_boolean(loaded_data[:alternate_rows_enabled], true)
    @last_opened_filename = loaded_data[:last_opened_filename] || AppConfig::SETTINGS[:last_opened_filename]
    @startup_screen_font_name = loaded_data[:startup_screen_font_name] || AppConfig::SETTINGS[:startup_screen_font_name]
    @custom_theme_name = loaded_data[:custom_theme_name]
    @custom_theme_path = loaded_data[:custom_theme_path]

    # @collapsing_borders = valid_boolean(loaded_data[:collapsing_borders], AppConfig::SETTINGS[:collapsing_borders])

    # @study_strategy = loaded_data[:study_strategy] || AppConfig::SETTINGS[:study_strategy]

    true
  rescue StandardError
    @corrupt_on_load = true
    false
  end

  def migrate_legacy_config
    legacy_file = AppConfig::LEGACY_CONFIG_FILE
    return unless File.file?(legacy_file)

    FileUtils.mkdir_p(File.dirname(AppConfig::CONFIG_FILE))
    FileUtils.cp(legacy_file, AppConfig::CONFIG_FILE)
  end

  private

  def valid_setting(value, allowed_values, default)
    return default if value.nil?

    value = value.to_s.gsub(/\A:/, '').to_sym

    # If a complete AppConfig hash is provided, extract its keys.
    valid_keys = allowed_values.is_a?(Hash) ? allowed_values.keys : allowed_values

    if valid_keys.include?(value)
      value
    else
      default
    end
  end

  def valid_boolean(value, default)
    return value if [true, false].include?(value)

    default
  end
end
