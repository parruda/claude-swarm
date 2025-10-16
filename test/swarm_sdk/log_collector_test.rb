# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class LogCollectorTest < Minitest::Test
    def setup
      LogCollector.reset!
    end

    def teardown
      LogCollector.reset!
    end

    def test_on_log_registers_callback
      events = []
      LogCollector.on_log { |event| events << event }

      LogCollector.emit(type: "test", data: "value")

      assert_equal(1, events.size)
      assert_equal("test", events.first[:type])
    end

    def test_on_log_registers_multiple_callbacks
      events1 = []
      events2 = []

      LogCollector.on_log { |event| events1 << event }
      LogCollector.on_log { |event| events2 << event }

      LogCollector.emit(type: "test", data: "value")

      assert_equal(1, events1.size)
      assert_equal(1, events2.size)
      assert_equal(events1.first, events2.first)
    end

    def test_emit_with_no_callbacks_does_not_crash
      # Should not raise error when no callbacks registered
      # emit returns the result of Array(@callbacks).each, which is []
      result = LogCollector.emit(type: "test")

      assert_empty(result)
    end

    def test_emit_with_nil_callbacks
      # Explicitly test the nil case
      LogCollector.instance_variable_set(:@callbacks, nil)

      # Should not raise error
      result = LogCollector.emit(type: "test")

      assert_empty(result)
    end

    def test_freeze_prevents_new_callbacks
      LogCollector.freeze!

      error = assert_raises(StateError) do
        LogCollector.on_log { |_event| }
      end

      assert_match(/frozen/i, error.message)
    end

    def test_freeze_makes_callbacks_immutable
      events = []
      LogCollector.on_log { |event| events << event }

      LogCollector.freeze!

      # Should still work with existing callbacks
      LogCollector.emit(type: "test")

      assert_equal(1, events.size)
    end

    def test_frozen_returns_true_after_freeze
      refute_predicate(LogCollector, :frozen?)

      LogCollector.freeze!

      assert_predicate(LogCollector, :frozen?)
    end

    def test_freeze_with_nil_callbacks
      # Ensure @callbacks is nil
      LogCollector.instance_variable_set(:@callbacks, nil)

      # Should not raise error
      LogCollector.freeze!

      assert_predicate(LogCollector, :frozen?)
    end

    def test_reset_unfreezes_collector
      LogCollector.freeze!

      assert_predicate(LogCollector, :frozen?)

      LogCollector.reset!

      refute_predicate(LogCollector, :frozen?)

      # Should be able to register callbacks again
      events = []
      LogCollector.on_log { |event| events << event }
      LogCollector.emit(type: "test")

      assert_equal(1, events.size)
    end

    def test_emit_uses_defensive_copy
      events = []
      LogCollector.on_log { |event| events << event }

      # Freeze callbacks
      LogCollector.freeze!

      # Emit should work even with frozen array
      LogCollector.emit(type: "test1")
      LogCollector.emit(type: "test2")

      assert_equal(2, events.size)
    end

    def test_callbacks_receive_exact_entry
      received = nil
      LogCollector.on_log { |event| received = event }

      entry = { type: "test", agent: :backend, data: "value" }
      LogCollector.emit(entry)

      assert_equal(entry, received)
    end
  end
end
