# frozen_string_literal: true

require_relative "../test_helper"
require "swarm_cli"
require "tempfile"
require "fileutils"

module SwarmCLI
  class PersistentHistoryTest < Minitest::Test
    def setup
      @original_api_key = ENV["OPENAI_API_KEY"]
      ENV["OPENAI_API_KEY"] = "test-key-12345"
      RubyLLM.configure { |config| config.openai_api_key = "test-key-12345" }

      @temp_dir = Dir.mktmpdir("persistent-history-test")
      @temp_config = Tempfile.new(["test_config", ".yml"])
      @temp_config.write("version: 2\nagents:\n  test:\n    system_prompt: test")
      @temp_config.close

      # Use temp history file via environment variable
      @original_swarm_history = ENV["SWARM_HISTORY"]
      @test_history_file = File.join(@temp_dir, "test_history")
      ENV["SWARM_HISTORY"] = @test_history_file

      # Clear Reline history at start (may be polluted from other tests)
      Reline::HISTORY.clear
    end

    def teardown
      # Restore original environment
      if @original_swarm_history
        ENV["SWARM_HISTORY"] = @original_swarm_history
      else
        ENV.delete("SWARM_HISTORY")
      end

      FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
      @temp_config&.unlink
      ENV["OPENAI_API_KEY"] = @original_api_key
      RubyLLM.configure { |config| config.openai_api_key = @original_api_key }

      # Clear Reline history for next test
      Reline::HISTORY.clear
    end

    def test_history_persists_across_sessions
      # Create swarm
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          coding_agent(false)
          tools(:Read)
          directory(@temp_dir)
        end
      end

      # Session 1: Create REPL and add history
      options1 = SwarmCLI::Options.new
      options1.parse([@temp_config.path, "-q"])
      repl1 = SwarmCLI::InteractiveREPL.new(swarm: swarm, options: options1)

      # Add entries to Reline history
      Reline::HISTORY << "command 1"
      Reline::HISTORY << "command 2"
      Reline::HISTORY << "command 3"

      # Save history (simulate REPL exit)
      repl1.save_persistent_history

      # Verify history file was created
      assert_path_exists(@test_history_file)

      # Clear in-memory history
      Reline::HISTORY.clear

      assert_empty(Reline::HISTORY)

      # Session 2: Create new REPL (should load history)
      options2 = SwarmCLI::Options.new
      options2.parse([@temp_config.path, "-q"])
      SwarmCLI::InteractiveREPL.new(swarm: swarm, options: options2)

      # Verify history was loaded
      assert_equal(3, Reline::HISTORY.size)
      assert_equal("command 1", Reline::HISTORY[0])
      assert_equal("command 2", Reline::HISTORY[1])
      assert_equal("command 3", Reline::HISTORY[2])
    end

    def test_history_file_has_secure_permissions
      # Create swarm
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          coding_agent(false)
          tools(:Read)
          directory(@temp_dir)
        end
      end

      options = SwarmCLI::Options.new
      options.parse([@temp_config.path, "-q"])
      repl = SwarmCLI::InteractiveREPL.new(swarm: swarm, options: options)

      # Add history and save
      Reline::HISTORY << "secret command"
      repl.save_persistent_history

      # Check file permissions (should be 0600 - owner read/write only)
      stat = File.stat(@test_history_file)
      mode = format("%o", stat.mode)

      # On macOS/Unix, mode includes file type bits, so we check last 3 digits
      assert_match(/600$/, mode, "History file should have 0600 permissions")
    end

    def test_history_size_limit_enforced
      # Create swarm
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          coding_agent(false)
          tools(:Read)
          directory(@temp_dir)
        end
      end

      options = SwarmCLI::Options.new
      options.parse([@temp_config.path, "-q"])
      repl = SwarmCLI::InteractiveREPL.new(swarm: swarm, options: options)

      # Add more entries than HISTORY_SIZE
      1200.times do |i|
        Reline::HISTORY << "command #{i}"
      end

      # Save history
      repl.save_persistent_history

      # Clear and reload
      Reline::HISTORY.clear
      SwarmCLI::InteractiveREPL.new(swarm: swarm, options: options)

      # Should only have last 1000 entries (HISTORY_SIZE)
      assert_equal(SwarmCLI::InteractiveREPL::HISTORY_SIZE, Reline::HISTORY.size)
      assert_equal("command 200", Reline::HISTORY.first) # First of last 1000
      assert_equal("command 1199", Reline::HISTORY.last) # Last entry
    end

    def test_history_handles_multiline_entries
      # Create swarm
      swarm = SwarmSDK.build do
        name("Test Swarm")
        lead(:agent1)

        agent(:agent1) do
          description("Test agent")
          coding_agent(false)
          tools(:Read)
          directory(@temp_dir)
        end
      end

      options = SwarmCLI::Options.new
      options.parse([@temp_config.path, "-q"])
      repl = SwarmCLI::InteractiveREPL.new(swarm: swarm, options: options)

      # Add multi-line entry
      multiline_entry = "line 1\nline 2\nline 3"
      Reline::HISTORY << multiline_entry

      # Save and reload
      repl.save_persistent_history
      Reline::HISTORY.clear
      SwarmCLI::InteractiveREPL.new(swarm: swarm, options: options)

      # Verify multi-line entry was preserved
      assert_equal(1, Reline::HISTORY.size)
      assert_equal(multiline_entry, Reline::HISTORY.first)
    end
  end
end
