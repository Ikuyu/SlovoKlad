module SpeechHandler
  def speak_term(term, context_receiver = self)
    return if term.to_s.strip.empty?

    settings = AppConfig.settings
    opts = CliHandler.options

    begin
      SoundManager.say(
        term.to_s,
        command: opts[:speech_command],
        voice: opts[:speech_voice],
        lang: opts[:speech_lang]
      )
    rescue ArgumentError => e
      msg_key = case e.message
                when 'speech_not_configured' then :statusbar_speech_command_not_configured
                when 'speech_missing_placeholders' then :statusbar_speech_command_missing_placeholders
                else :statusbar_speech_command_invalid
                end

      context_receiver.trigger_statusbar_message(
        "#{settings.language_string(msg_key)}!",
        type: e.message == 'speech_not_configured' ? :info : :error,
        beep: true,
        expires: true
      )
    rescue Errno::ENOENT => e
      context_receiver.trigger_statusbar_message(
        "#{settings.language_string(:statusbar_speech_command_not_found)}: #{e.message}",
        type: :warn,
        beep: true,
        expires: true
      )
    end
  end
end
