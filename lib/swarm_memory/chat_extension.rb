# frozen_string_literal: true

module SwarmMemory
  # Extension module for SwarmSDK::Agent::Chat
  #
  # Adds individual tool removal capability needed for:
  # 1. Mode-based tool filtering (retrieval/interactive/researcher)
  # 2. LoadSkill's fine-grained tool swapping
  #
  # This is injected into SwarmSDK::Agent::Chat when SwarmMemory is loaded.
  module ChatExtension
    # Remove a specific tool by name
    #
    # Used by SwarmMemory to filter tools based on memory mode.
    # Unlike remove_mutable_tools (which removes ALL mutable tools),
    # this removes a single tool by name.
    #
    # @param tool_name [String, Symbol] Tool name to remove
    # @return [void]
    def remove_tool(tool_name)
      tool_sym = tool_name.to_sym
      tool_str = tool_name.to_s

      # Remove from @tools hash (tools are keyed by symbol)
      @tools.delete(tool_sym)
      @tools.delete(tool_str)
    end
  end
end

# Inject into SwarmSDK when both gems are loaded
if defined?(SwarmSDK::Agent::Chat)
  SwarmSDK::Agent::Chat.include(SwarmMemory::ChatExtension)
end
