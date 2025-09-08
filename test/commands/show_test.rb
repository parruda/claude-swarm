# frozen_string_literal: true

require "test_helper"

module ClaudeSwarm
  module Commands
    class ShowTest < Minitest::Test
      def setup
        @run_dir = ClaudeSwarm.joined_run_dir
        @test_session_dir = ClaudeSwarm.joined_sessions_dir("test-project", "test-session-123")

        # Clean up any existing test data
        FileUtils.rm_rf(@run_dir)
        FileUtils.rm_rf(@test_session_dir)

        # Create test session directory structure
        FileUtils.mkdir_p(@test_session_dir)
        FileUtils.mkdir_p(@run_dir)
      end

      def teardown
        FileUtils.rm_rf(@run_dir)
        FileUtils.rm_rf(@test_session_dir)
      end

      def test_execute_with_non_existent_session
        assert_raises(SystemExit) do
          capture_io { Commands::Show.new.execute("non-existent-session") }
        end
      end

      def test_execute_with_simple_hierarchy
        setup_test_session_with_hierarchy

        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        assert_match(/Session: test-session-123/, output)
        assert_match(/Session Path: #{Regexp.escape(@test_session_dir)}/, output)
        assert_match(/Swarm: Test Swarm/, output)
        assert_match(/Total Cost: \$0\.3579/, output)
        assert_match(/Instance Hierarchy/, output)
        assert_match(/├─ orchestrator \[main\]/, output)
        assert_match(/└─ worker/, output)
      end

      def test_execute_with_interactive_main_instance
        setup_test_session_with_hierarchy

        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        # Main instance should show n/a for cost
        assert_includes(output, "Cost: n/a (interactive)")
        # Check the whole pattern including the main marker
        assert_includes(output, "orchestrator [main]")

        # Should show note about interactive mode
        assert_match(/Note: Main instance.*cost is not tracked in interactive mode/, output)
      end

      def test_execute_with_cost_data_for_main
        # Create session with cost data for main instance
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "orchestrator",
            "instances" => {
              "orchestrator" => { "directory" => "." },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)

        # Create JSON log with cost for main instance
        json_log = {
          "instance" => "orchestrator",
          "instance_id" => "orchestrator_123",
          "event" => { "type" => "result", "cost_usd" => 0.5 },
        }.to_json
        File.write(File.join(@test_session_dir, "session.log.json"), json_log)

        # Create symlink
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        # Should not show the interactive note
        refute_match(/Note: Main instance.*cost is not tracked/, output)
        # Total cost should not say "excluding main instance"
        assert_match(/Total Cost: \$0\.5000$/, output)
      end

      def test_execute_with_root_directory
        setup_test_session_with_hierarchy
        File.write(File.join(@test_session_dir, "root_directory"), "/home/user/project")

        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        assert_match(%r{Root Directory: /home/user/project}, output)
      end

      def test_find_session_in_all_sessions
        # Create session without symlink
        setup_test_session_with_hierarchy
        # Remove the symlink to test finding via directory search
        FileUtils.rm_f(File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        assert_match(/Session: test-session-123/, output)
        assert_match(/Session Path: #{Regexp.escape(@test_session_dir)}/, output)
      end

      def test_session_path_display
        setup_test_session_with_hierarchy

        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        # Verify that the session path is displayed correctly
        assert_match(/Session Path: #{Regexp.escape(@test_session_dir)}/, output)
      end

      def test_display_complex_hierarchy
        # Create complex hierarchy with multiple levels
        config = {
          "swarm" => {
            "name" => "Complex Swarm",
            "main" => "orchestrator",
            "instances" => {
              "orchestrator" => { "directory" => "." },
              "frontend" => { "directory" => "./frontend" },
              "backend" => { "directory" => "./backend" },
              "database" => { "directory" => "./db" },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)

        # Create JSON log with complex relationships
        json_logs = [
          # Orchestrator calls frontend and backend
          {
            "instance" => "frontend",
            "instance_id" => "frontend_123",
            "calling_instance" => "orchestrator",
            "calling_instance_id" => "orchestrator_123",
            "event" => { "type" => "request" },
          },
          {
            "instance" => "backend",
            "instance_id" => "backend_123",
            "calling_instance" => "orchestrator",
            "calling_instance_id" => "orchestrator_123",
            "event" => { "type" => "request" },
          },
          # Backend calls database
          {
            "instance" => "database",
            "instance_id" => "database_123",
            "calling_instance" => "backend",
            "calling_instance_id" => "backend_123",
            "event" => { "type" => "request" },
          },
          # Add some results
          {
            "instance" => "frontend",
            "instance_id" => "frontend_123",
            "event" => { "type" => "result", "cost_usd" => 0.1 },
          },
          {
            "instance" => "backend",
            "instance_id" => "backend_123",
            "event" => { "type" => "result", "cost_usd" => 0.2 },
          },
          {
            "instance" => "database",
            "instance_id" => "database_123",
            "event" => { "type" => "result", "cost_usd" => 0.05 },
          },
        ].map(&:to_json).join("\n")

        File.write(File.join(@test_session_dir, "session.log.json"), json_logs)
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        # Check hierarchy structure
        assert_match(/├─ orchestrator/, output)
        assert_match(/└─ frontend/, output)
        assert_match(/└─ backend/, output)
        assert_match(/└─ database/, output)

        # Check costs directly in output
        assert_includes(output, "Cost: $0.1000", "Frontend cost not found in output")
        assert_includes(output, "Cost: $0.2000", "Backend cost not found in output")
        assert_includes(output, "Cost: $0.0500", "Database cost not found in output")
      end

      def test_parse_malformed_json_lines
        setup_test_session_with_hierarchy

        # Add malformed JSON line
        File.open(File.join(@test_session_dir, "session.log.json"), "a") do |f|
          f.puts "this is not json"
          f.puts '{"invalid": json'
        end

        # Should still work with valid lines
        output = capture_io { Commands::Show.new.execute("test-session-123") }.first

        assert_match(/Session: test-session-123/, output)
      end

      private

      def setup_test_session_with_hierarchy
        # Create test config
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "orchestrator",
            "instances" => {
              "orchestrator" => { "directory" => "." },
              "worker" => { "directory" => "./worker" },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)

        # Create test JSON log with hierarchy
        json_logs = [
          {
            "instance" => "worker",
            "instance_id" => "worker_123",
            "calling_instance" => "orchestrator",
            "calling_instance_id" => "orchestrator_123",
            "event" => { "type" => "request" },
          },
          {
            "instance" => "worker",
            "instance_id" => "worker_123",
            "event" => { "type" => "result", "cost_usd" => 0.3579 },
          },
        ].map(&:to_json).join("\n")

        File.write(File.join(@test_session_dir, "session.log.json"), json_logs)

        # Create symlink
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))
      end
    end
  end
end
