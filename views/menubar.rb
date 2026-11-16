class MenuBarView
  HIGHLIGHT_PADDING = true

  MENU_DATA = {
    'App' => %i[about],
    'Help' => %i[help website mail]
  }.freeze

  MENU_GAP = 1

  class << self
    def menu_data(app)
      settings = AppConfig.settings

      # Haal de app_name dynamic op uit de actieve applicatie-instantie
      app_name_value = app.instance_variable_get(:@app_name)

      menu_app_name = format(
        settings.language_string(:menu_app_name),
        app_name: app_name_value
      )

      {
        menu_app_name => [
          settings.language_string(:sub_menu_about)
        ],
        settings.language_string(:menu_help) => [
          settings.language_string(:help_main_title),
          settings.language_string(:sub_menu_visit_website),
          settings.language_string(:sub_menu_compose_support_email)
        ]
      }
    end

    def draw(frame, area, app, tui)
      active_menu_data = menu_data(app)
      menu_keys = active_menu_data.keys
      state = read_menu_state(app)

      # 👉 ECHTE POPUP EN HELP DETECTIE
      popup_is_displayed = (state[:active_focus].to_s == 'popup') ||
                           (app.instance_variable_get(:@popup)&.respond_to?(:active?) && app.instance_variable_get(:@popup).active?)

      # 🎯 COCKPIT PARITEIT: Controleer of de geopende popup daadwerkelijk uit het menu is ontstaan
      popup_from_menu =
        popup_is_displayed &&
        app.instance_variable_get(:@menu_origin_focus) == :menu

      # Het menu is visueel open als hij de focus heeft óf als er een popup vanuit het menu openstaat
      menu_is_visually_open = (state[:active_focus].to_s == 'menu') || popup_from_menu

      if state[:dropdown_open] && menu_is_visually_open
        draw_submenu(
          frame,
          area,
          tui,
          menu_keys,
          active_menu_data,
          state,
          state[:active_focus].to_s == 'menu', # Heeft het menu de échte focus?
          popup_is_displayed,
          popup_from_menu # 👉 Doorgesluisd naar de submenu-tekenaar
        )
      else
        draw_main_menu_bar(
          frame,
          area,
          tui,
          menu_keys,
          state,
          state[:active_focus].to_s == 'menu',
          popup_is_displayed,
          popup_from_menu # 👉 Doorgesluisd naar de hoofdmenu-tekenaar
        )
      end

      return unless app.respond_to?(:active_bar_rotation_indicator_symbol)

      rotation_indicator_char = app.active_bar_rotation_indicator_symbol
      return unless rotation_indicator_char && rotation_indicator_char != ' ' && rotation_indicator_char != ''

      reg_width = area.width.to_i
      rotation_indicator_x = area.x + reg_width - 2
      rotation_indicator_y = area.y

      bg_color = AppConfig.settings.theme_item(:background)
      rotation_indicator_style = tui.style(
        fg: AppConfig.settings.theme_item(:window_border),
        bg: bg_color,
        modifiers: [:bold]
      )

      frame.render_widget(
        tui.paragraph(text: "#{rotation_indicator_char}", style: rotation_indicator_style),
        RatatuiRuby::Layout::Rect.new(rotation_indicator_x, rotation_indicator_y, 1, 1)
      )
    end

    private

    def read_menu_state(app)
      active_focus = app.instance_variable_get(:@active_focus)

      popup = app.instance_variable_get(:@popup)
      popup_is_active =
        active_focus.to_s == 'popup' ||
        (popup&.respond_to?(:active?) && popup.active?)

      popup_from_menu =
        popup_is_active &&
        app.instance_variable_get(:@menu_origin_focus) == :menu

      if popup_from_menu
        {
          active_focus: active_focus,
          active_menu_idx: app.instance_variable_get(:@active_menu_idx).to_i,
          active_submenu_idx: app.instance_variable_get(:@active_submenu_idx).to_i,
          dropdown_open: true
        }
      else
        {
          active_focus: active_focus,
          active_menu_idx: app.instance_variable_get(:@active_menu_idx).to_i,
          active_submenu_idx: app.instance_variable_get(:@active_submenu_idx).to_i,
          dropdown_open: app.instance_variable_get(:@menu_dropdown_open) == true
        }
      end
    end

    def append_menu_item(spans, tui, text, style)
      if HIGHLIGHT_PADDING
        extended_text = " #{text} "
        spans << tui.span(extended_text, style)
      else
        # 💤 CONSTANT STATE OFF: Keep highlights exactly on the letters
        # and place the padding outside them.
        spans << tui.span(' ', tui.style)
        spans << tui.span(text, style)
        spans << tui.span(' ', tui.style)
      end
    end

    def draw_main_menu_bar(
      frame,
      area,
      tui,
      menu_keys,
      state,
      menu_has_focus,
      popup_is_displayed,
      popup_from_menu
    )
      spans = []

      spans << if HIGHLIGHT_PADDING
                 tui.span(' ', tui.style)
               else
                 # Ruststand als padding uitstaat (originele insprong)
                 tui.span('', tui.style)
               end

      menu_keys.each_with_index do |menu_key, menu_index|
        selected = (state[:active_menu_idx] == menu_index)
        style = main_menu_style(tui, menu_has_focus, popup_is_displayed, popup_from_menu, selected)

        append_menu_item(spans, tui, menu_key, style)
        spans << tui.span(' ' * [MENU_GAP, 3].min, tui.style)
      end

      frame.render_widget(tui.line(spans), area)
    end

    def submenu?(menu_key)
      MENU_DATA.fetch(menu_key, []).any?
    end

    def draw_submenu(frame, area, tui, menu_keys, active_menu_data, state, menu_has_focus, popup_is_displayed,
                     popup_from_menu)
      menu_index = normalize_index(
        state[:active_menu_idx],
        menu_keys.length
      )

      menu_key = menu_keys[menu_index]
      submenu_items = active_menu_data.fetch(menu_key, [])

      spans = []

      spans << if HIGHLIGHT_PADDING
                 tui.span('  ', tui.style) # 🌟 2 posities opschuiven!
               else
                 tui.span(' ', tui.style) # Ruststand (1 positie insprong)
               end

      # Context van het submenu (de parent kolomkop); niet gehighlight
      spans << tui.span("#{menu_key} ›", submenu_parent_style(tui))

      # 🎯 VERSCHUIVING 2: HET GEDEELTE NÁ HET '>' TEKEN
      # When wide padding is enabled, add one extra space here so
      # de brede sub-highlights niet tegen het '›' teken aan plakken!
      spans << tui.span(' ', tui.style) if HIGHLIGHT_PADDING

      submenu_items.each_with_index do |item, submenu_index|
        selected = (state[:active_submenu_idx] == submenu_index)
        style = submenu_style(tui, menu_has_focus, popup_is_displayed, popup_from_menu, selected)

        append_menu_item(spans, tui, item, style)
        spans << tui.span(' ' * [MENU_GAP, 3].min, tui.style)
      end

      frame.render_widget(tui.line(spans), area)
    end

    def submenu_parent_style(tui)
      tui.style(
        fg: AppConfig.settings.theme_item(:foreground),
        modifiers: [:dim]
      )
    end

    # =========================================================================
    # 🎨 GECORRIGEERDE HOOFDMENU STIJLASSISTENT
    # =========================================================================
    def main_menu_style(tui, menu_has_focus, popup_is_displayed, popup_from_menu, selected)
      settings = AppConfig.settings
      if menu_has_focus && selected
        # 🟢 MENU ACTIEF EN GESELECTEERD -> Fel verlichte cursorbalk!
        tui.style(
          fg: settings.theme_item(:search_results_background),
          bg: settings.theme_item(:selection_background)
        )
      elsif popup_from_menu && selected
        # 🟡 POPUP GEOPEND VANUIT HET MENU -> Toon de gedimde inactieve cursorbalk!
        tui.style(
          fg: settings.theme_item(:search_results_background),
          bg: settings.theme_item(:selection_background),
          modifiers: %i[dim]
        )
      elsif menu_has_focus
        # Menu is actief maar niet geselecteerd -> Helder wit
        tui.style(fg: settings.theme_item(:foreground))
      else
        # 🚨 RUSTSTAND (Focus in Tree/Table) OF POPUP VANUIT HOOFDSCHERM (?, /, \)
        # Keep it dimmed in monochrome; do not show highlighted bars.
        tui.style(
          fg: settings.theme_item(:foreground),
          modifiers: [:dim]
        )
      end
    end

    # =========================================================================
    # 🎨 GECORRIGEERDE SUBMENU STIJLASSISTENT
    # =========================================================================
    def submenu_style(tui, menu_has_focus, popup_is_displayed, popup_from_menu, selected)
      settings = AppConfig.settings

      if menu_has_focus && selected
        # 🟢 DROPDOWN ACTIEF EN GEFOCUST -> Fel verlichte actieve cursorbalk
        tui.style(
          fg: settings.theme_item(:search_results_background),
          bg: settings.theme_item(:selection_background)
        )
      elsif popup_from_menu && selected
        # 🟡 POPUP GEOPEND VANUIT DROPDOWN -> Toon de gedimde inactieve cursorbalk!
        tui.style(
          fg: settings.theme_item(:search_results_background),
          bg: settings.theme_item(:selection_background),
          modifiers: [:dim]
        )
      elsif popup_is_displayed
        # Als er een popup openstaat, moeten de inactieve submenu-items ook dimmen
        tui.style(
          fg: settings.theme_item(:foreground),
          modifiers: [:dim]
        )
      else
        # Normale actieve geopende dropdown stand -> Helder wit
        tui.style(
          fg: settings.theme_item(:foreground)
        )
      end
    end

    def normalize_index(index, length)
      return 0 if length <= 0

      [[index, 0].max, length - 1].min
    end
  end
end
