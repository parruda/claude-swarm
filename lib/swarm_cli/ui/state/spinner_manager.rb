# frozen_string_literal: true

module SwarmCLI
  module UI
    module State
      # Manages active spinners with elapsed time display
      class SpinnerManager
        def initialize
          @active_spinners = {}
          @time_updaters = {}
        end

        # Start a spinner with elapsed time tracking
        #
        # @param key [Symbol, String] Unique key for this spinner
        # @param message [String] Spinner message
        # @param format [Symbol] Spinner format (:dots, :pulse, etc.)
        # @return [TTY::Spinner] The spinner instance
        def start(key, message, format: :dots)
          # Stop any existing spinner with this key
          stop(key) if @active_spinners[key]

          # Create spinner with elapsed time token
          spinner = TTY::Spinner.new(
            "[:spinner] #{message} (:elapsed)",
            format: format,
            hide_cursor: true,
          )

          spinner.auto_spin

          # Spawn thread to update elapsed time every 1 second
          # This is 10x slower than spinner animation (100ms), preventing flicker
          @time_updaters[key] = Thread.new do
            loop do
              elapsed = spinner.duration
              break unless elapsed

              formatted_time = format_duration(elapsed)
              spinner.update(elapsed: formatted_time)
              sleep(1.0) # 1s refresh rate - smooth without flicker
            rescue StandardError
              break
            end
          end

          @active_spinners[key] = spinner
          spinner
        end

        # Stop spinner with success
        #
        # @param key [Symbol, String] Spinner key
        # @param message [String] Success message
        def success(key, message = "completed")
          spinner = @active_spinners[key]
          return unless spinner

          # Kill time updater
          kill_updater(key)

          # Show final time
          final_time = format_duration(spinner.duration || 0)
          spinner.success("#{message} (#{final_time})")

          cleanup(key)
        end

        # Stop spinner with error
        #
        # @param key [Symbol, String] Spinner key
        # @param message [String] Error message
        def error(key, message = "failed")
          spinner = @active_spinners[key]
          return unless spinner

          # Kill time updater
          kill_updater(key)

          # Show final time
          final_time = format_duration(spinner.duration || 0)
          spinner.error("#{message} (#{final_time})")

          cleanup(key)
        end

        # Stop spinner without success/error (just stop)
        #
        # @param key [Symbol, String] Spinner key
        def stop(key)
          spinner = @active_spinners[key]
          return unless spinner

          kill_updater(key)
          spinner.stop
          cleanup(key)
        end

        # Stop all active spinners
        def stop_all
          @active_spinners.keys.each { |key| stop(key) }
        end

        # Check if a spinner is active
        #
        # @param key [Symbol, String] Spinner key
        # @return [Boolean]
        def active?(key)
          @active_spinners.key?(key)
        end

        # Pause all active spinners (for interactive debugging)
        #
        # This temporarily stops spinner animation while preserving state,
        # allowing interactive sessions like binding.irb to run cleanly.
        #
        # @return [void]
        def pause_all
          @active_spinners.each_value do |spinner|
            spinner.stop if spinner.spinning?
          end

          # Keep time updaters running (they'll safely handle stopped spinners)
        end

        # Resume all paused spinners
        #
        # Restarts spinner animation for all spinners that were paused.
        #
        # @return [void]
        def resume_all
          @active_spinners.each_value do |spinner|
            spinner.auto_spin unless spinner.spinning?
          end
        end

        private

        def kill_updater(key)
          updater = @time_updaters[key]
          return unless updater

          updater.kill if updater.alive?
          @time_updaters.delete(key)
        end

        def cleanup(key)
          @active_spinners.delete(key)
          @time_updaters.delete(key)
        end

        def format_duration(seconds)
          if seconds < 1
            "#{(seconds * 1000).round}ms"
          elsif seconds < 60
            "#{seconds.round}s"
          elsif seconds < 3600
            minutes = (seconds / 60).floor
            secs = (seconds % 60).round
            "#{minutes}m #{secs}s"
          else
            hours = (seconds / 3600).floor
            minutes = ((seconds % 3600) / 60).floor
            "#{hours}h #{minutes}m"
          end
        end
      end
    end
  end
end
