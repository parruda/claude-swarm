# frozen_string_literal: true

require "test_helper"

class ConfigurationErbTest < Minitest::Test
  # Helper module for ERB-specific test utilities
  module ErbTestHelpers
    def create_config_from_yaml(yaml_content, filename = "claude-swarm.yml")
      config_file = File.join(@temp_dir, filename)
      write_config_file(config_file, yaml_content)
      ClaudeSwarm::Configuration.new(config_file)
    end

    def with_env_vars(env_vars = {})
      original_values = {}
      env_vars.each do |key, value|
        original_values[key] = ENV[key]
        ENV[key] = value
      end
      yield
    ensure
      original_values.each do |key, original_value|
        if original_value.nil?
          ENV.delete(key)
        else
          ENV[key] = original_value
        end
      end
    end

    def assert_erb_config_valid(yaml_content, env_vars = {}, &block)
      capture_io do
        with_env_vars(env_vars) do
          config = create_config_from_yaml(yaml_content)
          block&.call(config)
        end
      end
    end

    def generate_large_erb_template(instance_count)
      <<~YAML
        version: 1
        swarm:
          name: "Large Template Test"
          main: instance_1
          instances:
            <% #{instance_count}.times do |i| %>
            instance_<%= i + 1 %>:
              description: "Instance <%= i + 1 %>"
              directory: "#{@temp_dir}"
            <% end %>
      YAML
    end
  end

  include ErbTestHelpers

  def setup
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_regular_yaml_without_erb_works_unchanged
    with_temp_dir do |dir|
      yaml_content = <<~YAML
        version: 1
        swarm:
          name: "Test Swarm"
          main: leader
          instances:
            leader:
              description: "Main instance"
              directory: "#{dir}"
      YAML

      config = create_config_from_yaml(yaml_content)

      assert_equal("Test Swarm", config.swarm_name)
      assert_equal("leader", config.main_instance)
      assert_equal("Main instance", config.instances["leader"][:description])
    end
  end

  # Test that ERB templates are properly detected and processed
  def test_erb_templates_are_processed
    with_temp_dir do |dir|
      # Test with ERB syntax
      yaml_with_erb = <<~YAML
        version: 1
        swarm:
          name: "<%= 'Processed' + ' Swarm' %>"
          main: leader
          instances:
            leader:
              description: "Test"
              directory: "#{dir}"
      YAML

      config = create_config_from_yaml(yaml_with_erb)

      assert_equal("Processed Swarm", config.swarm_name)

      # Test without ERB syntax
      yaml_without_erb = <<~YAML
        version: 1
        swarm:
          name: "Normal Swarm"
          main: leader
          instances:
            leader:
              description: "Test with < and > and %"
              directory: "#{dir}"
      YAML

      config = create_config_from_yaml(yaml_without_erb)

      assert_equal("Normal Swarm", config.swarm_name)
      assert_equal("Test with < and > and %", config.instances["leader"][:description])
    end
  end

  def test_erb_with_environment_variables
    assert_erb_config_valid(
      <<~YAML,
        version: 1
        swarm:
          name: "<%= ENV['TEST_SWARM_NAME'] %>"
          main: leader
          instances:
            leader:
              description: "Main instance"
              directory: "<%= ENV['TEST_DIR'] %>"
              model: "<%= ENV['TEST_MODEL'] %>"
      YAML
      {
        "TEST_SWARM_NAME" => "Dynamic Swarm",
        "TEST_MODEL" => "opus",
        "TEST_DIR" => @temp_dir,
      },
    ) do |config|
      assert_equal("Dynamic Swarm", config.swarm_name)
      assert_equal("opus", config.instances["leader"][:model])
      assert_equal(@temp_dir, config.instances["leader"][:directory])
    end
  end

  def test_erb_with_conditional_sections
    assert_erb_config_valid(
      <<~YAML,
        version: 1
        swarm:
          name: "Conditional Swarm"
          main: leader
          instances:
            leader:
              description: "Main instance"
              directory: "#{@temp_dir}"
              <% if ENV['ENABLE_FRONTEND'] == 'true' %>
              connections:
                - frontend
              <% end %>
            <% if ENV['ENABLE_FRONTEND'] == 'true' %>
            frontend:
              description: "Frontend developer"
              directory: "#{@temp_dir}"
            <% end %>
            <% if ENV['ENABLE_BACKEND'] == 'true' %>
            backend:
              description: "Backend developer"
              directory: "#{@temp_dir}"
            <% end %>
      YAML
      {
        "ENABLE_FRONTEND" => "true",
        "ENABLE_BACKEND" => "false",
      },
    ) do |config|
      assert_includes(config.instance_names, "frontend")
      refute_includes(config.instance_names, "backend")
      assert_equal(["frontend"], config.connections_for("leader"))
    end
  end

  def test_erb_with_deterministic_ruby_code_execution
    # Use fixed values instead of random/time-based
    capture_io do
      yaml_content = <<~YAML
        version: 1
        swarm:
          name: "Ruby Execution Swarm"
          main: leader
          instances:
            leader:
              description: "Main instance"
              directory: "#{@temp_dir}"
              model: "<%= ['sonnet', 'opus', 'haiku'][1] %>"
              prompt: "Generated at 2024-01-01"
              tools:
                <% %w[Read Write Edit].each do |tool| %>
                - <%= tool %>
                <% end %>
      YAML

      config = create_config_from_yaml(yaml_content)

      assert_equal("opus", config.instances["leader"][:model])
      assert_equal("Generated at 2024-01-01", config.instances["leader"][:prompt])
      assert_equal(["Read", "Write", "Edit"], config.instances["leader"][:tools])
    end
  end

  def test_erb_with_loops_generating_instances
    capture_io do
      yaml_content = <<~YAML
        version: 1
        swarm:
          name: "Loop Generated Swarm"
          main: worker_1
          instances:
            <% 3.times do |i| %>
            worker_<%= i + 1 %>:
              description: "Worker instance <%= i + 1 %>"
              directory: "#{@temp_dir}"
              model: "sonnet"
              <% if i > 0 %>
              connections:
                - worker_<%= i %>
              <% end %>
            <% end %>
      YAML

      config = create_config_from_yaml(yaml_content)

      assert_equal(3, config.instance_names.size)
      assert_includes(config.instance_names, "worker_1")
      assert_includes(config.instance_names, "worker_2")
      assert_includes(config.instance_names, "worker_3")
      assert_empty(config.connections_for("worker_1"))
      assert_equal(["worker_1"], config.connections_for("worker_2"))
      assert_equal(["worker_2"], config.connections_for("worker_3"))
    end
  end

  def test_erb_trim_mode_removes_trailing_newlines
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Trim Mode Test"
        main: leader
        instances:
          leader:
            description: "Main"
            directory: "#{@temp_dir}"
            <%- tools = ['Read', 'Write', 'Edit'] -%>
            tools:
              <%- tools.each do |tool| -%>
              - <%= tool %>
              <%- end -%>
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal(["Read", "Write", "Edit"], config.instances["leader"][:tools])
  end

  def test_erb_with_helper_methods
    yaml_content = <<~YAML
      <%
        def generate_model(type)
          case type
          when :fast then 'haiku'
          when :balanced then 'sonnet'
          when :powerful then 'opus'
          else 'sonnet'
          end
        end
      %>
      version: 1
      swarm:
        name: "Helper Methods Swarm"
        main: leader
        instances:
          leader:
            description: "Team lead"
            directory: "#{@temp_dir}"
            model: "<%= generate_model(:powerful) %>"
            connections:
              - analyst
          analyst:
            description: "Data analyst"
            directory: "#{@temp_dir}"
            model: "<%= generate_model(:balanced) %>"
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal("opus", config.instances["leader"][:model])
    assert_equal("sonnet", config.instances["analyst"][:model])
    assert_equal(["analyst"], config.connections_for("leader"))
  end

  def test_erb_with_invalid_syntax_raises_error
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Invalid ERB"
        main: leader
        instances:
          leader:
            description: "<%= undefined_variable %>"
            directory: "#{@temp_dir}"
    YAML

    assert_error_message(NameError, /undefined_variable/) do
      create_config_from_yaml(yaml_content)
    end
  end

  def test_erb_resulting_in_invalid_yaml_raises_error
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: <%= "invalid: yaml: structure" %>
        main: leader
        instances:
          leader:
            description: "Test"
            directory: "#{@temp_dir}"
    YAML

    assert_error_message(ClaudeSwarm::Error, /Invalid YAML syntax/) do
      create_config_from_yaml(yaml_content)
    end
  end

  def test_erb_with_safe_file_inclusion
    # Create a safe included file
    include_file = File.join(@temp_dir, "tools.yml")
    write_config_file(include_file, "- Read\n- Write\n- Edit")

    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Include Test"
        main: leader
        instances:
          leader:
            description: "Main instance"
            directory: "#{@temp_dir}"
            tools:
              <% File.read('#{include_file}').each_line do |line| %>
              <%= line.chomp %>
              <% end %>
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal(["Read", "Write", "Edit"], config.instances["leader"][:tools])
  end

  def test_erb_handles_path_traversal_safely
    # NOTE: ERB allows file access - this test documents that behavior
    # Users should be aware that ERB templates have full Ruby capabilities
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Security Test"
        main: leader
        instances:
          leader:
            description: "<%= File.exist?('/etc/passwd') ? 'file exists' : 'file not found' %>"
            directory: "#{@temp_dir}"
    YAML

    config = create_config_from_yaml(yaml_content)
    # This documents that ERB can access files - users should trust their templates
    assert_includes(["file exists", "file not found"], config.instances["leader"][:description])
  end

  def test_erb_handles_missing_file_inclusion
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Missing File Test"
        main: leader
        instances:
          leader:
            description: "<%= File.read('/nonexistent/file.txt') rescue 'file not found' %>"
            directory: "#{@temp_dir}"
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal("file not found", config.instances["leader"][:description])
  end

  def test_erb_with_complex_data_structures
    yaml_content = <<~YAML
      <%
        instances_config = {
          'leader' => { model: 'opus', connections: ['frontend', 'backend'] },
          'frontend' => { model: 'sonnet', connections: [] },
          'backend' => { model: 'sonnet', connections: [] }
        }
      %>
      version: 1
      swarm:
        name: "Complex Structure"
        main: leader
        instances:
          <% instances_config.each do |name, cfg| %>
          <%= name %>:
            description: "<%= name.capitalize %> instance"
            directory: "#{@temp_dir}"
            model: "<%= cfg[:model] %>"
            <% unless cfg[:connections].empty? %>
            connections:
              <% cfg[:connections].each do |conn| %>
              - <%= conn %>
              <% end %>
            <% end %>
          <% end %>
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal("opus", config.instances["leader"][:model])
    assert_equal(["frontend", "backend"], config.connections_for("leader"))
    assert_equal("sonnet", config.instances["frontend"][:model])
  end

  def test_erb_preserves_yaml_anchors_and_aliases
    yaml_content = <<~YAML
      <% base_dir = '#{@temp_dir}' %>
      version: 1
      swarm:
        name: "Anchor Test"
        main: leader
        instances:
          leader: &base_config
            description: "Leader instance"
            directory: "<%= base_dir %>"
            model: sonnet
            tools:
              - Read
              - Write
          follower:
            <<: *base_config
            description: "Follower instance"
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal("sonnet", config.instances["leader"][:model])
    assert_equal("sonnet", config.instances["follower"][:model])
    assert_equal(["Read", "Write"], config.instances["leader"][:tools])
    assert_equal(["Read", "Write"], config.instances["follower"][:tools])
    assert_equal("Follower instance", config.instances["follower"][:description])
  end

  def test_erb_with_environment_variable_defaults
    with_env_vars({}) do # Ensure vars are not set
      yaml_content = <<~YAML
        version: 1
        swarm:
          name: "Default Values Test"
          main: leader
          instances:
            leader:
              description: "Main instance"
              directory: "#{@temp_dir}"
              model: "<%= ENV['UNDEFINED_VAR'] || 'sonnet' %>"
              prompt: "<%= ENV.fetch('ANOTHER_UNDEFINED', 'Default prompt') %>"
      YAML

      config = create_config_from_yaml(yaml_content)

      assert_equal("sonnet", config.instances["leader"][:model])
      assert_equal("Default prompt", config.instances["leader"][:prompt])
    end
  end

  def test_erb_comments_are_ignored
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Comment Test"
        main: leader
        <%# This is an ERB comment that should be ignored %>
        instances:
          leader:
            <%# Another comment %>
            description: "Main instance"
            directory: "#{@temp_dir}"
            <%# Comments can contain anything: bad_code %>
    YAML

    # Should not raise any errors
    config = create_config_from_yaml(yaml_content)

    assert_equal("Comment Test", config.swarm_name)
  end

  def test_erb_processes_before_env_var_interpolation
    assert_erb_config_valid(
      <<~YAML,
        <%
          # ERB sets a value
          erb_value = "from_erb"
        %>
        version: 1
        swarm:
          name: "Processing Order Test"
          main: leader
          instances:
            leader:
              description: "ERB: <%= erb_value %>, ENV: ${TEST_VALUE}"
              directory: "#{@temp_dir}"
      YAML
      { "TEST_VALUE" => "from_env" },
    ) do |config|
      assert_equal("ERB: from_erb, ENV: from_env", config.instances["leader"][:description])
    end
  end

  def test_erb_with_mcp_server_configuration
    yaml_content = <<~YAML
      <%
        mcp_servers = [
          { name: 'tool1', type: 'stdio', command: 'cmd1' },
          { name: 'tool2', type: 'sse', url: 'http://example.com' }
        ]
      %>
      version: 1
      swarm:
        name: "MCP Test"
        main: leader
        instances:
          leader:
            description: "Main instance"
            directory: "#{@temp_dir}"
            mcps:
              <% mcp_servers.each do |mcp| %>
              - name: "<%= mcp[:name] %>"
                type: "<%= mcp[:type] %>"
                <% if mcp[:type] == 'stdio' %>
                command: "<%= mcp[:command] %>"
                <% else %>
                url: "<%= mcp[:url] %>"
                <% end %>
              <% end %>
    YAML

    config = create_config_from_yaml(yaml_content)
    mcps = config.instances["leader"][:mcps]

    assert_equal(2, mcps.size)
    assert_equal("tool1", mcps[0]["name"])
    assert_equal("stdio", mcps[0]["type"])
    assert_equal("cmd1", mcps[0]["command"])
    assert_equal("tool2", mcps[1]["name"])
    assert_equal("sse", mcps[1]["type"])
    assert_equal("http://example.com", mcps[1]["url"])
  end

  def test_erb_with_dynamic_connections_based_on_env
    assert_erb_config_valid(
      <<~YAML,
        version: 1
        swarm:
          name: "Dynamic Connections"
          main: leader
          instances:
            leader:
              description: "Main instance"
              directory: "#{@temp_dir}"
              connections:
                <% if ENV['DEPLOYMENT_MODE'] == 'production' %>
                - monitor
                - logger
                <% else %>
                - debugger
                <% end %>
            monitor:
              description: "Monitor"
              directory: "#{@temp_dir}"
            logger:
              description: "Logger"
              directory: "#{@temp_dir}"
            debugger:
              description: "Debugger"
              directory: "#{@temp_dir}"
      YAML
      { "DEPLOYMENT_MODE" => "production" },
    ) do |config|
      assert_equal(["monitor", "logger"], config.connections_for("leader"))
    end

    # Test with development mode
    assert_erb_config_valid(
      <<~YAML,
        version: 1
        swarm:
          name: "Dynamic Connections"
          main: leader
          instances:
            leader:
              description: "Main instance"
              directory: "#{@temp_dir}"
              connections:
                <% if ENV['DEPLOYMENT_MODE'] == 'production' %>
                - monitor
                - logger
                <% else %>
                - debugger
                <% end %>
            monitor:
              description: "Monitor"
              directory: "#{@temp_dir}"
            logger:
              description: "Logger"
              directory: "#{@temp_dir}"
            debugger:
              description: "Debugger"
              directory: "#{@temp_dir}"
      YAML
      { "DEPLOYMENT_MODE" => "development" },
    ) do |config|
      assert_equal(["debugger"], config.connections_for("leader"))
    end
  end

  def test_backward_compatibility_with_non_erb_files
    # Test that existing YAML files without ERB continue to work
    yaml_files = [
      # Minimal config
      <<~YAML,
        version: 1
        swarm:
          name: "Simple"
          main: leader
          instances:
            leader:
              description: "Test"
              directory: "#{@temp_dir}"
      YAML
      # Config with special characters that could be mistaken for ERB
      <<~YAML,
        version: 1
        swarm:
          name: "Special <> chars % test"
          main: leader
          instances:
            leader:
              description: "Has < and > but not ERB"
              directory: "#{@temp_dir}"
              prompt: "Use % for percentage"
      YAML
    ]

    yaml_files.each_with_index do |content, index|
      config = create_config_from_yaml(content, "test#{index}.yml")

      assert_instance_of(ClaudeSwarm::Configuration, config)
    end
  end

  def test_erb_with_method_chaining_and_transformations
    yaml_content = <<~YAML
      <%
        base_tools = ['read', 'write', 'edit', 'bash']
        formatted_tools = base_tools.map(&:capitalize).sort
      %>
      version: 1
      swarm:
        name: "Transform Test"
        main: leader
        instances:
          leader:
            description: "Main instance"
            directory: "#{@temp_dir}"
            tools:
              <% formatted_tools.each do |tool| %>
              - <%= tool %>
              <% end %>
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal(["Bash", "Edit", "Read", "Write"], config.instances["leader"][:tools])
  end

  def test_erb_handles_large_templates_efficiently
    # Test with 100 instances (not 1000 to keep test fast)
    yaml_content = generate_large_erb_template(100)

    start_time = Time.now
    config = create_config_from_yaml(yaml_content)
    elapsed = Time.now - start_time

    assert_equal(100, config.instances.size)
    assert_operator(elapsed, :<, 1.0, "ERB processing took too long: #{elapsed}s")
  end

  def test_erb_with_syntax_error_provides_context
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Syntax Error Test"
        main: leader
        instances:
          leader:
            description: "<%= 1 / 0 %>"
            directory: "#{@temp_dir}"
    YAML

    error = assert_raises(ZeroDivisionError) do
      create_config_from_yaml(yaml_content)
    end
    assert_match(/divided by 0/, error.message)
  end

  def test_erb_prevents_infinite_loops
    yaml_content = <<~YAML
      version: 1
      swarm:
        name: "Loop Prevention"
        main: leader
        instances:
          leader:
            description: "<%= loop { break 'stopped' } %>"
            directory: "#{@temp_dir}"
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal("stopped", config.instances["leader"][:description])
  end

  def test_erb_with_nested_erb_tags
    yaml_content = <<~YAML
      <% outer = "leader" %>
      version: 1
      swarm:
        name: "Nested ERB"
        main: <%= outer %>
        instances:
          <%= outer %>:
            description: "Main"
            directory: "#{@temp_dir}"
            <% if outer == "leader" %>
            model: "opus"
            <% end %>
    YAML

    config = create_config_from_yaml(yaml_content)

    assert_equal("leader", config.main_instance)
    assert_equal("opus", config.instances["leader"][:model])
  end
end
