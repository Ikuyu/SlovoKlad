# https://soundinator.net

require 'native_audio'
require 'shellwords'

module SoundManager
  class << self
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

    def say(word, command:, voice:, lang: nil)
      raise ArgumentError, 'speech_not_configured' if command.to_s.empty? || voice.to_s.empty?

      normalized_word = normalize_word(word, lang: lang)
      template_args = Shellwords.split(command)

      required_placeholders = %w[{text} {voice}]
      missing_placeholders = required_placeholders.reject do |placeholder|
        template_args.include?(placeholder)
      end

      raise ArgumentError, 'speech_missing_placeholders' unless missing_placeholders.empty?

      args = template_args.flat_map do |arg|
        case arg
        when '{text}'  then [normalized_word]
        when '{voice}' then [voice]
        when '{lang}'  then lang ? [lang] : [] # Alleen meesturen als lang aanwezig is
        else
          [arg]
        end
      end

      pid = spawn(*args)
      Process.detach(pid)
    rescue Errno::ENOENT => e
      raise Errno::ENOENT, e.message
    rescue ArgumentError => e
      raise ArgumentError, e.message.include?('speech_') ? e.message : 'speech_command_invalid'
    end

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
