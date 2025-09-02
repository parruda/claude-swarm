# frozen_string_literal: true

module ClaudeSwarm
  class SettingsGenerator
    def initialize(configuration)
      @config = configuration
    end

    def generate_all
      ensure_session_directory

      @config.instances.each do |name, instance|
        generate_settings(name, instance)
      end
    end

    def settings_path(instance_name)
      File.join(session_path, "#{instance_name}_settings.json")
    end

    private

    def session_path
      @session_path ||= SessionPath.from_env
    end

    def ensure_session_directory
      # Session directory is already created by orchestrator
      # Just ensure it exists
      SessionPath.ensure_directory(session_path)
    end

    def generate_settings(name, instance)
      settings = {}

      # Add hooks if configured
      if instance[:hooks] && !instance[:hooks].empty?
        settings["hooks"] = instance[:hooks]
      end

      # Add SessionStart hook for main instance to capture transcript path
      if name == @config.main_instance
        session_start_hook = build_session_start_hook

        # Initialize hooks if not present
        settings["hooks"] ||= {}
        settings["hooks"]["SessionStart"] ||= []

        # Add our hook to the SessionStart hooks
        settings["hooks"]["SessionStart"] << session_start_hook
      end

      # Only write settings file if there are settings to write
      return if settings.empty?

      # Write settings file
      JsonHandler.write_file!(settings_path(name), settings)
    end

    def build_session_start_hook
      hook_script_path = File.expand_path("hooks/session_start_hook.rb", __dir__)
      # Pass session path as an argument since ENV may not be inherited
      session_path_arg = session_path

      {
        "matcher" => "startup",
        "hooks" => [
          {
            "type" => "command",
            "command" => "ruby #{hook_script_path} '#{session_path_arg}'",
            "timeout" => 5,
          },
        ],
      }
    end
  end
end
