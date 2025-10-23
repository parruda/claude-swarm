# frozen_string_literal: true

module SwarmMemory
  module Integration
    # Auto-registration with SwarmSDK
    #
    # Registers SwarmMemory plugin with SwarmSDK when the swarm_memory gem is loaded.
    # This enables SwarmSDK to automatically use SwarmMemory features.
    class Registration
      class << self
        # Register SwarmMemory plugin with SwarmSDK
        #
        # This is called automatically when swarm_memory is required.
        # It registers the plugin so SwarmSDK can provide memory tools and storage.
        #
        # @return [void]
        def register!
          # Only register if SwarmSDK is present
          return unless defined?(SwarmSDK)
          return unless defined?(SwarmSDK::PluginRegistry)

          # Register plugin with SwarmSDK
          plugin = SDKPlugin.new
          SwarmSDK::PluginRegistry.register(plugin)
        rescue StandardError => e
          warn("Warning: Failed to register SwarmMemory plugin with SwarmSDK: #{e.message}")
        end
      end
    end
  end
end
