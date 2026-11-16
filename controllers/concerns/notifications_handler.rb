module NotificationHandler
  def trigger_system_beep
    # 1. Start de hoorbare BEEP/Bell asynchroon op de achtergrond
    if RUBY_PLATFORM =~ /darwin/
      # macOS: Native AppleScript beep (omzeilt terminal-beperkingen)
      system("osascript -e 'beep 1' &")
    elsif RUBY_PLATFORM =~ /mswin|mingw|cygwin/
      # Windows: PowerShell inline .NET console frequency beep (werkt ALTIJD)
      system('powershell -Command "[Console]::Beep(800, 150)" &')
    else
      # Linux / Unix: Fallback naar aplay, paplay, of spd-say indien beschikbaar
      begin
        system("spd-say 'beep' &")
      rescue StandardError
        nil
      end
      print "\a"
      $stdout.flush
    end
  end

  def trigger_statusbar_message(msg, type: :error, beep: true, expires: true)
    # 1. Start de hoorbare BEEP/Bell asynchroon op de achtergrond

    if beep && defined?(AppConfig) && AppConfig.settings.respond_to?(:beeps) && AppConfig.settings.beeps == true
      trigger_system_beep
    end

    msg_type = case type.to_s.downcase.to_sym
               when :info
                 'i'  # Resulteert in [i]
               when :warning
                 '!'  # Resulteert in [!]
               when :error
                 'x'  # Resulteert in [x]
               else
                 '!'  # Veilige fallback
               end

    msg_str = format(
      msg,
      app_name: @app_name
    )

    @status_message = "[#{msg_type}] #{msg_str}"

    @status_message_expires_at = if expires
                                   Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3.5
                                 else
                                   nil
                                 end

    #     begin
    #       if RUBY_PLATFORM =~ /darwin/
    #         # --- MACOS (AppleScript Notificatie) ---
    #         system("osascript -e 'display notification \"#{msg_str}\" with title \"#{msg_notify}\"' &")
    #
    #       elsif RUBY_PLATFORM =~ /linux/ || RUBY_PLATFORM =~ /freebsd/
    #         # --- LINUX (Universal libnotify / notify-send) ---
    #         system("notify-send \"#{msg_notify}\" \"#{msg_str}\" -i dialog-error &")
    #
    #       elsif RUBY_PLATFORM =~ /mswin|mingw|cygwin/
    #         # --- WINDOWS (Native PowerShell Toast Notification) ---
    #         ps_command = "[void] [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms'); " \
    #                      '$objNotifyIcon = New-Object System.Windows.Forms.NotifyIcon; ' \
    #                      '$objNotifyIcon.Icon = [System.Drawing.SystemIcons]::Error; ' \
    #                      "$objNotifyIcon.BalloonTipIcon = 'Error'; " \
    #                      "$objNotifyIcon.BalloonTipTitle = '#{msg_notify}'; " \
    #                      "$objNotifyIcon.BalloonTipText = '#{msg_str}'; " \
    #                      '$objNotifyIcon.Visible = $True; ' \
    #                      '$objNotifyIcon.ShowBalloonTip(5000)'
    #
    #         system("start /b powershell -Command \"#{ps_command}\"")
    #       end
    #     rescue StandardError
    #       nil
    #     end

    # Herteken de interface direct schoon
    @tree.refresh_nodes if @tree.respond_to?(:refresh_nodes)
  end

  # Once the renderer has shown the message, the next keypress clears it immediately
  # instead of waiting for the timer.
  def active_statusbar_message
    return nil if @status_message.nil?

    if @status_message_expires_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @status_message_expires_at
      @status_message = nil
      @status_message_expires_at = nil
      return nil
    end

    @status_message
  end
end
