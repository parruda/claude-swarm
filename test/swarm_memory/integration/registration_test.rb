# frozen_string_literal: true

require_relative "../../swarm_memory_test_helper"

class RegistrationTest < Minitest::Test
  def test_memory_plugin_registered_with_swarm_sdk
    # Memory plugin should be registered after requiring swarm_memory
    assert(SwarmSDK::PluginRegistry.registered?(:memory), "Memory plugin not registered")

    plugin = SwarmSDK::PluginRegistry.get(:memory)

    assert_instance_of(SwarmMemory::Integration::SDKPlugin, plugin)
  end

  def test_memory_plugin_provides_tools
    plugin = SwarmSDK::PluginRegistry.get(:memory)
    tools = plugin.tools

    # Check that plugin provides expected memory tools
    assert_includes(tools, :MemoryWrite)
    assert_includes(tools, :MemoryRead)
    assert_includes(tools, :MemoryEdit)
    assert_includes(tools, :MemoryMultiEdit)
    assert_includes(tools, :MemoryDelete)
    assert_includes(tools, :MemoryGlob)
    assert_includes(tools, :MemoryGrep)
    assert_includes(tools, :MemoryDefrag)

    # LoadSkill is NOT in tools list (registered via on_agent_initialized)
    refute_includes(tools, :LoadSkill)
  end

  def test_plugin_registry_knows_about_memory_tools
    # PluginRegistry should map memory tools to the memory plugin
    assert(SwarmSDK::PluginRegistry.plugin_tool?(:MemoryWrite))
    assert(SwarmSDK::PluginRegistry.plugin_tool?(:MemoryRead))
    assert(SwarmSDK::PluginRegistry.plugin_tool?(:MemoryDefrag))

    plugin = SwarmSDK::PluginRegistry.plugin_for_tool(:MemoryWrite)

    assert_equal(:memory, plugin.name)
  end

  def test_memory_tools_not_in_tools_registry
    # Memory tools should NOT be in Tools::Registry (they're plugin-provided)
    refute(SwarmSDK::Tools::Registry.exists?(:MemoryWrite))
    refute(SwarmSDK::Tools::Registry.exists?(:MemoryRead))
    refute(SwarmSDK::Tools::Registry.exists?(:MemoryDefrag))
  end
end
