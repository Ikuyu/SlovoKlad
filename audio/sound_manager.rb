# https://soundinator.net

# Unused or alternate sound files have filenames that start with an underscore.

require 'native_audio'

module SoundManager
  class << self
    def active_sources
      @active_sources ||= {}
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
