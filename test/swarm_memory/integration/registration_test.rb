# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class RegistrationTest < Minitest::Test
  def test_memory_tools_registered_with_swarm_sdk
    # Memory tools should be registered after requiring swarm_memory
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryWrite))
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryRead))
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryEdit))
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryMultiEdit))
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryDelete))
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryGlob))
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryGrep))
    assert(SwarmSDK::Tools::Registry.exists?(:MemoryDefrag))
  end

  def test_memory_tools_in_available_names
    available = SwarmSDK::Tools::Registry.available_names

    assert_includes(available, :MemoryWrite)
    assert_includes(available, :MemoryRead)
    assert_includes(available, :MemoryDefrag)
  end

  def test_registry_get_returns_special_for_memory_tools
    # Memory tools are marked as :special (require context)
    assert_equal(:special, SwarmSDK::Tools::Registry.get(:MemoryWrite))
    assert_equal(:special, SwarmSDK::Tools::Registry.get(:MemoryDefrag))
  end
end
