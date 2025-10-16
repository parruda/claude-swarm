# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class LogStreamTest < Minitest::Test
    # Mock emitter for testing
    class MockEmitter
      attr_reader :events

      def initialize
        @events = []
      end

      def emit(entry)
        @events << entry
      end
    end

    def setup
      LogStream.reset!
    end

    def teardown
      LogStream.reset!
    end

    def test_emit_with_no_emitter_does_not_crash
      # Should not raise error when no emitter configured
      assert_nil(LogStream.emit(type: "test", data: "value"))
    end

    def test_emit_with_emitter_forwards_event
      emitter = MockEmitter.new

      LogStream.emitter = emitter
      LogStream.emit(type: "test", agent: :backend, data: "value")

      assert_equal(1, emitter.events.size)
      event = emitter.events.first

      assert_equal("test", event[:type])
      assert_equal(:backend, event[:agent])
      assert_equal("value", event[:data])
    end

    def test_emit_adds_timestamp
      emitter = MockEmitter.new

      LogStream.emitter = emitter

      Time.now.utc.iso8601
      LogStream.emit(type: "test")
      Time.now.utc.iso8601

      event = emitter.events.first

      assert(event.key?(:timestamp))
      assert_instance_of(String, event[:timestamp])

      # Timestamp should be in ISO8601 format
      assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, event[:timestamp])
    end

    def test_emit_compacts_nil_values
      emitter = MockEmitter.new

      LogStream.emitter = emitter
      LogStream.emit(type: "test", data: "value", empty: nil)

      event = emitter.events.first

      refute(event.key?(:empty), "Expected nil values to be removed")
      assert(event.key?(:data))
    end

    def test_reset_clears_emitter
      LogStream.emitter = Object.new

      assert_predicate(LogStream, :enabled?)

      LogStream.reset!

      refute_predicate(LogStream, :enabled?)
    end

    def test_enabled_returns_true_when_emitter_set
      refute_predicate(LogStream, :enabled?)

      LogStream.emitter = Object.new

      assert_predicate(LogStream, :enabled?)
    end

    def test_enabled_returns_false_when_no_emitter
      LogStream.reset!

      refute_predicate(LogStream, :enabled?)
    end

    def test_emitter_accessor_allows_reading
      emitter = Object.new
      LogStream.emitter = emitter

      assert_same(emitter, LogStream.emitter)
    end
  end
end
