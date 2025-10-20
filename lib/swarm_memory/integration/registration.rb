# frozen_string_literal: true

module SwarmMemory
  module Integration
    # Auto-registration with SwarmSDK
    #
    # Registers memory tools with SwarmSDK's extension mechanism when
    # the swarm_memory gem is required.
    class Registration
      class << self
        # Register memory tools with SwarmSDK
        #
        # This is called automatically when swarm_memory is required.
        # It registers all memory tools so SwarmSDK can create them.
        #
        # @return [void]
        def register!
          # Only register if SwarmSDK is present
          return unless defined?(SwarmSDK)

          # Register all memory tools with SwarmSDK's extension mechanism
          memory_tools = {
            MemoryWrite: :special,
            MemoryRead: :special,
            MemoryEdit: :special,
            MemoryMultiEdit: :special,
            MemoryDelete: :special,
            MemoryGlob: :special,
            MemoryGrep: :special,
            MemoryDefrag: :special,
          }

          SwarmSDK::Tools::Registry.register_extension(:memory, memory_tools)
        rescue StandardError => e
          warn("Warning: Failed to register SwarmMemory tools with SwarmSDK: #{e.message}")
        end
      end
    end
  end
end
