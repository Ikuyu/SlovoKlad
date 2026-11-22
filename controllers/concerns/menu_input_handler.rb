require 'uri'

def handle_menu_input(key, _modifiers = [])
  raw_key = key.to_s.downcase
  key_str = raw_key.strip

  # Enter niet eerst strippen, anders verdwijnen \r en \n
  if ["\r", "\n"].include?(raw_key) || key_str == 'enter'
    key_str = 'enter'
  elsif raw_key == "\e" || key_str == 'esc' || key_str == 'escape'
    key_str = 'escape'
  end

  menu_keys = MenuBarView.menu_data(self)

  active_menu_data = MenuBarView.menu_data(self)
  current_translated_key = active_menu_data.keys[@active_menu_idx]
  translated_submenu_items = active_menu_data.fetch(current_translated_key, [])

  # Zorg dat de index altijd geldig is
  @active_menu_idx = 0 if @active_menu_idx.nil?
  @active_menu_idx = @active_menu_idx.clamp(0, menu_keys.length - 1)

  current_key = MenuBarView::MENU_DATA.keys[@active_menu_idx]
  submenu_items_symbols = MenuBarView::MENU_DATA.fetch(current_key, [])

  case key_str
  when 'escape'
    if @menu_dropdown_open
      # Close the submenu while keeping the main menu active.
      @menu_dropdown_open = false
      @active_submenu_idx = 0
    else
      SoundManager.play(:switch)
      trigger_rotation_indicator
      # 🎯 OPTIMALISATIE: Grijp terug naar het actieve paneel vòòr het menu!
      # We gebruiken @cockpit_panel_anchor (die bewaart of :tree of :table actief was)
      target = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree
      target = :tree if %i[menu popup command_mode].include?(target)

      @active_focus = target
      @last_focus   = target

      @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    end
    return true

  when 'left', 'h'
    if @menu_dropdown_open
      @active_submenu_idx = (@active_submenu_idx - 1) % [translated_submenu_items.length, 1].max
    else
      @active_menu_idx = (@active_menu_idx - 1) % menu_keys.length
      @active_submenu_idx = 0
    end
    return true

  when 'right', 'l'
    if @menu_dropdown_open
      @active_submenu_idx = (@active_submenu_idx + 1) % [translated_submenu_items.length, 1].max
    else
      @active_menu_idx = (@active_menu_idx + 1) % menu_keys.length
      @active_submenu_idx = 0
    end
    return true

  when 'up', 'k'
    @menu_dropdown_open = false
    @active_submenu_idx = 0

    return true

  when 'down', 'j'
    # Down vanuit het hoofdmenu opent het submenu ook
    @menu_dropdown_open = true
    @active_submenu_idx = 0

    return true

  when 'enter'
    if @menu_dropdown_open
      selected_action_symbol = submenu_items_symbols[@active_submenu_idx]

      @last_focus = :tree if @last_focus.nil? || @last_focus == :menu

      # Vuur de actie stabiel af (zoals execute_library_save)
      execute_menu_action(selected_action_symbol)

      # =========================================================================
      # 🎯 DE BRANDMUUR FIX: ANKER EN MENU BEHOUDEN NA SELECTION
      # =========================================================================
      if @active_focus == :popup
        # SCENARIO A: Er is een popup geopend (About / Help).
        # Keep the dropdown rendering in the background.
        @menu_dropdown_open = true
      else
        # SCENARIO B: Reguliere actie uitgevoerd (Save, Export, Print, Website, etc.)
        # Nu mag het menu direct dicht en keert de besturing direct terug naar de basis!
        @menu_dropdown_open = false
        @active_submenu_idx = 0
        @active_focus       = @menu_origin_focus || :tree
      end
    else
      # Enter op een hoofdmenu-item: open het submenu
      @menu_dropdown_open = true
      @active_submenu_idx = 0
    end

    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
    return true
  end

  false
end

# =========================================================================
# 🎯 GECORRIGEERDE ACTIE-ROUTER (MAPPING VIA SYMBOLEN)
# Always respond to stable symbols, regardless of the language.
# =========================================================================
def execute_menu_action(action_sym)
  # Preserve the original focus (before opening the menu) as the anchor.
  unless defined?(@menu_origin_focus) && @menu_origin_focus && @menu_origin_focus != :menu
    @menu_origin_focus = defined?(@cockpit_panel_anchor) && @cockpit_panel_anchor ? @cockpit_panel_anchor : :tree
    @menu_origin_focus = :tree if %i[menu popup command_mode].include?(@menu_origin_focus)
  end

  case action_sym
  when :about
    @menu_dropdown_open = true if defined?(@menu_dropdown_open)
    show_about_popup
    @active_focus = :popup

  when :help
    if respond_to?(:open_help_popup, true)
      @menu_dropdown_open = true
      open_help_popup
      @active_focus = :popup
    end

  when :website
    help_visit_website

  when :mail
    help_compose_support_mail
  end
end

def show_about_popup
  settings = AppConfig.settings

  # =========================================================================
  # 👉 Net als bij Help leggen we hier de actieve menu-toestand vast vòòrdat
  # de pop-up de regie overneemt! Dit lost de Escape-gijzeling per direct op.
  # =========================================================================
  @focus_before_help = @active_focus unless @focus_before_help == :menu
  @menu_origin_focus = :menu if @active_focus == :menu
  # =========================================================================

  about_message = format(
    settings.language_string(:about_message),
    app_name: @app_name,
    app_version: @app_version,
    ruby_version: RUBY_VERSION,
    ratatui_ruby_version: Gem.loaded_specs.fetch('ratatui_ruby').version,
    app_copyright_year: @app_copyright_year
  )

  @popup.show(
    type: :info,
    title: " #{settings.language_string(:about_title)} ",
    message: about_message
  )

  # Zet de focus-poort open naar de geopende popup
  @active_focus = :popup
end

def help_visit_website
  url = "https://github.com/Ikuyu/#{@app_name}"

  if RUBY_PLATFORM.match?(/darwin/)
    system('open', url)
  else
    system('xdg-open', url)
  end
end

def help_compose_support_mail
  subject = format(
    AppConfig.settings.language_string(:mail_subject),
    app_name: @app_name
  )

  encoded_subject = URI
                    .encode_www_form_component(subject)
                    .gsub('+', '%20')

  mailto = "mailto:hetlevenkronen@gmail.com?subject=#{encoded_subject}"

  if RUBY_PLATFORM.match?(/darwin/)
    system('open', mailto)
  else
    system('xdg-open', mailto)
  end
end
