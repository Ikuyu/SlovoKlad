class RatatuiRubyApp
  def draw_top_region(tui, frame, region)
    settings = AppConfig.settings

    # 1. Check live whether a popup or help window is open.
    popup_is_displayed = (defined?(@active_focus) && @active_focus.to_s == 'popup') ||
                         (defined?(@popup) && @popup && @popup.respond_to?(:active?) && @popup.active?)

    # The menu has focus only when focus is :menu and no popup is open.
    menu_has_focus = (@active_focus.to_s == 'menu') && !popup_is_displayed

    # 2. Determine the window border style.
    border_style = if menu_has_focus
                     tui.style(fg: settings.theme_item(:window_border),
                               bg: settings.theme_item(:background))
                   else
                     tui.style(fg: settings.theme_item(:foreground),
                               bg: settings.theme_item(:background), modifiers: [:dim])
                   end

    # 👉 STEP A: Draw the block completely without a title.
    top_block = tui.block(
      border_style: border_style,
      style: { bg: settings.theme_item(:background) },
      borders: :all,
      border_type: settings.corner
    )
    frame.render_widget(top_block, region)

    # 👉 STEP B: Calculate the coordinates on top of the upper border.
    title_area = RatatuiRuby::Layout::Rect.new(
      region.x + 2,
      region.y,
      [region.width - 4, 1].max,
      1
    )

    # =========================================================================
    # 🎯 STAP C: STRENG OPGEFORMATTEERDE EN TEXT-BEWUSTE ACCENT MATRIX
    # Split the brackets and colons from the main word.
    # =========================================================================
    accent_style = if popup_is_displayed
                     # 🚨 POPUP OPEN: Dim the highlighted sections as well.
                     tui.style(fg: settings.theme_item(:foreground),
                               bg: settings.theme_item(:background), modifiers: [:dim])
                   elsif !menu_has_focus
                     # Menu is active -> bright highlight (window_shortcut_section theme).
                     tui.style(fg: settings.theme_item(:window_shortcut_section),
                               bg: settings.theme_item(:background), modifiers: [:bold])
                   else
                     # Idle state -> normally dimmed.
                     tui.style(fg: settings.theme_item(:window_shortcut_section),
                               bg: settings.theme_item(:background), modifiers: [:bold])
                   end

    # Dim the word portion along with the panel in its idle or popup state.
    text_style = if popup_is_displayed || !menu_has_focus
                   tui.style(fg: settings.theme_item(:window_title),
                             bg: settings.theme_item(:background), modifiers: [:dim])
                 else
                   tui.style(fg: settings.theme_item(:window_title),
                             bg: settings.theme_item(:background))
                 end

    # Manually combine the spans into the final title line.
    label, key = settings.language_string(:menu_title).split(/\s+/, 2)

    title_spans = [
      tui.span(" #{label} ", text_style), # Fel gekleurd bij Menu/Table, helder wit bij de rest!
      tui.span("#{key} ", accent_style)
    ]

    formatted_title = RatatuiRuby::Text::Line.new(spans: title_spans)
    frame.render_widget(formatted_title, title_area)

    # 3. Fill the menu bar in the inner area.
    menu_bar_area = RatatuiRuby::Layout::Rect.new(
      region.x + 1,
      region.y + 1,
      [region.width - 2, 1].max,
      1
    )
    MenuBarView.draw(frame, menu_bar_area, self, tui)
  end

  private

  def draw_top_block(tui, frame, region)
    settings = AppConfig.settings
    active_menu = @active_focus == :menu

    border_style =
      if active_menu
        {
          fg: settings.theme_item(:window_border),
          bg: settings.theme_item(:background)
        }
      else
        {
          fg: settings.theme_item(:foreground),
          bg: settings.theme_item(:background), modifiers: [:dim]
        }
      end

    top_block = tui.block(
      title: settings.language_string(:menu_title),
      title_style: {
        fg: settings.theme_item(:foreground),
        bg: settings.theme_item(:background), modifiers: [:dim]
      },
      border_style: border_style,
      style: { bg: settings.theme_item(:background) },
      borders: :all,
      border_type: settings.corner
    )

    frame.render_widget(top_block, region)
  end
end
