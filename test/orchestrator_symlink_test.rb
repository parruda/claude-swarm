# frozen_string_literal: true

require "test_helper"

module ClaudeSwarm
  class OrchestratorSymlinkTest < Minitest::Test
    def setup
      @config = mock_configuration
      @generator = mock_generator
      @session_path = File.join(Dir.tmpdir, "claude-swarm-test-#{Time.now.to_i}")
      @run_dir = ClaudeSwarm.joined_run_dir

      FileUtils.mkdir_p(@session_path)
      FileUtils.rm_rf(@run_dir)

      # Store original ENV
      @original_env = ENV["CLAUDE_SWARM_SESSION_PATH"]

      # Mock SessionPath to return our test path
      SessionPath.stub(:generate, @session_path) do
        SessionPath.stub(:ensure_directory, nil) do
          # Set ENV for SettingsGenerator
          ENV["CLAUDE_SWARM_SESSION_PATH"] = @session_path
          @orchestrator = Orchestrator.new(@config, @generator)
        end
      end
    end

    def teardown
      FileUtils.rm_rf(@session_path)
      FileUtils.rm_rf(@run_dir)
      # Restore original ENV
      if @original_env
        ENV["CLAUDE_SWARM_SESSION_PATH"] = @original_env
      else
        ENV.delete("CLAUDE_SWARM_SESSION_PATH")
      end
    end

    def test_create_run_symlink_creates_directory
      @orchestrator.instance_variable_set(:@session_path, @session_path)
      @orchestrator.send(:create_run_symlink)

      assert(File.directory?(@run_dir))
    end

    def test_create_run_symlink_creates_symlink
      @orchestrator.instance_variable_set(:@session_path, @session_path)
      @orchestrator.send(:create_run_symlink)

      session_id = File.basename(@session_path)
      symlink_path = File.join(@run_dir, session_id)

      assert(File.symlink?(symlink_path))
      assert_equal(@session_path, File.readlink(symlink_path))
    end

    def test_create_run_symlink_replaces_existing
      @orchestrator.instance_variable_set(:@session_path, @session_path)

      # Create existing symlink
      FileUtils.mkdir_p(@run_dir)
      session_id = File.basename(@session_path)
      symlink_path = File.join(@run_dir, session_id)
      File.symlink("/old/path", symlink_path)

      # Create new symlink
      @orchestrator.send(:create_run_symlink)

      assert_equal(@session_path, File.readlink(symlink_path))
    end

    def test_create_run_symlink_handles_nil_session_path
      @orchestrator.instance_variable_set(:@session_path, nil)

      # Should not raise error
      @orchestrator.send(:create_run_symlink)
    end

    def test_cleanup_run_symlink_removes_symlink
      @orchestrator.instance_variable_set(:@session_path, @session_path)

      # Create symlink first
      @orchestrator.send(:create_run_symlink)
      session_id = File.basename(@session_path)
      symlink_path = File.join(@run_dir, session_id)

      assert_path_exists(symlink_path)

      # Clean up
      @orchestrator.send(:cleanup_run_symlink)

      refute_path_exists(symlink_path)
    end

    def test_cleanup_run_symlink_handles_missing_symlink
      @orchestrator.instance_variable_set(:@session_path, @session_path)

      # Should not raise error even if symlink doesn't exist
      @orchestrator.send(:cleanup_run_symlink)
    end

    def test_cleanup_run_symlink_handles_nil_session_path
      @orchestrator.instance_variable_set(:@session_path, nil)

      # Should not raise error
      @orchestrator.send(:cleanup_run_symlink)
    end

    def test_start_creates_symlink_for_new_session
      # Mock all the start dependencies
      @orchestrator.stub(:save_swarm_config_path, nil) do
        @generator.stub(:generate_all, nil) do
          @orchestrator.instance_variable_get(:@settings_generator).stub(:generate_all, nil) do
            @orchestrator.stub(:build_main_command, ["echo", "test"]) do
              @orchestrator.stub(:system_with_pid!, lambda { |*_args, &block|
                block&.call(12345)
                true
              }) do
                @orchestrator.stub(:cleanup_processes, nil) do
                  @orchestrator.stub(:cleanup_run_symlink, nil) do
                    @orchestrator.stub(:cleanup_worktrees, nil) do
                      capture_io { @orchestrator.start }

                      # Verify symlink was created
                      session_id = File.basename(@session_path)
                      symlink_path = File.join(@run_dir, session_id)

                      assert(File.symlink?(symlink_path), "Symlink should exist at #{symlink_path}")
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    def test_start_creates_symlink_for_restored_session
      restore_path = @session_path # Use our test session path

      # Set ENV for restoration
      ENV["CLAUDE_SWARM_SESSION_PATH"] = restore_path
      @orchestrator = Orchestrator.new(@config, @generator, restore_session_path: restore_path)

      # Mock start dependencies
      @generator.stub(:generate_all, nil) do
        @orchestrator.instance_variable_get(:@settings_generator).stub(:generate_all, nil) do
          @orchestrator.stub(:build_main_command, ["echo", "test"]) do
            @orchestrator.stub(:system_with_pid!, lambda { |*_args, &block|
              block&.call(12345)
              true
            }) do
              @orchestrator.stub(:cleanup_processes, nil) do
                @orchestrator.stub(:cleanup_run_symlink, nil) do
                  @orchestrator.stub(:cleanup_worktrees, nil) do
                    capture_io { @orchestrator.start }

                    # Verify symlink was created for restored session
                    session_id = File.basename(restore_path)
                    symlink_path = File.join(@run_dir, session_id)

                    assert(File.symlink?(symlink_path), "Symlink should exist at #{symlink_path}")
                  end
                end
              end
            end
          end
        end
      end
    end

    private

    def mock_configuration
      MockConfiguration.new
    end

    def mock_generator
      MockGenerator.new
    end

    # Mock classes
    class MockProcessTracker
      def cleanup_all; end
    end

    class MockConfiguration
      attr_reader :swarm_name, :main_instance, :config_path, :base_dir

      def initialize
        @swarm_name = "Test Swarm"
        @main_instance = "leader"
        @config_path = "claude-swarm.yml"
        @base_dir = Dir.pwd
      end

      def main_instance_config
        {
          directory: ".",
          directories: ["."],
          model: "opus",
          connections: [],
          allowed_tools: ["Read", "Write"],
          prompt: nil,
        }
      end

      def instances
        {
          "leader" => {
            directory: ".",
            directories: ["."],
            model: "opus",
            connections: [],
            allowed_tools: ["Read", "Write"],
          },
        }
      end

      def before_commands
        []
      end

      def after_commands
        []
      end
    end

    class MockGenerator
      def generate_all; end

      def mcp_config_path(_name)
        "test.mcp.json"
      end
    end
  end
end
