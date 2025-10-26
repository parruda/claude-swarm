# frozen_string_literal: true

require_relative "../swarm_memory_test_helper"

class AdapterRegistryTest < Minitest::Test
  def test_register_adapter
    # Create a mock adapter class
    mock_adapter = Class.new(SwarmMemory::Adapters::Base) do
      def initialize(option1:)
        super()
        @option1 = option1
      end
    end

    # Register it
    SwarmMemory.register_adapter(:mock, mock_adapter)

    # Should be able to retrieve it
    assert_equal(mock_adapter, SwarmMemory.adapter_for(:mock))
  end

  def test_register_adapter_requires_base_inheritance
    # Create a class that doesn't inherit from Base
    non_adapter_class = Class.new

    # Should raise error
    error = assert_raises(ArgumentError) do
      SwarmMemory.register_adapter(:invalid, non_adapter_class)
    end

    assert_match(/must inherit from SwarmMemory::Adapters::Base/, error.message)
  end

  def test_adapter_for_filesystem
    # Filesystem adapter should be built-in
    assert_equal(SwarmMemory::Adapters::FilesystemAdapter, SwarmMemory.adapter_for(:filesystem))
  end

  def test_adapter_for_unknown
    # Unknown adapter should raise error
    error = assert_raises(ArgumentError) do
      SwarmMemory.adapter_for(:unknown)
    end

    assert_match(/Unknown adapter: unknown/, error.message)
    assert_match(/Available:/, error.message)
  end

  def test_available_adapters
    # Should include filesystem by default
    assert_includes(SwarmMemory.available_adapters, :filesystem)

    # Register a custom adapter
    mock_adapter = Class.new(SwarmMemory::Adapters::Base)
    SwarmMemory.register_adapter(:custom, mock_adapter)

    # Should now include custom
    assert_includes(SwarmMemory.available_adapters, :custom)
  end

  def test_adapter_registry_is_shared
    # Register in one place
    mock_adapter = Class.new(SwarmMemory::Adapters::Base)
    SwarmMemory.register_adapter(:shared, mock_adapter)

    # Should be accessible everywhere
    assert_equal(mock_adapter, SwarmMemory.adapter_for(:shared))
  end
end
