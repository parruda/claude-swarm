# frozen_string_literal: true

require "test_helper"
module ClaudeSwarm
  module Commands
    class PsTest < Minitest::Test
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

      def test_execute_with_no_sessions
        output = capture_io { Commands::Ps.new.execute }.first

        assert_equal("No active sessions\n", output)
      end

      def test_execute_with_no_run_directory
        FileUtils.rm_rf(@run_dir)
        output = capture_io { Commands::Ps.new.execute }.first

        assert_equal("No active sessions\n", output)
      end

      def test_execute_with_active_session
        # Create test config
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "leader",
            "instances" => {
              "leader" => {
                "directory" => ".",
              },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)

        # Create test JSON log with cost_usd from same instance
        json_log = [
          { "instance" => "agent1", "event" => { "type" => "result", "cost_usd" => 0.1111 } },
          { "instance" => "agent1", "event" => { "type" => "result", "cost_usd" => 0.1234 } },
          { "event" => { "type" => "other" } },
        ].map(&:to_json).join("\n")
        File.write(File.join(@test_session_dir, "session.log.json"), json_log)

        # Create symlink
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Ps.new.execute }.first

        assert_includes(output, "SESSION_ID")
        assert_includes(output, "SWARM_NAME")
        assert_includes(output, "TOTAL_COST")
        assert_includes(output, "UPTIME")
        assert_includes(output, "DIRECTORY")
        assert_match(/test-session-123/, output)
        assert_match(/Test Swarm/, output)
        # Should show sum of costs for the instance with asterisk (no main instance cost)
        assert_match(/\$0\.2345\*/, output)
        assert_match(/\d+s/, output) # Should show uptime
        assert_match(/\./, output) # Should show directory
        # Should show warning about missing main instance costs
        assert_match(/Total cost does not include the cost of the main instance/, output)
      end

      def test_execute_with_stale_symlink
        # Create symlink pointing to non-existent directory
        File.symlink("/non/existent/path", File.join(@run_dir, "stale-session"))

        output = capture_io { Commands::Ps.new.execute }.first

        assert_equal("No active sessions\n", output)
      end

      def test_execute_with_missing_config
        # Create symlink but no config file
        FileUtils.mkdir_p(@test_session_dir)
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Ps.new.execute }.first

        assert_equal("No active sessions\n", output)
      end

      def test_execute_with_main_instance_costs
        # Create test config
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "leader",
            "instances" => {
              "leader" => {
                "directory" => ".",
              },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)

        # Create test JSON log with main instance token costs
        json_log = [
          {
            "instance" => "leader",
            "instance_id" => "main",
            "event" => {
              "type" => "assistant",
              "message" => {
                "model" => "claude-3-5-sonnet-20241022",
                "usage" => {
                  "input_tokens" => 1000,
                  "output_tokens" => 500,
                },
              },
            },
          },
          { "instance" => "agent1", "event" => { "type" => "result", "cost_usd" => 0.10 } },
        ].map(&:to_json).join("\n")
        File.write(File.join(@test_session_dir, "session.log.json"), json_log)

        # Create symlink
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Ps.new.execute }.first

        # Should NOT show warning about missing main instance costs
        refute_match(/Total cost does not include the cost of the main instance/, output)
        # Should NOT have asterisk on cost (main instance cost included)
        assert_match(/\$0\.1/, output)
        refute_match(/\$0\.\d+\*/, output)
      end

      def test_execute_with_no_json_log
        # Create config but no JSON log
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "leader",
            "instances" => {
              "leader" => { "directory" => "." },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Ps.new.execute }.first

        assert_match(/test-session-123/, output)
        assert_match(/Test Swarm/, output)
        assert_match(/\$0\.0000/, output)
      end

      def test_format_duration
        ps = Commands::Ps.new

        assert_equal("45s", ps.send(:format_duration, 45))
        assert_equal("2m", ps.send(:format_duration, 120))
        assert_equal("1h", ps.send(:format_duration, 3600))
        assert_equal("2d", ps.send(:format_duration, 172_800))
      end

      def test_truncate
        ps = Commands::Ps.new

        assert_equal("short", ps.send(:truncate, "short", 10))
        assert_equal("very long ..", ps.send(:truncate, "very long string", 12))
      end

      def test_execute_with_array_directory_format
        # Create config with array directory format (as used in real configs)
        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "leader",
            "instances" => {
              "leader" => {
                "directory" => ["/path/to/main", "/path/to/other"],
              },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)
        File.write(File.join(@test_session_dir, "session.log.json"), "")
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Ps.new.execute }.first

        assert_match(/test-session-123/, output)
        assert_match(/Test Swarm/, output)
        assert_match(%r{/path/to/main, /path/to/other}, output) # Should show all directories comma-separated
        refute_match(/\[\s*"/, output) # Should not show array brackets with quotes
      end

      def test_multiple_sessions_sorted_by_time
        # Create two sessions with different timestamps
        session1_dir = ClaudeSwarm.joined_sessions_dir("test-project", "session-1")
        session2_dir = ClaudeSwarm.joined_sessions_dir("test-project", "session-2")

        [session1_dir, session2_dir].each_with_index do |dir, i|
          FileUtils.mkdir_p(dir)
          config = {
            "swarm" => {
              "name" => "Swarm #{i + 1}",
              "main" => "leader",
              "instances" => { "leader" => { "directory" => "." } },
            },
          }
          File.write(File.join(dir, "config.yml"), config.to_yaml)
          File.write(File.join(dir, "session.log.json"), "")

          # Create symlinks
          File.symlink(dir, File.join(@run_dir, "session-#{i + 1}"))
        end

        # Touch session-2 to make it newer
        FileUtils.touch(session2_dir, mtime: Time.now + 60)

        output = capture_io { Commands::Ps.new.execute }.first
        lines = output.split("\n")

        # Find the data lines (skip warning, headers, and separator)
        data_lines = lines.select { |line| line.match(/session-\d/) }

        # Session 2 should appear first (newer)
        assert(data_lines[0].include?("session-2") && data_lines[0].include?("Swarm 2"))
        assert(data_lines[1].include?("session-1") && data_lines[1].include?("Swarm 1"))
      end

      def test_execute_with_expanded_paths
        # Create a session with relative directory
        root_dir = "/Users/test/projects/myapp"
        File.write(File.join(@test_session_dir, "root_directory"), root_dir)

        config = {
          "swarm" => {
            "name" => "Test Swarm",
            "main" => "leader",
            "instances" => {
              "leader" => {
                "directory" => ".",
              },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)
        File.write(File.join(@test_session_dir, "session.log.json"), "")
        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Ps.new.execute }.first

        # Should show expanded path, not "."
        assert_match(root_dir, output)
        refute_match(/DIRECTORY\s+\.$/, output)
      end

      def test_execute_with_worktree_paths
        # Create a session with worktree metadata
        root_dir = "/Users/test/projects/myapp"
        File.write(File.join(@test_session_dir, "root_directory"), root_dir)

        config = {
          "swarm" => {
            "name" => "Worktree Swarm",
            "main" => "leader",
            "instances" => {
              "leader" => {
                "directory" => ".",
              },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)
        File.write(File.join(@test_session_dir, "session.log.json"), "")

        # Create session metadata with worktree info
        metadata = {
          "worktree" => {
            "enabled" => true,
            "shared_name" => "feature-branch",
            "created_paths" => {
              "#{root_dir}:feature-branch" => "#{root_dir}/.worktrees/feature-branch",
            },
          },
        }
        File.write(File.join(@test_session_dir, "session_metadata.json"), JSON.pretty_generate(metadata))

        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        # Mock find_git_root to return the start_dir as if it's a git repo
        ps_instance = Commands::Ps.new
        ps_instance.stub(:find_git_root, root_dir) do
          output = capture_io { ps_instance.execute }.first

          # Should show worktree path
          assert_match("#{root_dir}/.worktrees/feature-branch", output)
          refute_match(/DIRECTORY\s+#{Regexp.escape(root_dir)}$/, output)
        end
      end

      def test_execute_with_multiple_worktree_paths
        # Create a session with multiple directories and worktrees
        root_dir = "/Users/test/projects"
        File.write(File.join(@test_session_dir, "root_directory"), root_dir)

        config = {
          "swarm" => {
            "name" => "Multi Worktree",
            "main" => "leader",
            "instances" => {
              "leader" => {
                "directory" => ["./app1", "./app2"],
              },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)
        File.write(File.join(@test_session_dir, "session.log.json"), "")

        # Create session metadata with worktree info for both repos
        metadata = {
          "worktree" => {
            "enabled" => true,
            "shared_name" => "feature-x",
            "created_paths" => {
              "#{root_dir}/app1:feature-x" => "#{root_dir}/app1/.worktrees/feature-x",
              "#{root_dir}/app2:feature-x" => "#{root_dir}/app2/.worktrees/feature-x",
            },
          },
        }
        File.write(File.join(@test_session_dir, "session_metadata.json"), JSON.pretty_generate(metadata))

        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        # Mock find_git_root to return appropriate git roots
        ps_instance = Commands::Ps.new
        def ps_instance.find_git_root(dir)
          case dir
          when %r{/app1}
            "/Users/test/projects/app1"
          when %r{/app2}
            "/Users/test/projects/app2"
          end
        end

        output = capture_io { ps_instance.execute }.first

        # Should show both worktree paths
        assert_match("#{root_dir}/app1/.worktrees/feature-x, #{root_dir}/app2/.worktrees/feature-x", output)
      end

      def test_execute_without_worktree_metadata
        # Test that sessions without worktree metadata still work
        root_dir = "/Users/test/projects/myapp"
        File.write(File.join(@test_session_dir, "root_directory"), root_dir)

        config = {
          "swarm" => {
            "name" => "No Worktree",
            "main" => "leader",
            "instances" => {
              "leader" => {
                "directory" => "./src",
              },
            },
          },
        }
        File.write(File.join(@test_session_dir, "config.yml"), config.to_yaml)
        File.write(File.join(@test_session_dir, "session.log.json"), "")

        # No session_metadata.json file

        File.symlink(@test_session_dir, File.join(@run_dir, "test-session-123"))

        output = capture_io { Commands::Ps.new.execute }.first

        # Should show expanded path without worktree
        assert_match("#{root_dir}/src", output)
      end
    end
  end
end
