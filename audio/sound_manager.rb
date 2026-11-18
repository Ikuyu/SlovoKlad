# https://soundinator.net

require 'native_audio'
require 'shellwords'

module SoundManager
  class << self
    def speaking?
      @speaking ||= false
    end

    def speaking=(value)
      @speaking = value
      # 🎯 Zodra het spreken klaar is, starten we direct de wachtrij als die er is!
      process_queue unless value
    end

    def active_sources
      @active_sources ||= {}
    end

    def normalize_word(word, lang:)
      text = word.unicode_normalize(:nfd)

      if lang.to_s.downcase.start_with?('ru')
        text = text.gsub(/[\u0300\u0301]/, '') # Russische klemtoontekens
      end

      text.unicode_normalize(:nfc)
    end

    def say(word, command:, voice: nil, lang: nil)
      raise ArgumentError, 'speech_not_configured' if command.to_s.empty?

      # 🎯 Als we al aan het spreken zijn, slaan we dit woord op in de wachtrij.
      # Druk je twee keer snel, dan wordt de 'pending' netjes overschreven naar het nieuwste woord.
      if speaking?
        @pending_speech = { word: word, command: command, voice: voice, lang: lang }
        return
      end

      execute_say(word, command: command, voice: voice, lang: lang)
    end

    private

    def execute_say(word, command:, voice: nil, lang: nil)
      self.speaking = true

      normalized_word = normalize_word(word, lang: lang)
      template_args = Shellwords.split(command)

      if command.include?('say') || command.include?('espeak')
        unless template_args.include?('{text}') && template_args.include?('{voice}')
          self.speaking = false
          raise ArgumentError, 'speech_missing_placeholders'
        end
        if voice.to_s.empty?
          self.speaking = false
          raise ArgumentError, 'speech_not_configured'
        end
      else
        unless template_args.include?('{text}')
          self.speaking = false
          raise ArgumentError, 'speech_missing_placeholders'
        end
      end

      final_command = command.dup
      final_command.gsub!('{text}', normalized_word)
      final_command.gsub!('{voice}', voice.to_s) if voice
      final_command.gsub!('{lang}', lang.to_s) if lang

      Thread.new do
        system('bash', '-c', final_command)
      ensure
        self.speaking = false
      end

      nil
    rescue Errno::ENOENT => e
      self.speaking = false
      raise Errno::ENOENT, e.message
    rescue ArgumentError => e
      self.speaking = false
      raise ArgumentError, e.message.include?('speech_') ? e.message : 'speech_command_invalid'
    end

    def process_queue
      return unless @pending_speech

      args = @pending_speech
      @pending_speech = nil
      execute_say(args[:word], command: args[:command], voice: args[:voice], lang: args[:lang])
    end

    public

    def play(type)
      normalized_type = type.to_sym

      filename =
        case normalized_type
        when :right then 'right.mp3'
        when :wrong then 'wrong.mp3'
        when :finished then 'finished.mp3'
        when :failed then 'failed.mp3'
        when :select then 'select.mp3'
        when :exclude then 'exclude.mp3'
        when :toggle then 'toggle.mp3'
        when :off then 'off.mp3'
        when :cycle then 'cycle.mp3'
        when :start then 'start.mp3'
        when :switch then 'switch.mp3'
        when :chime then 'chime.mp3'
        when :draw_card then 'draw_card.mp3'
        end

      return unless filename

      path = File.expand_path("audio/#{filename}", Dir.pwd)
      return unless File.file?(path)

      clip = NativeAudio::Clip.new(path)
      source = NativeAudio::AudioSource.new(clip)

      source.play

      active_sources[normalized_type] = source

      clip
    rescue StandardError => e
      warn "Audio play error: #{e.class}: #{e.message}"
      nil
    end

    def stop(type)
      source = active_sources.delete(type.to_sym)
      return false unless source

      source.stop
      true
    rescue StandardError => e
      warn "Audio stop error: #{e.class}: #{e.message}"
      false
    end
  end
end
