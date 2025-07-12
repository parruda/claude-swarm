# frozen_string_literal: true

require "test_helper"

class ClaudeSwarmTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil(::ClaudeSwarm::VERSION)
  end

  def test_cli_exists
    assert_kind_of(Class, ClaudeSwarm::CLI)
  end

  def test_with_clean_environment
    # Save original values
    original_rubyopt = ENV["RUBYOPT"]
    original_gem_home = ENV["GEM_HOME"]
    
    # Set some test environment variables
    ENV["BUNDLE_TEST"] = "bundle_value"
    ENV["RUBYOPT"] = "ruby_opt_value"
    ENV["GEM_HOME"] = "gem_home_value"

    executed = false
    ClaudeSwarm.with_clean_environment do
      executed = true
      # Bundle vars should be removed by Bundler.with_unbundled_env
      assert_nil(ENV["BUNDLE_TEST"])
      # Ruby vars should be removed by our additional cleaning
      assert_nil(ENV["RUBYOPT"])
      assert_nil(ENV["GEM_HOME"])
    end

    assert(executed, "Block should have been executed")
    
    # After block, test vars should be restored (but original Ruby vars might be different)
    assert_equal("bundle_value", ENV["BUNDLE_TEST"])
  ensure
    # Clean up test variables
    ENV.delete("BUNDLE_TEST")
    # Restore original values
    if original_rubyopt
      ENV["RUBYOPT"] = original_rubyopt
    else
      ENV.delete("RUBYOPT")
    end
    if original_gem_home
      ENV["GEM_HOME"] = original_gem_home
    else
      ENV.delete("GEM_HOME")
    end
  end

  def test_clean_env_hash
    # Set some test environment variables
    ENV["BUNDLE_TEST"] = "bundle_value"
    ENV["RUBY_VERSION"] = "ruby_version_value"
    ENV["GEM_HOME"] = "gem_home_value"
    ENV["RUBYOPT"] = "rubyopt_value"
    ENV["MY_NORMAL_VAR"] = "normal_value"

    clean_hash = ClaudeSwarm.clean_env_hash

    # These should be removed
    refute(clean_hash.key?("BUNDLE_TEST"))
    refute(clean_hash.key?("RUBY_VERSION"))
    refute(clean_hash.key?("GEM_HOME"))
    refute(clean_hash.key?("RUBYOPT"))
    # Normal vars should remain
    assert_equal("normal_value", clean_hash["MY_NORMAL_VAR"])
  ensure
    # Clean up test variables
    ENV.delete("BUNDLE_TEST")
    ENV.delete("RUBY_VERSION")
    ENV.delete("GEM_HOME")
    ENV.delete("RUBYOPT")
    ENV.delete("MY_NORMAL_VAR")
  end
end
