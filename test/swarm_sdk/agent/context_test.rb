# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class AgentContextTest < Minitest::Test
    def test_initialize_sets_name
      context = Agent::Context.new(name: :backend)

      assert_equal(:backend, context.name)
    end

    def test_initialize_converts_name_to_symbol
      context = Agent::Context.new(name: "backend")

      assert_equal(:backend, context.name)
    end

    def test_initialize_sets_delegation_tools
      context = Agent::Context.new(
        name: :backend,
        delegation_tools: ["DelegateToDatabase", "DelegateToAuth"],
      )

      assert(context.delegation_tool?("DelegateToDatabase"))
      assert(context.delegation_tool?("DelegateToAuth"))
      refute(context.delegation_tool?("SomeOtherTool"))
    end

    def test_initialize_converts_delegation_tools_to_strings
      context = Agent::Context.new(
        name: :backend,
        delegation_tools: [:database, :auth],
      )

      assert(context.delegation_tool?("database"))
      assert(context.delegation_tool?("auth"))
    end

    def test_initialize_sets_metadata
      metadata = { role: "backend", version: "1.0" }
      context = Agent::Context.new(name: :backend, metadata: metadata)

      assert_equal(metadata, context.metadata)
    end

    def test_track_delegation_records_call
      context = Agent::Context.new(name: :backend)

      context.track_delegation(call_id: "call_123", target: "DelegateToDatabase")

      assert(context.delegation?(call_id: "call_123"))
      assert_equal("DelegateToDatabase", context.delegation_target(call_id: "call_123"))
    end

    def test_delegation_returns_false_for_unknown_call
      context = Agent::Context.new(name: :backend)

      refute(context.delegation?(call_id: "unknown"))
    end

    def test_delegation_target_returns_nil_for_unknown_call
      context = Agent::Context.new(name: :backend)

      assert_nil(context.delegation_target(call_id: "unknown"))
    end

    def test_clear_delegation_removes_tracking
      context = Agent::Context.new(name: :backend)

      context.track_delegation(call_id: "call_123", target: "DelegateToDatabase")

      assert(context.delegation?(call_id: "call_123"))

      context.clear_delegation(call_id: "call_123")

      refute(context.delegation?(call_id: "call_123"))
      assert_nil(context.delegation_target(call_id: "call_123"))
    end

    def test_delegation_tool_checks_tool_name
      context = Agent::Context.new(
        name: :backend,
        delegation_tools: ["DelegateToDatabase"],
      )

      assert(context.delegation_tool?("DelegateToDatabase"))
      refute(context.delegation_tool?("Read"))
    end

    def test_hit_warning_threshold_returns_true_first_time
      context = Agent::Context.new(name: :backend)

      result = context.hit_warning_threshold?(80)

      assert(result, "Expected hit_warning_threshold? to return true on first hit")
    end

    def test_hit_warning_threshold_returns_false_second_time
      context = Agent::Context.new(name: :backend)

      context.hit_warning_threshold?(80) # First hit
      result = context.hit_warning_threshold?(80) # Second hit

      refute(result, "Expected hit_warning_threshold? to return false on second hit")
    end

    def test_warning_threshold_hit_tracks_hit_thresholds
      context = Agent::Context.new(name: :backend)

      refute(context.warning_threshold_hit?(80))

      context.hit_warning_threshold?(80)

      assert(context.warning_threshold_hit?(80))
    end

    def test_warning_threshold_hit_tracks_multiple_thresholds
      context = Agent::Context.new(name: :backend)

      context.hit_warning_threshold?(80)
      context.hit_warning_threshold?(90)

      assert(context.warning_threshold_hit?(80))
      assert(context.warning_threshold_hit?(90))
      refute(context.warning_threshold_hit?(95))
    end

    def test_warning_thresholds_hit_reader_returns_set
      context = Agent::Context.new(name: :backend)

      assert_instance_of(Set, context.warning_thresholds_hit)
      assert_empty(context.warning_thresholds_hit)
    end

    def test_delegation_tools_reader_returns_set
      context = Agent::Context.new(
        name: :backend,
        delegation_tools: ["DelegateToDatabase"],
      )

      assert_instance_of(Set, context.delegation_tools)
      assert_includes(context.delegation_tools, "DelegateToDatabase")
    end

    def test_context_warning_thresholds_constant
      assert_equal([80, 90], Agent::Context::CONTEXT_WARNING_THRESHOLDS)
    end
  end
end
