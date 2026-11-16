class RatinCheckbox
  attr_accessor :is_focused, :cursor_index
  attr_reader :checked, :label

  def initialize(label:, checked: false)
    @label = label.to_s
    @checked = !!checked
    @is_focused = false
    @cursor_index = 0
  end

  def checked?
    @checked
  end

  def active?
    @checked
  end

  def value
    @checked ? :checked : :unchecked
  end

  def toggle
    @checked = !@checked
  end

  def get_text
    @checked ? 'true' : 'false'
  end

  def text
    @checked ? '[x]' : '[ ]'
  end

  def display_text
    "#{text} #{@label}"
  end

  def handle_key(key, _modifiers = [])
    key_str = key.to_s.strip.downcase

    if key_str == 'space' || key == ' ' || key == :space
      toggle
      true
    else
      false
    end
  end
end
