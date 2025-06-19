# frozen_string_literal: true

require "test_helper"

class ExtensionsTest < Minitest::Test
  def setup
    # Clear extensions and hooks before each test
    ClaudeSwarm::Extensions.clear_hooks!
  end

  def teardown
    # Clean up after each test
    ClaudeSwarm::Extensions.clear_hooks!
  end

  def test_register_extension
    metadata = {
      version: "1.0.0",
      author: "Test Author",
      description: "Test extension"
    }

    ClaudeSwarm::Extensions.register_extension("test_extension", metadata)

    extensions = ClaudeSwarm::Extensions.instance_variable_get(:@extensions)
    assert_equal 1, extensions.size
    assert_equal metadata, extensions["test_extension"]
  end

  def test_register_extension_overwrites_existing
    ClaudeSwarm::Extensions.register_extension("test_ext", { version: "1.0" })
    ClaudeSwarm::Extensions.register_extension("test_ext", { version: "2.0" })

    extensions = ClaudeSwarm::Extensions.registered_extensions
    assert_equal 2, extensions.size
    assert_equal "2.0", extensions.last[:metadata][:version]
  end

  def test_registered_extensions
    ClaudeSwarm::Extensions.register_extension("ext1", { version: "1.0" })
    ClaudeSwarm::Extensions.register_extension("ext2", { version: "2.0" })

    extensions = ClaudeSwarm::Extensions.registered_extensions
    assert_equal 2, extensions.size
    assert_equal "ext1", extensions[0][:name]
    assert_equal "ext2", extensions[1][:name]
  end

  def test_register_hook_with_default_priority
    block_called = false
    ClaudeSwarm::Extensions.register_hook(:test_hook) { block_called = true }

    # Verify hook was registered by calling it
    assert ClaudeSwarm::Extensions.hooks_registered?(:test_hook)
    
    # Execute through run_hooks
    ClaudeSwarm::Extensions.run_hooks(:test_hook)
    assert block_called
  end

  def test_register_hook_with_custom_priority
    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 10) { "first" }
    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 90) { "second" }

    # Verify both hooks were registered
    assert ClaudeSwarm::Extensions.hooks_registered?(:test_hook)
    
    # Test order by checking results
    results = []
    ClaudeSwarm::Extensions.register_hook(:order_test, priority: 10) { results << "10" }
    ClaudeSwarm::Extensions.register_hook(:order_test, priority: 90) { results << "90" }
    ClaudeSwarm::Extensions.register_hook(:order_test, priority: 50) { results << "50" }
    
    ClaudeSwarm::Extensions.run_hooks(:order_test)
    assert_equal ["10", "50", "90"], results
  end

  def test_run_hooks_single_handler
    result = nil
    ClaudeSwarm::Extensions.register_hook(:test_hook) do |data|
      result = "processed: #{data}"
      result
    end

    output = ClaudeSwarm::Extensions.run_hooks(:test_hook, "input")
    assert_equal "processed: input", result
    assert_equal "processed: input", output
  end

  def test_run_hooks_multiple_handlers_in_priority_order
    results = []
    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 80) do |data|
      results << "third"
      "#{data}-third"
    end

    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 20) do |data|
      results << "first"
      "#{data}-first"
    end

    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 50) do |data|
      results << "second"
      "#{data}-second"
    end

    output = ClaudeSwarm::Extensions.run_hooks(:test_hook, "test")
    assert_equal ["first", "second", "third"], results
    assert_equal "test-third", output # Last result is returned
  end

  def test_run_hooks_passes_data_through_handlers
    ClaudeSwarm::Extensions.register_hook(:transform, priority: 10) do |data|
      data[:step1] = true
      data
    end

    ClaudeSwarm::Extensions.register_hook(:transform, priority: 20) do |data|
      data[:step2] = true
      data
    end

    result = ClaudeSwarm::Extensions.run_hooks(:transform, {})
    assert result[:step1]
    assert result[:step2]
  end

  def test_run_hooks_with_no_handlers
    result = ClaudeSwarm::Extensions.run_hooks(:nonexistent, "data")
    assert_equal "data", result
  end

  def test_run_hooks_handles_nil_return
    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 10) do |data|
      nil # First handler returns nil
    end

    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 20) do |data|
      "final: #{data}"
    end

    result = ClaudeSwarm::Extensions.run_hooks(:test_hook, "input")
    assert_equal "final: input", result
  end

  def test_run_hooks_with_error_in_handler
    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 10) do |_data|
      raise StandardError, "Handler error"
    end

    ClaudeSwarm::Extensions.register_hook(:test_hook, priority: 20) do |data|
      "processed: #{data}"
    end

    # Should not raise error, but continue with next handler
    result = ClaudeSwarm::Extensions.run_hooks(:test_hook, "input")
    assert_equal "processed: input", result
  end

  def test_hook_priorities_edge_cases
    results = []
    ClaudeSwarm::Extensions.register_hook(:test, priority: 0) { results << "zero" }
    ClaudeSwarm::Extensions.register_hook(:test, priority: 100) { results << "hundred" }
    ClaudeSwarm::Extensions.register_hook(:test, priority: -10) { results << "negative" }

    ClaudeSwarm::Extensions.run_hooks(:test)
    assert_equal ["negative", "zero", "hundred"], results
  end

  def test_extensions_module_thread_safety
    require "concurrent"
    
    results = Concurrent::Array.new
    threads = []

    10.times do |i|
      threads << Thread.new do
        ClaudeSwarm::Extensions.register_extension("ext_#{i}", { thread: i })
        ClaudeSwarm::Extensions.register_hook(:concurrent) { |data| results << "#{data}-#{i}" }
      end
    end

    threads.each(&:join)

    extensions = ClaudeSwarm::Extensions.registered_extensions
    assert_equal 10, extensions.size

    hooks = ClaudeSwarm::Extensions.instance_variable_get(:@hooks)[:concurrent]
    assert_equal 10, hooks.size
  end

  def test_complex_hook_chain
    # Test a realistic hook chain that modifies configuration
    config = {
      instances: {
        main: { directory: "." }
      }
    }

    ClaudeSwarm::Extensions.register_hook(:before_config_load, priority: 10) do |cfg|
      cfg[:modified_at_10] = true
      cfg
    end

    ClaudeSwarm::Extensions.register_hook(:before_config_load, priority: 50) do |cfg|
      cfg[:instances][:main][:model] = "opus"
      cfg
    end

    ClaudeSwarm::Extensions.register_hook(:before_config_load, priority: 90) do |cfg|
      cfg[:final_check] = true
      cfg
    end

    result = ClaudeSwarm::Extensions.run_hooks(:before_config_load, config)

    assert result[:modified_at_10]
    assert_equal "opus", result[:instances][:main][:model]
    assert result[:final_check]
  end

  def test_load_extensions_from_user_directory
    # Create a temporary directory with test extensions
    Dir.mktmpdir do |tmpdir|
      # Mock the home directory
      original_home = ENV['HOME']
      ENV['HOME'] = tmpdir
      
      ext_dir = File.join(tmpdir, ".claude-swarm")
      FileUtils.mkdir_p(ext_dir)

      # Create a test extension file
      File.write(File.join(ext_dir, "extensions.rb"), <<~RUBY)
        ClaudeSwarm::Extensions.register_extension("test_ext", {
          version: "1.0.0",
          loaded_from: "user_directory"
        })

        ClaudeSwarm::Extensions.register_hook(:test_hook) do |data|
          "\#{data} from test_ext"
        end
      RUBY

      # Load extensions
      ClaudeSwarm::Extensions.load_extensions

      extensions = ClaudeSwarm::Extensions.registered_extensions
      assert extensions.any? { |e| e[:name] == "test_ext" }
      
      result = ClaudeSwarm::Extensions.run_hooks(:test_hook, "hello")
      assert_equal "hello from test_ext", result
      
      ENV['HOME'] = original_home
    end
  end

  def test_load_extensions_handles_errors
    Dir.mktmpdir do |tmpdir|
      original_home = ENV['HOME']
      ENV['HOME'] = tmpdir
      
      ext_dir = File.join(tmpdir, ".claude-swarm")
      FileUtils.mkdir_p(ext_dir)

      # Create an extension with syntax error
      File.write(File.join(ext_dir, "extensions.rb"), <<~RUBY)
        this is not valid ruby code {{{
      RUBY

      # Should raise error when loading
      assert_raises(SyntaxError) do
        ClaudeSwarm::Extensions.load_extensions
      end
      
      ENV['HOME'] = original_home
    end
  end

  def test_load_extensions_from_nonexistent_directory
    # Should handle gracefully when no extension files exist
    original_home = ENV['HOME']
    ENV['HOME'] = "/nonexistent"
    
    assert_nothing_raised do
      ClaudeSwarm::Extensions.load_extensions
    end
    
    ENV['HOME'] = original_home
  end
end