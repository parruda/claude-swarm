# frozen_string_literal: true

require "test_helper"
require "swarm_cli"

class NumberFormatterTest < Minitest::Test
  def test_format_zero
    assert_equal("0", SwarmCLI::UI::Formatters::Number.format(0))
  end

  def test_format_nil
    assert_equal("0", SwarmCLI::UI::Formatters::Number.format(nil))
  end

  def test_format_small_number
    assert_equal("123", SwarmCLI::UI::Formatters::Number.format(123))
  end

  def test_format_thousands
    assert_equal("5,922", SwarmCLI::UI::Formatters::Number.format(5922))
  end

  def test_format_millions
    assert_equal("1,500,000", SwarmCLI::UI::Formatters::Number.format(1_500_000))
  end

  def test_compact_zero
    assert_equal("0", SwarmCLI::UI::Formatters::Number.compact(0))
  end

  def test_compact_nil
    assert_equal("0", SwarmCLI::UI::Formatters::Number.compact(nil))
  end

  def test_compact_under_thousand
    assert_equal("500", SwarmCLI::UI::Formatters::Number.compact(500))
  end

  def test_compact_thousands
    assert_equal("5.9K", SwarmCLI::UI::Formatters::Number.compact(5922))
  end

  def test_compact_millions
    assert_equal("1.5M", SwarmCLI::UI::Formatters::Number.compact(1_500_000))
  end

  def test_compact_billions
    assert_equal("2.3B", SwarmCLI::UI::Formatters::Number.compact(2_300_000_000))
  end

  def test_bytes_zero
    assert_equal("0 B", SwarmCLI::UI::Formatters::Number.bytes(0))
  end

  def test_bytes_nil
    assert_equal("0 B", SwarmCLI::UI::Formatters::Number.bytes(nil))
  end

  def test_bytes_under_kb
    assert_equal("512 B", SwarmCLI::UI::Formatters::Number.bytes(512))
  end

  def test_bytes_kilobytes
    assert_equal("1.0 KB", SwarmCLI::UI::Formatters::Number.bytes(1024))
  end

  def test_bytes_megabytes
    assert_equal("1.4 MB", SwarmCLI::UI::Formatters::Number.bytes(1_500_000))
  end

  def test_bytes_gigabytes
    assert_equal("2.3 GB", SwarmCLI::UI::Formatters::Number.bytes(2_500_000_000))
  end
end
