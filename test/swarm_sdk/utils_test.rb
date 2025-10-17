# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class UtilsTest < Minitest::Test
    def test_symbolize_keys_with_hash
      input = { "name" => "test", "config" => { "key" => "value" } }
      result = Utils.symbolize_keys(input)

      assert_equal(:name, result.keys.first)
      assert_equal("test", result[:name])
      assert_equal({ key: "value" }, result[:config])
    end

    def test_symbolize_keys_with_array
      input = [{ "name" => "test" }, { "id" => "123" }]
      result = Utils.symbolize_keys(input)

      assert_equal(2, result.size)
      assert_equal({ name: "test" }, result[0])
      assert_equal({ id: "123" }, result[1])
    end

    def test_symbolize_keys_with_other_types
      # Should return the object unchanged for non-hash/array types
      assert_equal("test", Utils.symbolize_keys("test"))
      assert_equal(123, Utils.symbolize_keys(123))
      assert_nil(Utils.symbolize_keys(nil))
      assert(Utils.symbolize_keys(true))
    end

    def test_symbolize_keys_with_nested_arrays_and_hashes
      input = {
        "items" => [
          { "name" => "item1", "tags" => ["a", "b"] },
          { "name" => "item2", "meta" => { "count" => 5 } },
        ],
      }

      result = Utils.symbolize_keys(input)

      assert_equal(:items, result.keys.first)
      assert_equal({ name: "item1", tags: ["a", "b"] }, result[:items][0])
      assert_equal({ name: "item2", meta: { count: 5 } }, result[:items][1])
    end

    def test_stringify_keys_with_hash
      input = { name: "test", config: { key: "value" } }
      result = Utils.stringify_keys(input)

      assert_equal("name", result.keys.first)
      assert_equal("test", result["name"])
      assert_equal({ "key" => "value" }, result["config"])
    end

    def test_stringify_keys_with_array
      input = [{ name: "test" }, { id: "123" }]
      result = Utils.stringify_keys(input)

      assert_equal(2, result.size)
      assert_equal({ "name" => "test" }, result[0])
      assert_equal({ "id" => "123" }, result[1])
    end

    def test_stringify_keys_with_other_types
      # Should return the object unchanged for non-hash/array types
      assert_equal("test", Utils.stringify_keys("test"))
      assert_equal(123, Utils.stringify_keys(123))
      assert_nil(Utils.stringify_keys(nil))
      assert(Utils.stringify_keys(true))
    end

    def test_stringify_keys_with_nested_arrays_and_hashes
      input = {
        items: [
          { name: "item1", tags: ["a", "b"] },
          { name: "item2", meta: { count: 5 } },
        ],
      }

      result = Utils.stringify_keys(input)

      assert_equal("items", result.keys.first)
      assert_equal({ "name" => "item1", "tags" => ["a", "b"] }, result["items"][0])
      assert_equal({ "name" => "item2", "meta" => { "count" => 5 } }, result["items"][1])
    end

    def test_round_trip_conversion
      original = { "name" => "test", "items" => [{ "id" => 1 }] }

      # Convert to symbols and back to strings
      symbolized = Utils.symbolize_keys(original)
      stringified = Utils.stringify_keys(symbolized)

      assert_equal(original, stringified)
    end
  end
end
