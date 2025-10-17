# frozen_string_literal: true

module SwarmSDK
  module Node
    # Builder provides DSL for configuring nodes (mini-swarms within a workflow)
    #
    # A node represents a stage in a multi-step workflow where a specific set
    # of agents collaborate. Each node creates an independent swarm execution.
    #
    # @example Solo agent node
    #   node :planning do
    #     agent(:architect)
    #   end
    #
    # @example Multi-agent node with delegation
    #   node :implementation do
    #     agent(:backend).delegates_to(:tester, :database)
    #     agent(:tester).delegates_to(:database)
    #     agent(:database)
    #
    #     depends_on :planning
    #   end
    class Builder
      attr_reader :name,
        :agent_configs,
        :dependencies,
        :lead_override,
        :input_transformer,
        :output_transformer,
        :input_transformer_command,
        :output_transformer_command

      def initialize(name)
        @name = name
        @agent_configs = []
        @dependencies = []
        @lead_override = nil
        @input_transformer = nil # Ruby block
        @output_transformer = nil # Ruby block
        @input_transformer_command = nil # Bash command
        @output_transformer_command = nil # Bash command
      end

      # Configure an agent for this node
      #
      # Returns an AgentConfig object that supports fluent delegation syntax.
      # If delegates_to is not called, the agent is registered with no delegation.
      #
      # @param name [Symbol] Agent name
      # @return [AgentConfig] Fluent configuration object
      #
      # @example With delegation
      #   agent(:backend).delegates_to(:tester, :database)
      #
      # @example Without delegation
      #   agent(:planner)
      def agent(name)
        config = AgentConfig.new(name, self)

        # Register immediately with empty delegation
        # If delegates_to is called later, it will update this
        register_agent(name, [])

        config
      end

      # Register an agent configuration (called by AgentConfig)
      #
      # @param agent_name [Symbol] Agent name
      # @param delegates_to [Array<Symbol>] Delegation targets
      # @return [void]
      def register_agent(agent_name, delegates_to)
        # Check if agent already registered
        existing = @agent_configs.find { |ac| ac[:agent] == agent_name }

        if existing
          # Update delegation (happens when delegates_to is called after agent())
          existing[:delegates_to] = delegates_to
        else
          # Add new agent configuration
          @agent_configs << { agent: agent_name, delegates_to: delegates_to }
        end
      end

      # Declare dependencies (nodes that must execute before this one)
      #
      # @param node_names [Array<Symbol>] Names of prerequisite nodes
      # @return [void]
      #
      # @example Single dependency
      #   depends_on :planning
      #
      # @example Multiple dependencies
      #   depends_on :frontend, :backend
      def depends_on(*node_names)
        @dependencies.concat(node_names.map(&:to_sym))
      end

      # Override the lead agent (first agent is lead by default)
      #
      # @param agent_name [Symbol] Name of agent to make lead
      # @return [void]
      #
      # @example
      #   agent(:backend).delegates_to(:tester)
      #   agent(:tester)
      #   lead :tester  # tester is lead instead of backend
      def lead(agent_name)
        @lead_override = agent_name.to_sym
      end

      # Define input transformer for this node
      #
      # The transformer receives a NodeContext object with access to:
      # - Previous node's result (convenience: ctx.content)
      # - Original user prompt (ctx.original_prompt)
      # - All previous node results (ctx.all_results[:node_name])
      # - Current node metadata (ctx.node_name, ctx.dependencies)
      #
      # Can also be used for side effects (logging, file I/O) since the block
      # runs at execution time, not declaration time.
      #
      # **Skip Execution**: Return a hash with `skip_execution: true` to skip
      # the node's swarm execution and immediately return the provided content.
      # Useful for caching, validation, or conditional execution.
      #
      # @yield [NodeContext] Context with previous results and metadata
      # @return [String, Hash] Transformed input OR skip hash
      #
      # @example Access previous result and original prompt
      #   input do |ctx|
      #     # Convenience accessor
      #     previous_content = ctx.content
      #
      #     # Access original prompt
      #     "Original: #{ctx.original_prompt}\nPrevious: #{previous_content}"
      #   end
      #
      # @example Access results from specific nodes
      #   input do |ctx|
      #     plan = ctx.all_results[:planning].content
      #     design = ctx.all_results[:design].content
      #
      #     "Implement based on:\nPlan: #{plan}\nDesign: #{design}"
      #   end
      #
      # @example Skip execution (caching)
      #   input do |ctx|
      #     cached = check_cache(ctx.content)
      #     if cached
      #       # Skip LLM call, return cached result
      #       { skip_execution: true, content: cached }
      #     else
      #       ctx.content
      #     end
      #   end
      #
      # @example Skip execution (validation)
      #   input do |ctx|
      #     if ctx.content.length > 10000
      #       # Fail early without LLM call
      #       { skip_execution: true, content: "ERROR: Input too long" }
      #     else
      #       ctx.content
      #     end
      #   end
      def input(&block)
        @input_transformer = block
      end

      # Set input transformer as bash command (YAML API)
      #
      # The command receives NodeContext as JSON on STDIN and outputs transformed content.
      #
      # **Exit codes:**
      # - 0: Success, use STDOUT as transformed content
      # - 1: Skip node execution, use current_input unchanged (STDOUT ignored)
      # - 2: Halt workflow with error, show STDERR (STDOUT ignored)
      #
      # @param command [String] Bash command to execute
      # @param timeout [Integer] Timeout in seconds (default: 60)
      # @return [void]
      #
      # @example
      #   input_command("scripts/validate.sh", timeout: 30)
      def input_command(command, timeout: TransformerExecutor::DEFAULT_TIMEOUT)
        @input_transformer_command = { command: command, timeout: timeout }
      end

      # Define output transformer for this node
      #
      # The transformer receives a NodeContext object with access to:
      # - Current node's result (convenience: ctx.content)
      # - Original user prompt (ctx.original_prompt)
      # - All completed node results (ctx.all_results[:node_name])
      # - Current node metadata (ctx.node_name)
      #
      # Can also be used for side effects (logging, file I/O) since the block
      # runs at execution time, not declaration time.
      #
      # @yield [NodeContext] Context with current result and metadata
      # @return [String] Transformed output
      #
      # @example Transform and save to file
      #   output do |ctx|
      #     # Side effect: save to file
      #     File.write("results/plan.txt", ctx.content)
      #
      #     # Return transformed output for next node
      #     "Key decisions: #{extract_decisions(ctx.content)}"
      #   end
      #
      # @example Access original prompt
      #   output do |ctx|
      #     # Include original context in output
      #     "Task: #{ctx.original_prompt}\nResult: #{ctx.content}"
      #   end
      #
      # @example Access multiple node results
      #   output do |ctx|
      #     plan = ctx.all_results[:planning].content
      #     impl = ctx.content
      #
      #     "Completed:\nPlan: #{plan}\nImpl: #{impl}"
      #   end
      def output(&block)
        @output_transformer = block
      end

      # Set output transformer as bash command (YAML API)
      #
      # The command receives NodeContext as JSON on STDIN and outputs transformed content.
      #
      # **Exit codes:**
      # - 0: Success, use STDOUT as transformed content
      # - 1: Pass through unchanged, use result.content (STDOUT ignored)
      # - 2: Halt workflow with error, show STDERR (STDOUT ignored)
      #
      # @param command [String] Bash command to execute
      # @param timeout [Integer] Timeout in seconds (default: 60)
      # @return [void]
      #
      # @example
      #   output_command("scripts/format.sh", timeout: 30)
      def output_command(command, timeout: TransformerExecutor::DEFAULT_TIMEOUT)
        @output_transformer_command = { command: command, timeout: timeout }
      end

      # Check if node has any input transformer (block or command)
      #
      # @return [Boolean]
      def has_input_transformer?
        @input_transformer || @input_transformer_command
      end

      # Check if node has any output transformer (block or command)
      #
      # @return [Boolean]
      def has_output_transformer?
        @output_transformer || @output_transformer_command
      end

      # Transform input using configured transformer (block or command)
      #
      # Executes either Ruby block or bash command transformer.
      #
      # **Exit code behavior (bash commands only):**
      # - Exit 0: Use STDOUT as transformed content
      # - Exit 1: Skip node execution, use current_input unchanged (STDOUT ignored)
      # - Exit 2: Halt workflow with error (STDOUT ignored)
      #
      # @param context [NodeContext] Context with previous results and metadata
      # @param current_input [String] Fallback content for exit 1 (skip), also used for halt error context
      # @return [String, Hash] Transformed input OR skip hash `{ skip_execution: true, content: "..." }`
      # @raise [ConfigurationError] If bash transformer halts workflow (exit 2)
      def transform_input(context, current_input:)
        # No transformer configured: return content as-is
        return context.content unless @input_transformer || @input_transformer_command

        # Ruby block transformer
        # Ruby blocks can return String (transformed content) OR Hash (skip_execution)
        if @input_transformer
          return @input_transformer.call(context)
        end

        # Bash command transformer
        # Bash commands use exit codes to control behavior:
        # - Exit 0: Success, use STDOUT as transformed content
        # - Exit 1: Skip node execution, use current_input unchanged (STDOUT ignored)
        # - Exit 2: Halt workflow with error (STDOUT ignored)
        if @input_transformer_command
          result = TransformerExecutor.execute(
            command: @input_transformer_command[:command],
            context: context,
            event: "input",
            node_name: @name,
            fallback_content: current_input, # Used for exit 1 (skip)
            timeout: @input_transformer_command[:timeout],
          )

          # Handle transformer result based on exit code
          if result.halt?
            # Exit 2: Halt workflow with error
            raise ConfigurationError,
              "Input transformer halted workflow for node '#{@name}': #{result.error_message}"
          elsif result.skip_execution?
            # Exit 1: Skip node execution, return skip hash
            # Content is current_input unchanged (STDOUT was ignored)
            { skip_execution: true, content: result.content }
          else
            # Exit 0: Return transformed content from STDOUT
            result.content
          end
        end
      end

      # Transform output using configured transformer (block or command)
      #
      # Executes either Ruby block or bash command transformer.
      #
      # **Exit code behavior (bash commands only):**
      # - Exit 0: Use STDOUT as transformed content
      # - Exit 1: Pass through unchanged, use result.content (STDOUT ignored)
      # - Exit 2: Halt workflow with error (STDOUT ignored)
      #
      # @param context [NodeContext] Context with current result and metadata
      # @return [String] Transformed output
      # @raise [ConfigurationError] If bash transformer halts workflow (exit 2)
      def transform_output(context)
        # No transformer configured: return content as-is
        return context.content unless @output_transformer || @output_transformer_command

        # Ruby block transformer
        # Simply calls the block with context and returns result
        if @output_transformer
          return @output_transformer.call(context)
        end

        # Bash command transformer
        # Bash commands use exit codes to control behavior:
        # - Exit 0: Success, use STDOUT as transformed content
        # - Exit 1: Pass through unchanged, use result.content (STDOUT ignored)
        # - Exit 2: Halt workflow with error from STDERR (STDOUT ignored)
        if @output_transformer_command
          result = TransformerExecutor.execute(
            command: @output_transformer_command[:command],
            context: context,
            event: "output",
            node_name: @name,
            fallback_content: context.content, # result.content for exit 1
            timeout: @output_transformer_command[:timeout],
          )

          # Handle transformer result based on exit code
          if result.halt?
            # Exit 2: Halt workflow with error
            raise ConfigurationError,
              "Output transformer halted workflow for node '#{@name}': #{result.error_message}"
          else
            # Exit 0: Return transformed content from STDOUT
            # Exit 1: Return fallback (result.content unchanged)
            result.content
          end
        end
      end

      # Get the lead agent for this node
      #
      # @return [Symbol] Lead agent name
      def lead_agent
        @lead_override || @agent_configs.first&.dig(:agent)
      end

      # Check if this is an agent-less (computation-only) node
      #
      # Agent-less nodes run pure Ruby code without LLM execution.
      # They must have at least one transformer (input or output).
      #
      # @return [Boolean]
      def agent_less?
        @agent_configs.empty?
      end

      # Validate node configuration
      #
      # Also auto-adds agents that are referenced in delegates_to but not explicitly declared.
      # This allows writing: agent(:backend).delegates_to(:verifier)
      # without needing: agent(:verifier)
      #
      # @return [void]
      # @raise [ConfigurationError] If configuration is invalid
      def validate!
        # Auto-add agents mentioned in delegates_to but not explicitly declared
        auto_add_delegate_agents

        # Agent-less nodes (pure computation) are allowed but need transformers
        if @agent_configs.empty?
          unless has_input_transformer? || has_output_transformer?
            raise ConfigurationError,
              "Agent-less node '#{@name}' must have at least one transformer (input or output). " \
                "Either add agents with agent(:name) or add input/output transformers."
          end
        end

        # If has agents, validate lead override
        if @lead_override && !@agent_configs.any? { |ac| ac[:agent] == @lead_override }
          raise ConfigurationError,
            "Node '#{@name}' lead agent '#{@lead_override}' not found in node's agents"
        end
      end

      private

      # Auto-add agents that are mentioned in delegates_to but not explicitly declared
      #
      # This allows:
      #   agent(:backend).delegates_to(:tester)
      # Without needing:
      #   agent(:tester)
      #
      # The tester agent is automatically added to the node with no delegation.
      #
      # @return [void]
      def auto_add_delegate_agents
        # Collect all agents mentioned in delegates_to
        all_delegates = @agent_configs.flat_map { |ac| ac[:delegates_to] }.uniq

        # Find delegates that aren't explicitly declared
        declared_agents = @agent_configs.map { |ac| ac[:agent] }
        missing_delegates = all_delegates - declared_agents

        # Auto-add missing delegates with empty delegation
        missing_delegates.each do |delegate_name|
          @agent_configs << { agent: delegate_name, delegates_to: [] }
        end
      end
    end
  end
end
