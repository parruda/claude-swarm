# frozen_string_literal: true

module ClaudeSwarm
  module SystemUtils
    def system!(*args, **options)
      system(*args, **options)
      handle_command_failure(last_status, args)
    end

    def system_with_pid!(*args, **options)
      # Spawn the process - by default, inherits the parent's I/O
      pid = Process.spawn(*args, **options)

      # Yield the PID to the block if given
      yield(pid) if block_given?

      # Wait for the process to complete
      _, status = Process.wait2(pid)

      # Check the exit status
      handle_command_failure(status, args)
    end

    def last_status
      $CHILD_STATUS
    end

    private

    def handle_command_failure(status, args) # rubocop:disable Naming/PredicateMethod
      return true if status&.success?

      exit_status = status&.exitstatus || 1
      command_str = args.size == 1 ? args.first : args.join(" ")

      if exit_status == 143 # timeout command exit status = 128 + 15 (SIGTERM)
        warn("⏱️ Command timeout: #{command_str}")
      else
        warn("❌ Command failed with exit status: #{exit_status}")
        raise Error, "Command failed with exit status #{exit_status}: #{command_str}"
      end

      false
    end
  end
end
