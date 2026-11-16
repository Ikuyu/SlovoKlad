class PopupManager
  attr_reader :active_popup, :popup_callback

  def initialize
    @active_popup = nil
    @popup_callback = nil
  end

  # Activeer pop-up (type can be :info, :confirm, or :form)
  def show(title:, message: nil, type: :info, fields: nil, alignment: :center, scroll_y: 0, &block)
    @active_popup = {
      title: title,
      message: message,
      type: type,
      fields: fields,       # Expected: Hash van invoervelden
      alignment: alignment, # Toegevoegd voor uitlijning
      scroll_y: scroll_y    # Toegevoegd voor scroll-positie tracking
    }
    @popup_callback = block
  end

  def submit(form_data = {})
    return unless active?

    # 🎯 FIX: Use the correct instance variable (@popup_callback)!
    block_outcome = if @popup_callback
                      @popup_callback.call(form_data)
                    else
                      true
                    end

    # =========================================================================
    # 🎯 THE ABSOLUTE FIREWALL: If the block returns 'false',
    # refuse to close the popup. The form remains open and intact.
    # =========================================================================
    return false if block_outcome == false

    # Close the popup cleanly only when validation succeeds (true or nil).
    close
    true
  end

  def close
    @active_popup = nil
    @popup_callback = nil
  end

  def active?
    !@active_popup.nil?
  end
end
