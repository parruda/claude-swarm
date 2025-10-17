# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class CLITest < Minitest::Test
  def test_help_flag_shows_help
    out, _err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["--help"]).run }
    end

    assert_match(/SwarmCLI v/, out)
    assert_match(/Usage:/, out)
    assert_match(/Commands:/, out)
    assert_match(/run/, out)
    assert_match(/migrate/, out)
    assert_match(/mcp serve/, out)
    assert_match(/mcp tools/, out)
  end

  def test_short_help_flag
    out, _err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["-h"]).run }
    end

    assert_match(/SwarmCLI v/, out)
    assert_match(/Usage:/, out)
  end

  def test_empty_args_shows_help
    out, _err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new([]).run }
    end

    assert_match(/SwarmCLI v/, out)
    assert_match(/Usage:/, out)
  end

  def test_version_flag_shows_version
    out, _err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["--version"]).run }
    end

    assert_match(/SwarmCLI v#{SwarmCLI::VERSION}/, out)
  end

  def test_short_version_flag
    out, _err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["-v"]).run }
    end

    assert_match(/SwarmCLI v#{SwarmCLI::VERSION}/, out)
  end

  def test_unknown_command_shows_error
    _out, err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["unknown"]).run }
    end

    assert_match(/Unknown command: unknown/, err)
    # Help is printed after error
    assert_includes(err, "Unknown command")
  end

  def test_run_command_routes_to_run_command
    tmpdir = Dir.mktmpdir
    config_path = File.join(tmpdir, "config.yml")
    File.write(config_path, <<~YAML)
      version: 2
      swarm:
        name: "Test"
        lead: agent1
        agents:
          agent1:
            model: gpt-4
            system_prompt: "test"
    YAML

    # Run command will try to execute - we just verify it doesn't crash
    # during option parsing
    _out, err = capture_io do
      SwarmCLI::CLI.new(["run", config_path, "-p", "test prompt"]).run
    rescue SystemExit
      # Expected - execution will fail but options should parse
    end

    # Should not have option parsing errors
    refute_includes(err, "Error: Configuration file not found")
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_migrate_command_routes_to_migrate_command
    tmpdir = Dir.mktmpdir
    config_path = File.join(tmpdir, "v1.yml")
    File.write(config_path, <<~YAML)
      version: 1
      swarm:
        name: "Test"
        main: agent1
        instances:
          agent1:
            description: "test"
    YAML

    # Migrate command will execute and output to stdout
    out, _err = capture_io do
      SwarmCLI::CLI.new(["migrate", config_path]).run
    rescue SystemExit
      # Expected - command exits after execution
    end

    # Should output migrated YAML
    assert_includes(out, "version: 2")
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_mcp_serve_command_routes_to_mcp_serve
    tmpdir = Dir.mktmpdir
    config_path = File.join(tmpdir, "config.yml")
    File.write(config_path, <<~YAML)
      version: 2
      swarm:
        name: "Test"
        lead: agent1
        agents:
          agent1:
            model: gpt-4
            system_prompt: "test"
    YAML

    # MCP serve command will try to start server - we just test routing
    # by checking it doesn't error during option parsing
    _out, err = capture_io do
      # Start in background and kill it quickly
      pid = fork do
        SwarmCLI::CLI.new(["mcp", "serve", config_path]).run
      rescue StandardError
        # Server may error when starting
      end

      sleep(0.1)
      begin
        Process.kill("TERM", pid)
      rescue
        nil
      end
      begin
        Process.wait(pid)
      rescue
        nil
      end
    end

    # Should not have option parsing errors
    refute_includes(err, "Error: Configuration file not found")
  ensure
    FileUtils.rm_rf(tmpdir)
  end

  def test_mcp_tools_command_routes_to_mcp_tools
    # MCP tools command will try to start server
    _out, err = capture_io do
      pid = fork do
        SwarmCLI::CLI.new(["mcp", "tools"]).run
      rescue StandardError
        # Server may error
      end

      sleep(0.1)
      begin
        Process.kill("TERM", pid)
      rescue
        nil
      end
      begin
        Process.wait(pid)
      rescue
        nil
      end
    end

    # Should not have option parsing errors
    refute_includes(err, "Error:")
  end

  def test_mcp_unknown_subcommand_shows_error
    _out, err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["mcp", "unknown"]).run }
    end

    assert_match(/Unknown mcp subcommand: unknown/, err)
    assert_match(/Available mcp subcommands:/, err)
    assert_match(/serve/, err)
    assert_match(/tools/, err)
  end

  def test_invalid_run_options_show_error
    _out, err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["run", "nonexistent.yml", "-p", "test"]).run }
    end

    # Error message may vary depending on where validation fails
    assert(err.downcase.include?("error") || err.downcase.include?("fatal"))
  end

  def test_invalid_migrate_options_show_error
    _out, err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["migrate", "nonexistent.yml"]).run }
    end

    assert_match(/Error:/, err)
    assert_match(/Input file not found/, err)
  end

  def test_invalid_mcp_serve_options_show_error
    _out, err = capture_io do
      assert_raises(SystemExit) { SwarmCLI::CLI.new(["mcp", "serve", "nonexistent.yml"]).run }
    end

    # Error message may vary depending on where validation fails
    assert(err.downcase.include?("error") || err.downcase.include?("fatal") || err.downcase.include?("not found"))
  end
end
