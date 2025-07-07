# frozen_string_literal: true

module ClaudeSwarm
  module SystemUtils
    def system!(*args)
      success = system(*args)
      unless success
        exit_status = $CHILD_STATUS&.exitstatus || 1
        command_str = args.size == 1 ? args.first : args.join(" ")
        warn("❌ Command failed with exit status: #{exit_status}")
        raise Error, "Command failed with exit status #{exit_status}: #{command_str}"
      end
      success
    end
  end
end
