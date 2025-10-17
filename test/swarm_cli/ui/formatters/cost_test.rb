# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class CostFormatterTest < Minitest::Test
  def setup
    @pastel = Pastel.new(enabled: false)
  end

  def test_format_zero
    result = SwarmCLI::UI::Formatters::Cost.format(0, pastel: @pastel)

    assert_equal("$0.0000", result)
  end

  def test_format_nil
    result = SwarmCLI::UI::Formatters::Cost.format(nil, pastel: @pastel)

    assert_equal("$0.0000", result)
  end

  def test_format_very_small_cost
    result = SwarmCLI::UI::Formatters::Cost.format(0.000123, pastel: @pastel)

    assert_includes(result, "$0.000123")
  end

  def test_format_small_cost
    result = SwarmCLI::UI::Formatters::Cost.format(0.0123, pastel: @pastel)

    assert_includes(result, "$0.0123")
  end

  def test_format_medium_cost
    result = SwarmCLI::UI::Formatters::Cost.format(0.5678, pastel: @pastel)

    assert_includes(result, "$0.5678")
  end

  def test_format_large_cost
    result = SwarmCLI::UI::Formatters::Cost.format(12.34, pastel: @pastel)

    assert_includes(result, "$12.34")
  end

  def test_format_plain_zero
    assert_equal("$0.0000", SwarmCLI::UI::Formatters::Cost.format_plain(0))
  end

  def test_format_plain_nil
    assert_equal("$0.0000", SwarmCLI::UI::Formatters::Cost.format_plain(nil))
  end

  def test_format_plain_very_small
    assert_equal("$0.000123", SwarmCLI::UI::Formatters::Cost.format_plain(0.000123))
  end

  def test_format_plain_small
    assert_equal("$0.0123", SwarmCLI::UI::Formatters::Cost.format_plain(0.0123))
  end

  def test_format_plain_medium
    assert_equal("$0.5678", SwarmCLI::UI::Formatters::Cost.format_plain(0.5678))
  end

  def test_format_plain_large
    assert_equal("$12.34", SwarmCLI::UI::Formatters::Cost.format_plain(12.34))
  end
end
