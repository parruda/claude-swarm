# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class ModuleTest < Minitest::Test
    def test_refresh_models_silently_suppresses_log_output
      # Mock RubyLLM.models.refresh! to avoid HTTP calls
      RubyLLM.models.stub(:refresh!, ->() { nil }) do
        # Capture any output that might be produced
        output = capture_io do
          SwarmSDK.refresh_models_silently
        end

        # Should produce no output (suppressed)
        assert_empty(output[0], "Expected no stdout output")
        assert_empty(output[1], "Expected no stderr output")
      end
    end

    def test_refresh_models_silently_restores_log_level
      original_level = RubyLLM.logger.level

      # Mock RubyLLM.models.refresh! to avoid HTTP calls
      RubyLLM.models.stub(:refresh!, ->() { nil }) do
        SwarmSDK.refresh_models_silently
      end

      assert_equal(original_level, RubyLLM.logger.level, "Log level should be restored")
    end

    def test_refresh_models_silently_restores_log_level_on_error
      original_level = RubyLLM.logger.level

      # Mock RubyLLM.models to raise an error
      RubyLLM.models.stub(:refresh!, ->() { raise StandardError, "Test error" }) do
        # Should silently catch the error (not raise)
        SwarmSDK.refresh_models_silently
      end

      assert_equal(original_level, RubyLLM.logger.level, "Log level should be restored even on error")
    end

    def test_refresh_models_silently_calls_rubyllm_refresh
      refresh_called = false

      # Mock RubyLLM.models.refresh! to track if it was called
      RubyLLM.models.stub(:refresh!, ->() { refresh_called = true }) do
        # Suppress output since we're mocking
        capture_io do
          SwarmSDK.refresh_models_silently
        end
      end

      assert(refresh_called, "Expected RubyLLM.models.refresh! to be called")
    end

    def test_refresh_models_silently_temporarily_raises_log_level
      log_level_during_refresh = nil

      # Mock refresh! to capture the log level during execution
      RubyLLM.models.stub(:refresh!, ->() { log_level_during_refresh = RubyLLM.logger.level }) do
        capture_io do
          SwarmSDK.refresh_models_silently
        end
      end

      assert_equal(Logger::ERROR, log_level_during_refresh, "Log level should be ERROR during refresh")
    end
  end
end
