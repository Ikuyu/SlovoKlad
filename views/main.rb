def draw_main_interface(_tui, frame)
  background = RatatuiRuby::Widgets::Block.new(
    borders: [],
    style: {
      bg: AppConfig.settings.theme_item(:background)
    }
  )

  frame.render_widget(background, frame.area)
end
