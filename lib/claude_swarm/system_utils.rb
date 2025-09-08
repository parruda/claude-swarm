# frozen_string_literal: true

module ClaudeSwarm
  module SystemUtils
    def system!(*args, chdir: nil)
      # Build options hash for system/spawn
      options = {}
      options[:chdir] = chdir if chdir

      # Call system with options if chdir is provided, otherwise use original behavior
      success = if chdir
        system(*args, **options)
      else
        system(*args)
      end

      exit_status = $CHILD_STATUS&.exitstatus || 1

      unless success
        command_str = args.size == 1 ? args.first : args.join(" ")
        if exit_status == 143 # timeout command exit status = 128 + 15 (SIGTERM)
          warn("⏱️ Command timeout: #{command_str}")
        else
          warn("❌ Command failed with exit status: #{exit_status}")
          raise Error, "Command failed with exit status #{exit_status}: #{command_str}"
        end
      end
      success
    end
  end
end
