# frozen_string_literal: true

module ClaudeSwarm
  class BaseExecutor
    attr_reader :session_id, :last_response, :working_directory, :logger, :session_path, :session_json_path, :instance_info

    def initialize(working_directory: Dir.pwd, model: nil, mcp_config: nil, vibe: false,
      instance_name: nil, instance_id: nil, calling_instance: nil, calling_instance_id: nil,
      claude_session_id: nil, additional_directories: [], debug: false)
      @working_directory = working_directory
      @additional_directories = additional_directories
      @model = model
      @mcp_config = mcp_config
      @vibe = vibe
      @session_id = claude_session_id
      @last_response = nil
      @instance_name = instance_name
      @instance_id = instance_id
      @calling_instance = calling_instance
      @calling_instance_id = calling_instance_id
      @debug = debug

      # Setup static info strings for logging
      @instance_info = build_info(@instance_name, @instance_id)
      @caller_info = build_info(@calling_instance, @calling_instance_id)
      @caller_to_instance = "#{@caller_info} -> #{instance_info}:"
      @instance_to_caller = "#{instance_info} -> #{@caller_info}:"

      # Setup logging
      setup_logging

      # Setup static event templates
      setup_event_templates
    end

    def execute(_prompt, _options = {})
      raise NotImplementedError, "Subclasses must implement the execute method"
    end

    def reset_session
      @session_id = nil
      @last_response = nil
    end

    def has_session?
      !@session_id.nil?
    end

    protected

    def build_info(name, id)
      return name unless id

      "#{name} (#{id})"
    end

    def setup_logging
      # Use session path from environment (required)
      @session_path = SessionPath.from_env
      SessionPath.ensure_directory(@session_path)

      # Initialize session JSON path
      @session_json_path = File.join(@session_path, "session.log.json")

      # Create logger with session.log filename
      log_filename = "session.log"
      log_path = File.join(@session_path, log_filename)
      log_level = @debug ? :debug : :info
      @logger = Logger.new(log_path, level: log_level, progname: @instance_name)

      logger.info { "Started #{self.class.name} for instance: #{instance_info}" }
    end

    def setup_event_templates
      @log_request_event_template = {
        type: "request",
        from_instance: @calling_instance,
        from_instance_id: @calling_instance_id,
        to_instance: @instance_name,
        to_instance_id: @instance_id,
      }.freeze

      @session_json_entry_template = {
        instance: @instance_name,
        instance_id: @instance_id,
        calling_instance: @calling_instance,
        calling_instance_id: @calling_instance_id,
      }.freeze
    end

    def log_request(prompt)
      logger.info { "#{@caller_to_instance} \n---\n#{prompt}\n---" }

      # Merge dynamic data with static template
      event = @log_request_event_template.merge(
        prompt: prompt,
        timestamp: Time.now.iso8601,
      )

      append_to_session_json(event)
    end

    def log_response(response)
      logger.info do
        "($#{response["total_cost"]} - #{response["duration_ms"]}ms) #{@instance_to_caller} \n---\n#{response["result"]}\n---"
      end
    end

    def append_to_session_json(event)
      # Use file locking to ensure thread-safe writes
      File.open(@session_json_path, File::WRONLY | File::APPEND | File::CREAT) do |file|
        file.flock(File::LOCK_EX)

        # Merge dynamic data with static template
        entry = @session_json_entry_template.merge(
          timestamp: Time.now.iso8601,
          event: event,
        )

        # Write as single line JSON (JSONL format)
        file.puts(entry.to_json)

        file.flock(File::LOCK_UN)
      end
    rescue StandardError => e
      logger.error { "Failed to append to session JSON: #{e.message}" }
      raise
    end

    class ExecutionError < StandardError; end
    class ParseError < StandardError; end
  end
end
