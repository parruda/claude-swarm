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
      # In tests, use the session path from env if available, otherwise use a temp path
      @session_path ||= if ENV["CLAUDE_SWARM_SESSION_PATH"]
        SessionPath.from_env
      else
        # This should only happen in unit tests
        Dir.pwd
      end
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

      # Only write settings file if there are settings to write
      return if settings.empty?

      # Write settings file
      File.write(settings_path(name), JSON.pretty_generate(settings))
    end
  end
end
