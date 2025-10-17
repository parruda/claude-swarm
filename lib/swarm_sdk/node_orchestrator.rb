# frozen_string_literal: true

module SwarmSDK
  # NodeOrchestrator executes a multi-node workflow
  #
  # Each node represents a mini-swarm execution stage. The orchestrator:
  # - Builds execution order from node dependencies (topological sort)
  # - Creates a separate swarm instance for each node
  # - Passes output from one node as input to dependent nodes
  # - Supports input/output transformers for data flow customization
  #
  # @example
  #   orchestrator = NodeOrchestrator.new(
  #     swarm_name: "Dev Team",
  #     agent_definitions: { backend: def1, tester: def2 },
  #     nodes: { planning: node1, implementation: node2 },
  #     start_node: :planning
  #   )
  #   result = orchestrator.execute("Build auth system")
  class NodeOrchestrator
    attr_reader :swarm_name, :nodes, :start_node

    def initialize(swarm_name:, agent_definitions:, nodes:, start_node:)
      @swarm_name = swarm_name
      @agent_definitions = agent_definitions
      @nodes = nodes
      @start_node = start_node

      validate!
      @execution_order = build_execution_order
    end

    # Execute the node workflow
    #
    # Executes nodes in topological order, passing output from each node
    # to its dependents. Supports streaming logs if block given.
    #
    # @param prompt [String] Initial prompt for the workflow
    # @yield [Hash] Log entry if block given (for streaming)
    # @return [Result] Final result from last node execution
    def execute(prompt, &block)
      logs = []
      current_input = prompt
      results = {}
      @original_prompt = prompt # Store original prompt for NodeContext

      # Setup logging if block given
      if block_given?
        # Register callback to collect logs and forward to user's block
        LogCollector.on_log do |entry|
          logs << entry
          block.call(entry)
        end

        # Set LogStream to use LogCollector as emitter
        LogStream.emitter = LogCollector
      end

      @execution_order.each do |node_name|
        node = @nodes[node_name]
        node_start_time = Time.now

        # Emit node_start event
        emit_node_start(node_name, node)

        # Transform input if node has transformer (Ruby block or bash command)
        skip_execution = false
        skip_content = nil

        if node.has_input_transformer?
          # Build NodeContext based on dependencies
          #
          # For single dependency: previous_result has original Result metadata,
          #                       transformed_content has output from previous transformer
          # For multiple dependencies: previous_result is hash of Results
          # For no dependencies: previous_result is initial prompt string
          previous_result = if node.dependencies.size > 1
            # Multiple dependencies: pass hash of original results
            node.dependencies.to_h { |dep| [dep, results[dep]] }
          elsif node.dependencies.size == 1
            # Single dependency: pass the original result
            results[node.dependencies.first]
          else
            # No dependencies: initial prompt
            current_input
          end

          # Create NodeContext for input transformer
          input_context = NodeContext.for_input(
            previous_result: previous_result,
            all_results: results,
            original_prompt: @original_prompt,
            node_name: node_name,
            dependencies: node.dependencies,
            transformed_content: node.dependencies.size == 1 ? current_input : nil,
          )

          # Apply input transformer (passes current_input for bash command fallback)
          # Bash transformer exit codes:
          # - Exit 0: Use STDOUT as transformed content
          # - Exit 1: Skip node execution, use current_input unchanged (STDOUT ignored)
          # - Exit 2: Halt workflow with error from STDERR (STDOUT ignored)
          transformed = node.transform_input(input_context, current_input: current_input)

          # Check if transformer requested skipping execution
          # (from Ruby block returning hash OR bash command exit 1)
          if transformed.is_a?(Hash) && transformed[:skip_execution]
            skip_execution = true
            skip_content = transformed[:content] || transformed["content"]
          else
            current_input = transformed
          end
        end

        # Execute node (or skip if requested)
        if skip_execution
          # Skip execution: return result immediately with provided content
          result = Result.new(
            content: skip_content,
            agent: "skipped:#{node_name}",
            logs: [],
            duration: 0.0,
          )
        elsif node.agent_less?
          # Agent-less node: run pure computation without LLM
          result = execute_agent_less_node(node, current_input)
        else
          # Normal node: build mini-swarm and execute with LLM
          # NOTE: Don't pass block to mini-swarm - LogCollector already captures all logs
          mini_swarm = build_swarm_for_node(node)
          result = mini_swarm.execute(current_input)

          # If result has error, log it with backtrace
          if result.error
            RubyLLM.logger.error("NodeOrchestrator: Node '#{node_name}' failed: #{result.error.message}")
            RubyLLM.logger.error("  Backtrace: #{result.error.backtrace&.first(5)&.join("\n  ")}")
          end
        end

        results[node_name] = result

        # Transform output for next node using NodeContext
        output_context = NodeContext.for_output(
          result: result,
          all_results: results,
          original_prompt: @original_prompt,
          node_name: node_name,
        )
        current_input = node.transform_output(output_context)

        # For agent-less nodes, update the result with transformed content
        # This ensures all_results contains the actual output, not the input
        if node.agent_less? && current_input != result.content
          results[node_name] = Result.new(
            content: current_input,
            agent: result.agent,
            logs: result.logs,
            duration: result.duration,
            error: result.error,
          )
        end

        # Emit node_stop event
        node_duration = Time.now - node_start_time
        emit_node_stop(node_name, node, result, node_duration, skip_execution)
      end

      results.values.last
    ensure
      # Reset logging state for next execution
      LogCollector.reset!
      LogStream.reset!
    end

    private

    # Emit node_start event
    #
    # @param node_name [Symbol] Name of the node
    # @param node [Node::Builder] Node configuration
    # @return [void]
    def emit_node_start(node_name, node)
      return unless LogStream.emitter

      LogStream.emit(
        type: "node_start",
        node: node_name.to_s,
        agent_less: node.agent_less?,
        agents: node.agent_configs.map { |ac| ac[:agent].to_s },
        dependencies: node.dependencies.map(&:to_s),
        timestamp: Time.now.utc.iso8601,
      )
    end

    # Emit node_stop event
    #
    # @param node_name [Symbol] Name of the node
    # @param node [Node::Builder] Node configuration
    # @param result [Result] Node execution result
    # @param duration [Float] Node execution duration in seconds
    # @param skipped [Boolean] Whether execution was skipped
    # @return [void]
    def emit_node_stop(node_name, node, result, duration, skipped)
      return unless LogStream.emitter

      LogStream.emit(
        type: "node_stop",
        node: node_name.to_s,
        agent_less: node.agent_less?,
        skipped: skipped,
        agents: node.agent_configs.map { |ac| ac[:agent].to_s },
        duration: duration.round(3),
        timestamp: Time.now.utc.iso8601,
      )
    end

    # Execute an agent-less (computation-only) node
    #
    # Agent-less nodes run pure Ruby code without LLM execution.
    # Creates a minimal Result object with the transformed content.
    #
    # @param node [Node::Builder] Agent-less node configuration
    # @param input [String] Input content
    # @return [Result] Result with transformed content
    def execute_agent_less_node(node, input)
      # For agent-less nodes, the "content" is just the input passed through
      # The output transformer will do the actual work
      Result.new(
        content: input,
        agent: "computation:#{node.name}",
        logs: [],
        duration: 0.0,
      )
    end

    # Validate orchestrator configuration
    #
    # @return [void]
    # @raise [ConfigurationError] If configuration is invalid
    def validate!
      # Validate start_node exists
      unless @nodes.key?(@start_node)
        raise ConfigurationError,
          "start_node '#{@start_node}' not found. Available nodes: #{@nodes.keys.join(", ")}"
      end

      # Validate all nodes
      @nodes.each_value(&:validate!)

      # Validate node dependencies reference existing nodes
      @nodes.each do |node_name, node|
        node.dependencies.each do |dep|
          unless @nodes.key?(dep)
            raise ConfigurationError,
              "Node '#{node_name}' depends on unknown node '#{dep}'"
          end
        end
      end

      # Validate all agents referenced in nodes exist (skip agent-less nodes)
      @nodes.each do |node_name, node|
        next if node.agent_less? # Skip validation for agent-less nodes

        node.agent_configs.each do |config|
          agent_name = config[:agent]
          unless @agent_definitions.key?(agent_name)
            raise ConfigurationError,
              "Node '#{node_name}' references undefined agent '#{agent_name}'"
          end

          # Validate delegation targets exist
          config[:delegates_to].each do |delegate|
            unless @agent_definitions.key?(delegate)
              raise ConfigurationError,
                "Node '#{node_name}' agent '#{agent_name}' delegates to undefined agent '#{delegate}'"
            end
          end
        end
      end
    end

    # Build a swarm instance for a specific node
    #
    # Creates a new Swarm with only the agents specified in the node,
    # configured with the node's delegation topology.
    #
    # @param node [Node::Builder] Node configuration
    # @return [Swarm] Configured swarm instance
    def build_swarm_for_node(node)
      swarm = Swarm.new(name: "#{@swarm_name}:#{node.name}")

      # Add each agent specified in this node
      node.agent_configs.each do |config|
        agent_name = config[:agent]
        delegates_to = config[:delegates_to]

        # Get global agent definition
        agent_def = @agent_definitions[agent_name]

        # Clone definition with node-specific delegation
        node_specific_def = clone_with_delegation(agent_def, delegates_to)

        swarm.add_agent(node_specific_def)
      end

      # Set lead agent
      swarm.lead = node.lead_agent

      swarm
    end

    # Clone an agent definition with different delegates_to
    #
    # @param agent_def [Agent::Definition] Original definition
    # @param delegates_to [Array<Symbol>] New delegation targets
    # @return [Agent::Definition] Cloned definition
    def clone_with_delegation(agent_def, delegates_to)
      config = agent_def.to_h
      config[:delegates_to] = delegates_to
      Agent::Definition.new(agent_def.name, config)
    end

    # Build execution order using topological sort (Kahn's algorithm)
    #
    # Processes all nodes in dependency order, starting from start_node.
    # Ensures all nodes are reachable from start_node.
    #
    # @return [Array<Symbol>] Ordered list of node names
    # @raise [CircularDependencyError] If circular dependency detected
    def build_execution_order
      # Build in-degree map and adjacency list
      in_degree = {}
      adjacency = Hash.new { |h, k| h[k] = [] }

      @nodes.each do |node_name, node|
        in_degree[node_name] = node.dependencies.size
        node.dependencies.each do |dep|
          adjacency[dep] << node_name
        end
      end

      # Start with nodes that have no dependencies
      queue = in_degree.select { |_, degree| degree == 0 }.keys
      order = []

      while queue.any?
        # Process nodes with all dependencies satisfied
        node_name = queue.shift
        order << node_name

        # Reduce in-degree for dependent nodes
        adjacency[node_name].each do |dependent|
          in_degree[dependent] -= 1
          queue << dependent if in_degree[dependent] == 0
        end
      end

      # Check for circular dependencies
      if order.size < @nodes.size
        unprocessed = @nodes.keys - order
        raise CircularDependencyError,
          "Circular dependency detected. Unprocessed nodes: #{unprocessed.join(", ")}"
      end

      # Verify start_node is in the execution order
      unless order.include?(@start_node)
        raise ConfigurationError,
          "start_node '#{@start_node}' is not reachable in the dependency graph"
      end

      # Verify start_node is actually first (or rearrange to make it first)
      # This ensures we start from the declared start_node
      start_index = order.index(@start_node)
      if start_index && start_index > 0
        # start_node has dependencies - this violates the assumption
        raise ConfigurationError,
          "start_node '#{@start_node}' has dependencies: #{@nodes[@start_node].dependencies.join(", ")}. " \
            "start_node must have no dependencies."
      end

      order
    end
  end
end
