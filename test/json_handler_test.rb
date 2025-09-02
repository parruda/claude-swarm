# frozen_string_literal: true

require "test_helper"
require "tempfile"

class JsonHandlerTest < Minitest::Test
  def setup
    @valid_json = '{"name": "test", "value": 42}'
    @invalid_json = '{"name": "test", value: 42}' # Missing quotes around value
    @valid_object = { name: "test", value: 42 }
  end

  # Tests for parse method
  def test_parse_valid_json
    result = ClaudeSwarm::JsonHandler.parse(@valid_json)

    assert_equal("test", result["name"])
    assert_equal(42, result["value"])
  end

  def test_parse_invalid_json_returns_original
    result = ClaudeSwarm::JsonHandler.parse(@invalid_json)

    assert_equal(@invalid_json, result)
  end

  def test_parse_with_raise_on_error_true
    assert_raises(JSON::ParserError) do
      ClaudeSwarm::JsonHandler.parse(@invalid_json, raise_on_error: true)
    end
  end

  def test_parse_with_raise_on_error_false
    result = ClaudeSwarm::JsonHandler.parse(@invalid_json, raise_on_error: false)

    assert_equal(@invalid_json, result)
  end

  # Tests for parse! method
  def test_parse_bang_valid_json
    result = ClaudeSwarm::JsonHandler.parse!(@valid_json)

    assert_equal("test", result["name"])
    assert_equal(42, result["value"])
  end

  def test_parse_bang_invalid_json_raises
    assert_raises(JSON::ParserError) do
      ClaudeSwarm::JsonHandler.parse!(@invalid_json)
    end
  end

  # Tests for parse_file! method
  def test_parse_file_bang_valid_json
    Tempfile.create(["test", ".json"]) do |file|
      file.write(@valid_json)
      file.flush

      result = ClaudeSwarm::JsonHandler.parse_file!(file.path)

      assert_equal("test", result["name"])
      assert_equal(42, result["value"])
    end
  end

  def test_parse_file_bang_invalid_json_raises
    Tempfile.create(["test", ".json"]) do |file|
      file.write(@invalid_json)
      file.flush

      assert_raises(JSON::ParserError) do
        ClaudeSwarm::JsonHandler.parse_file!(file.path)
      end
    end
  end

  def test_parse_file_bang_nonexistent_file_raises
    assert_raises(Errno::ENOENT) do
      ClaudeSwarm::JsonHandler.parse_file!("/nonexistent/file.json")
    end
  end

  # Tests for parse_file method
  def test_parse_file_valid_json
    Tempfile.create(["test", ".json"]) do |file|
      file.write(@valid_json)
      file.flush

      result = ClaudeSwarm::JsonHandler.parse_file(file.path)

      assert_equal("test", result["name"])
      assert_equal(42, result["value"])
    end
  end

  def test_parse_file_invalid_json_returns_nil
    Tempfile.create(["test", ".json"]) do |file|
      file.write(@invalid_json)
      file.flush

      result = ClaudeSwarm::JsonHandler.parse_file(file.path)

      assert_nil(result)
    end
  end

  def test_parse_file_nonexistent_file_returns_nil
    result = ClaudeSwarm::JsonHandler.parse_file("/nonexistent/file.json")

    assert_nil(result)
  end

  # Tests for pretty_generate method
  def test_pretty_generate_valid_object
    result = ClaudeSwarm::JsonHandler.pretty_generate(@valid_object)

    assert_kind_of(String, result)
    assert_match(/"name":\s+"test"/, result)
    assert_match(/"value":\s+42/, result)
    # Check it's pretty formatted (has newlines and indentation)
    assert_match(/\n/, result)
  end

  def test_pretty_generate_with_circular_reference_returns_nil
    obj = {}
    obj[:self] = obj

    result = ClaudeSwarm::JsonHandler.pretty_generate(obj)

    assert_nil(result)
  end

  def test_pretty_generate_with_raise_on_error_true
    obj = {}
    obj[:self] = obj

    assert_raises(JSON::NestingError) do
      ClaudeSwarm::JsonHandler.pretty_generate(obj, raise_on_error: true)
    end
  end

  # Tests for pretty_generate! method
  def test_pretty_generate_bang_valid_object
    result = ClaudeSwarm::JsonHandler.pretty_generate!(@valid_object)

    assert_kind_of(String, result)
    assert_match(/"name":\s+"test"/, result)
    assert_match(/"value":\s+42/, result)
  end

  def test_pretty_generate_bang_with_circular_reference_raises
    obj = {}
    obj[:self] = obj

    assert_raises(JSON::NestingError) do
      ClaudeSwarm::JsonHandler.pretty_generate!(obj)
    end
  end

  # Tests for write_file method
  def test_write_file_success
    Tempfile.create(["test", ".json"]) do |file|
      file_path = file.path
      file.close

      result = ClaudeSwarm::JsonHandler.write_file(file_path, @valid_object)

      assert(result)

      # Verify the content was written correctly
      written_content = File.read(file_path)
      parsed = JSON.parse(written_content)

      assert_equal("test", parsed["name"])
      assert_equal(42, parsed["value"])
    end
  end

  def test_write_file_with_invalid_object_returns_false
    obj = {}
    obj[:self] = obj

    Tempfile.create(["test", ".json"]) do |file|
      file_path = file.path
      file.close

      result = ClaudeSwarm::JsonHandler.write_file(file_path, obj)

      refute(result)
    end
  end

  def test_write_file_to_readonly_directory_returns_false
    # Try to write to a path that doesn't exist
    result = ClaudeSwarm::JsonHandler.write_file("/nonexistent/dir/file.json", @valid_object)

    refute(result)
  end

  # Tests for write_file! method
  def test_write_file_bang_success
    Tempfile.create(["test", ".json"]) do |file|
      file_path = file.path
      file.close

      ClaudeSwarm::JsonHandler.write_file!(file_path, @valid_object)

      # Verify the content was written correctly
      written_content = File.read(file_path)
      parsed = JSON.parse(written_content)

      assert_equal("test", parsed["name"])
      assert_equal(42, parsed["value"])
    end
  end

  def test_write_file_bang_with_invalid_object_raises
    obj = {}
    obj[:self] = obj

    Tempfile.create(["test", ".json"]) do |file|
      file_path = file.path
      file.close

      assert_raises(JSON::NestingError) do
        ClaudeSwarm::JsonHandler.write_file!(file_path, obj)
      end
    end
  end

  def test_write_file_bang_to_readonly_directory_raises
    assert_raises(SystemCallError) do
      ClaudeSwarm::JsonHandler.write_file!("/nonexistent/dir/file.json", @valid_object)
    end
  end

  # Test pretty formatting
  def test_pretty_generate_produces_formatted_output
    result = ClaudeSwarm::JsonHandler.pretty_generate!(@valid_object)

    # Should have multiple lines
    lines = result.split("\n")

    assert_operator(lines.length, :>, 1, "Pretty generated JSON should have multiple lines")

    # Should have indentation
    assert_match(/^\s+/, lines[1], "Pretty generated JSON should have indentation")
  end

  # Test complex objects
  def test_handles_nested_objects
    nested = {
      level1: {
        level2: {
          level3: "deep",
          array: [1, 2, 3],
        },
      },
    }

    json_string = ClaudeSwarm::JsonHandler.pretty_generate!(nested)
    parsed = ClaudeSwarm::JsonHandler.parse!(json_string)

    assert_equal("deep", parsed["level1"]["level2"]["level3"])
    assert_equal([1, 2, 3], parsed["level1"]["level2"]["array"])
  end

  def test_handles_arrays
    array_obj = {
      items: ["one", "two", "three"],
      numbers: [1, 2.5, 3],
    }

    json_string = ClaudeSwarm::JsonHandler.pretty_generate!(array_obj)
    parsed = ClaudeSwarm::JsonHandler.parse!(json_string)

    assert_equal(["one", "two", "three"], parsed["items"])
    assert_equal([1, 2.5, 3], parsed["numbers"])
  end

  def test_handles_unicode
    unicode_obj = {
      emoji: "🚀",
      japanese: "こんにちは",
      special: "café",
    }

    json_string = ClaudeSwarm::JsonHandler.pretty_generate!(unicode_obj)
    parsed = ClaudeSwarm::JsonHandler.parse!(json_string)

    assert_equal("🚀", parsed["emoji"])
    assert_equal("こんにちは", parsed["japanese"])
    assert_equal("café", parsed["special"])
  end

  # Integration test
  def test_roundtrip_file_operations
    Tempfile.create(["test", ".json"]) do |file|
      file_path = file.path
      file.close

      # Write object to file
      ClaudeSwarm::JsonHandler.write_file!(file_path, @valid_object)

      # Read it back
      result = ClaudeSwarm::JsonHandler.parse_file!(file_path)

      assert_equal("test", result["name"])
      assert_equal(42, result["value"])
    end
  end
end
