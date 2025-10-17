# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class TimeFormatterTest < Minitest::Test
  def test_timestamp_with_time_object
    time = Time.new(2025, 1, 15, 12, 34, 56)
    result = SwarmCLI::UI::Formatters::Time.timestamp(time)

    assert_equal("[12:34:56]", result)
  end

  def test_timestamp_with_string
    result = SwarmCLI::UI::Formatters::Time.timestamp("2025-01-15 12:34:56")

    assert_equal("[12:34:56]", result)
  end

  def test_timestamp_with_nil
    assert_empty(SwarmCLI::UI::Formatters::Time.timestamp(nil))
  end

  def test_timestamp_with_invalid_string
    result = SwarmCLI::UI::Formatters::Time.timestamp("invalid")

    assert_empty(result)
  end

  def test_duration_zero
    assert_equal("0ms", SwarmCLI::UI::Formatters::Time.duration(0))
  end

  def test_duration_nil
    assert_equal("0ms", SwarmCLI::UI::Formatters::Time.duration(nil))
  end

  def test_duration_milliseconds
    assert_equal("500ms", SwarmCLI::UI::Formatters::Time.duration(0.5))
  end

  def test_duration_seconds
    assert_equal("2.3s", SwarmCLI::UI::Formatters::Time.duration(2.3))
  end

  def test_duration_minutes
    assert_equal("1m 5s", SwarmCLI::UI::Formatters::Time.duration(65))
  end

  def test_duration_hours
    assert_equal("1h 1m 5s", SwarmCLI::UI::Formatters::Time.duration(3665))
  end

  def test_relative_seconds_ago
    time = Time.now - 30
    result = SwarmCLI::UI::Formatters::Time.relative(time)

    assert_match(/\d+s ago/, result)
  end

  def test_relative_minutes_ago
    time = Time.now - 120
    result = SwarmCLI::UI::Formatters::Time.relative(time)

    assert_match(/\d+m ago/, result)
  end

  def test_relative_hours_ago
    time = Time.now - 7200
    result = SwarmCLI::UI::Formatters::Time.relative(time)

    assert_match(/\d+h ago/, result)
  end

  def test_relative_days_ago
    time = Time.now - 86400
    result = SwarmCLI::UI::Formatters::Time.relative(time)

    assert_match(/\d+d ago/, result)
  end

  def test_relative_nil
    assert_empty(SwarmCLI::UI::Formatters::Time.relative(nil))
  end
end
