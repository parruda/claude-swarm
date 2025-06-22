# frozen_string_literal: true

require "json"
require "logger"
require "fileutils"

module ClaudeSwarm
  # Abstract base class for executors (ClaudeCodeExecutor and LlmExecutor)
  class BaseExecutor
    attr_reader :session_id, :last_response, :working_directory, :logger, :session_path

    def initialize(working_directory: Dir.pwd, instance_name: nil, instance_id: nil,
                   calling_instance: nil, calling_instance_id: nil, **options)
      @working_directory = working_directory
      @instance_name = instance_name
      @instance_id = instance_id
      @calling_instance = calling_instance
      @calling_instance_id = calling_instance_id
      @session_id = options[:session_id]
      @last_response = nil

      # Store additional options for subclasses
      @options = options

      # Setup logging
      setup_logging
    end

    # Abstract method - must be implemented by subclasses
    def execute(prompt, options = {})
      raise NotImplementedError, "Subclasses must implement the execute method"
    end

    def reset_session
      @session_id = nil
      @last_response = nil
    end

    def has_session?
      !@session_id.nil?
    end

    private

    def setup_logging
      # Use session path from environment (required)
      @session_path = SessionPath.from_env
      SessionPath.ensure_directory(@session_path)

      # Create logger with session.log filename
      log_filename = "session.log"
      log_path = File.join(@session_path, log_filename)
      @logger = Logger.new(log_path)
      @logger.level = Logger::INFO

      # Custom formatter for better readability
      @logger.formatter = proc do |severity, datetime, _progname, msg|
        "[#{datetime.strftime("%Y-%m-%d %H:%M:%S.%L")}] [#{severity}] #{msg}\n"
      end

      return unless @instance_name

      instance_info = @instance_name
      instance_info += " (#{@instance_id})" if @instance_id
      @logger.info("Started #{self.class.name.split("::").last} for instance: #{instance_info}")
    end

    def append_to_session_json(event)
      json_filename = "session.log.json"
      json_path = File.join(@session_path, json_filename)

      # Use file locking to ensure thread-safe writes
      File.open(json_path, File::WRONLY | File::APPEND | File::CREAT) do |file|
        file.flock(File::LOCK_EX)

        # Create entry with metadata
        entry = {
          instance: @instance_name,
          instance_id: @instance_id,
          calling_instance: @calling_instance,
          calling_instance_id: @calling_instance_id,
          timestamp: Time.now.iso8601,
          event: event
        }

        # Write as single line JSON (JSONL format)
        file.puts(entry.to_json)

        file.flock(File::LOCK_UN)
      end
    rescue StandardError => e
      @logger.error("Failed to append to session JSON: #{e.message}")
      raise
    end

    # Common error classes that can be used by subclasses
    class ExecutionError < StandardError; end
    class ParseError < StandardError; end
  end
end
