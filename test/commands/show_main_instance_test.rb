# frozen_string_literal: true

require "test_helper"
require "claude_swarm/commands/show"
require "tempfile"
require "yaml"
require "json"

module ClaudeSwarm
  module Commands
    class ShowMainInstanceTest < Minitest::Test
      def setup
        @tmpdir = Dir.mktmpdir
        @session_id = "test-session-123"
        @session_path = File.join(@tmpdir, @session_id)
        FileUtils.mkdir_p(@session_path)
      end

      def teardown
        FileUtils.rm_rf(@tmpdir)
      end

      def test_show_with_main_instance_token_costs
        # Create config
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "lead_developer",
          },
        }
        File.write(File.join(@session_path, "config.yml"), config.to_yaml)

        # Create session log with main instance token costs and other instance costs
        json_log = [
          # Main instance message with Opus model
          {
            "instance" => "lead_developer",
            "instance_id" => "main",
            "event" => {
              "type" => "assistant",
              "message" => {
                "model" => "claude-opus-4-1-20250805",
                "usage" => {
                  "input_tokens" => 1000,
                  "output_tokens" => 500,
                  "cache_creation_input_tokens" => 0,
                  "cache_read_input_tokens" => 0,
                },
              },
            },
          },
          # Another main instance message
          {
            "instance" => "lead_developer",
            "instance_id" => "main",
            "event" => {
              "type" => "assistant",
              "message" => {
                "model" => "claude-opus-4-1-20250805",
                "usage" => {
                  "input_tokens" => 2000,
                  "output_tokens" => 1000,
                },
              },
            },
          },
          # Other instance with cost_usd
          {
            "instance" => "worker",
            "instance_id" => "worker_123",
            "calling_instance" => "lead_developer",
            "calling_instance_id" => "main",
            "event" => { "type" => "result", "cost_usd" => 0.05 },
          },
        ].map(&:to_json).join("\n")
        File.write(File.join(@session_path, "session.log.json"), json_log)

        # Create run symlink in the expected location
        run_dir = ClaudeSwarm.joined_run_dir
        FileUtils.mkdir_p(run_dir)
        symlink_path = ClaudeSwarm.joined_run_dir(@session_id)
        File.unlink(symlink_path) if File.symlink?(symlink_path)
        File.symlink(@session_path, symlink_path)

        begin
          output = capture_io { Show.new.execute(@session_id) }.first

          # Check that main instance is shown with cost
          assert_match(/lead_developer \[main\]/, output)

          # Calculate expected main instance cost:
          # First message: 1000/1M * $15 + 500/1M * $75 = $0.015 + $0.0375 = $0.0525
          # Second message: 2000/1M * $15 + 1000/1M * $75 = $0.03 + $0.075 = $0.105
          # Total main: $0.0525 + $0.105 = $0.1575
          # Worker: $0.05
          # Grand total: $0.1575 + $0.05 = $0.2075

          # Check total cost includes main instance
          assert_match(/Total Cost: \$0\.2075/, output)

          # Should NOT show "(excluding main instance)" message
          refute_match(/excluding main instance/, output)

          # Check that the main instance shows cost (not "n/a")
          refute_match(%r{n/a \(interactive\)}, output)
        ensure
          # Clean up symlink
          File.unlink(symlink_path) if File.symlink?(symlink_path)
        end
      end

      def test_show_without_main_instance_costs
        # Create config
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "lead_developer",
          },
        }
        File.write(File.join(@session_path, "config.yml"), config.to_yaml)

        # Create session log with only other instance costs (no main instance data)
        json_log = [
          {
            "instance" => "worker",
            "instance_id" => "worker_123",
            "event" => { "type" => "result", "cost_usd" => 0.10 },
          },
        ].map(&:to_json).join("\n")
        File.write(File.join(@session_path, "session.log.json"), json_log)

        # Create run symlink in the expected location
        run_dir = ClaudeSwarm.joined_run_dir
        FileUtils.mkdir_p(run_dir)
        symlink_path = ClaudeSwarm.joined_run_dir(@session_id)
        File.unlink(symlink_path) if File.symlink?(symlink_path)
        File.symlink(@session_path, symlink_path)

        begin
          output = capture_io { Show.new.execute(@session_id) }.first

          # Should show "(excluding main instance)" when main has no cost data
          assert_match(/\$0\.1000 \(excluding main instance\)/, output)

          # Note about main instance not being tracked
          assert_match(/Note: Main instance \(lead_developer\) cost is not tracked/, output)
        ensure
          # Clean up symlink
          File.unlink(symlink_path) if File.symlink?(symlink_path)
        end
      end
    end
  end
end
