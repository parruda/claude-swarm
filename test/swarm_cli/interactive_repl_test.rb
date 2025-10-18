# frozen_string_literal: true

require "test_helper"
require "swarm_cli"
require "stringio"
require "tempfile"

class InteractiveREPLTest < Minitest::Test
  def setup
    @swarm = mock_swarm
    # Create a temporary config file for Options
    @temp_config = Tempfile.new(["test_config", ".yml"])
    @temp_config.write("version: 2\nagents:\n  test:\n    system_prompt: test")
    @temp_config.close

    # Create options with parsed arguments
    @options = SwarmCLI::Options.new
    @options.parse([@temp_config.path, "-q"]) # -q for quiet mode
  end

  def teardown
    @temp_config&.unlink
  end

  def test_interactive_repl_initializes_successfully
    # Test that REPL can be initialized without errors
    # This ensures setup_fuzzy_completion runs without errors
    repl = SwarmCLI::InteractiveREPL.new(swarm: @swarm, options: @options)

    assert(repl, "REPL should initialize successfully")
  end

  def test_interactive_repl_initializes_with_initial_message
    # Test initialization with an initial message
    initial_message = "Hello, swarm!"
    repl = SwarmCLI::InteractiveREPL.new(
      swarm: @swarm,
      options: @options,
      initial_message: initial_message,
    )

    assert(repl, "REPL should initialize with initial message")
  end

  def test_interactive_repl_constants_are_defined
    # Verify COMMANDS constant exists and has expected commands
    assert_instance_of(Hash, SwarmCLI::InteractiveREPL::COMMANDS)
    assert_includes(SwarmCLI::InteractiveREPL::COMMANDS, "/help")
    assert_includes(SwarmCLI::InteractiveREPL::COMMANDS, "/clear")
    assert_includes(SwarmCLI::InteractiveREPL::COMMANDS, "/history")
    assert_includes(SwarmCLI::InteractiveREPL::COMMANDS, "/exit")
  end

  private

  def mock_swarm
    swarm = Minitest::Mock.new
    swarm.expect(:name, "Test Swarm")
    swarm.expect(:lead_agent, :test_agent)
    swarm.expect(:validate, [])
    swarm
  end
end
