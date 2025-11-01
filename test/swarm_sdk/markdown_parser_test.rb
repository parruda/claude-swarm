# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  class MarkdownParserTest < Minitest::Test
    def test_parse_valid_markdown_with_name_in_frontmatter
      content = <<~MARKDOWN
        ---
        name: backend_dev
        description: Backend developer
        model: gpt-5
        directory: .
        tools:
          - Read
          - Edit
        ---

        You are a backend developer specializing in Ruby on Rails.
        Build APIs and write tests.
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      assert_equal(:backend_dev, agent_def.name)
      assert_equal("Backend developer", agent_def.description)
      assert_equal("gpt-5", agent_def.model)
      assert_includes(agent_def.system_prompt, "You are a backend developer")
      assert_includes(agent_def.system_prompt, "Build APIs and write tests.")
      assert_equal([{ name: :Read, permissions: nil }, { name: :Edit, permissions: { allowed_paths: ["**/*"] } }], agent_def.tools)
    end

    def test_parse_valid_markdown_with_external_name
      content = <<~MARKDOWN
        ---
        description: Frontend developer
        model: gpt-5
        directory: .
        ---

        You are a frontend developer specializing in React.
      MARKDOWN

      agent_def = MarkdownParser.parse(content, :frontend_dev)

      assert_equal(:frontend_dev, agent_def.name)
      assert_equal("Frontend developer", agent_def.description)
      assert_includes(agent_def.system_prompt, "You are a frontend developer")
    end

    def test_parse_external_name_overrides_frontmatter_name
      content = <<~MARKDOWN
        ---
        name: old_name
        description: Test agent
        directory: .
        ---

        Test prompt.
      MARKDOWN

      agent_def = MarkdownParser.parse(content, :new_name)

      assert_equal(:new_name, agent_def.name)
    end

    def test_parse_with_all_agent_definition_fields
      content = <<~MARKDOWN
        ---
        name: full_agent
        description: Full configuration agent
        model: claude-sonnet-4
        provider: anthropic
        base_url: https://api.anthropic.com
        parameters:
          temperature: 0.7
          max_tokens: 4000
          reasoning: high
        directory: .
        tools:
          - Read
          - Edit
          - Bash
        delegates_to:
          - backend
          - frontend
        ---

        You are a fully configured agent.
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      assert_equal(:full_agent, agent_def.name)
      assert_equal("claude-sonnet-4", agent_def.model)
      assert_equal("anthropic", agent_def.provider)
      assert_in_delta(0.7, agent_def.parameters[:temperature])
      assert_equal(4000, agent_def.parameters[:max_tokens])
      assert_equal("https://api.anthropic.com", agent_def.base_url)
      assert_equal("high", agent_def.parameters[:reasoning])
      assert_equal(File.expand_path("."), agent_def.directory)
      assert_equal([{ name: :Read, permissions: nil }, { name: :Edit, permissions: { allowed_paths: ["**/*"] } }, { name: :Bash, permissions: nil }], agent_def.tools)
      assert_equal([:backend, :frontend], agent_def.delegates_to)
    end

    def test_parse_strips_prompt_whitespace
      content = <<~MARKDOWN
        ---
        name: test_agent
        description: Test
        directory: .
        coding_agent: true
        ---


        Test prompt with leading newlines.


      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      assert_includes(agent_def.system_prompt, "Test prompt with leading newlines.")
      assert_includes(agent_def.system_prompt, "You are an AI agent designed to help users")
      refute_match(/\A\n+/, agent_def.system_prompt)
      refute_match(/\n+\z/, agent_def.system_prompt)
    end

    def test_parse_missing_frontmatter_raises_error
      content = "Just some text without frontmatter"

      error = assert_raises(ConfigurationError) do
        MarkdownParser.parse(content)
      end

      assert_match(/invalid markdown agent definition format/i, error.message)
      assert_match(/expected yaml frontmatter/i, error.message)
    end

    def test_parse_empty_prompt_with_coding_agent_true_uses_base_prompt
      content = <<~MARKDOWN
        ---
        name: test
        description: Test
        directory: .
        coding_agent: true
        ---
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      # With coding_agent: true and empty prompt, should use base prompt
      assert_includes(agent_def.system_prompt, "You are an AI agent designed to help users")
      refute_includes(agent_def.system_prompt, "<%= cwd %>")
    end

    def test_parse_empty_prompt_with_coding_agent_false_uses_todo_scratchpad
      content = <<~MARKDOWN
        ---
        name: test
        description: Test
        directory: .
        coding_agent: false
        ---
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      # With coding_agent: false, default tools enabled, and empty prompt
      # Should get environment info only (TodoWrite/Scratchpad info is in tool descriptions)
      refute_empty(agent_def.system_prompt)
      assert_includes(agent_def.system_prompt, "Today's date")
      assert_includes(agent_def.system_prompt, "Current Environment")
      refute_includes(agent_def.system_prompt, "TodoWrite")
      refute_includes(agent_def.system_prompt, "Scratchpad")
    end

    def test_parse_empty_prompt_no_default_tools_empty_string
      content = <<~MARKDOWN
        ---
        name: test
        description: Test
        directory: .
        coding_agent: false
        disable_default_tools: true
        ---
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      # With coding_agent: false, disable_default_tools: true, and empty prompt
      # Should be empty
      assert_equal("", agent_def.system_prompt)
    end

    def test_parse_only_opening_frontmatter_delimiter_raises_error
      content = <<~MARKDOWN
        ---
        name: test
        description: Test

        This has no closing delimiter
      MARKDOWN

      error = assert_raises(ConfigurationError) do
        MarkdownParser.parse(content)
      end

      assert_match(/invalid markdown agent definition format/i, error.message)
    end

    def test_parse_invalid_yaml_raises_error
      content = <<~MARKDOWN
        ---
        name: test
        description: [unclosed array
        ---

        Test prompt
      MARKDOWN

      assert_raises(Psych::SyntaxError) do
        MarkdownParser.parse(content)
      end
    end

    def test_parse_non_hash_frontmatter_raises_error
      content = <<~MARKDOWN
        ---
        - list
        - items
        ---

        Test prompt
      MARKDOWN

      error = assert_raises(ConfigurationError) do
        MarkdownParser.parse(content)
      end

      assert_match(/invalid frontmatter format/i, error.message)
    end

    def test_parse_missing_name_raises_error
      content = <<~MARKDOWN
        ---
        description: Test agent
        directory: .
        ---

        Test prompt
      MARKDOWN

      error = assert_raises(ConfigurationError) do
        MarkdownParser.parse(content)
      end

      assert_match(/must include 'name'/i, error.message)
    end

    def test_parse_preserves_multiline_prompt
      content = <<~MARKDOWN
        ---
        name: test_agent
        description: Test
        directory: .
        ---

        Line 1
        Line 2
        Line 3

        Line 5 after blank line
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      assert_includes(agent_def.system_prompt, "Line 1")
      assert_includes(agent_def.system_prompt, "Line 2")
      assert_includes(agent_def.system_prompt, "Line 3")
      assert_includes(agent_def.system_prompt, "Line 5 after blank line")
    end

    def test_class_method_parse
      content = <<~MARKDOWN
        ---
        name: test
        description: Test
        directory: .
        ---

        Test prompt
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      assert_instance_of(Agent::Definition, agent_def)
      assert_equal(:test, agent_def.name)
    end

    def test_instance_method_parse
      content = <<~MARKDOWN
        ---
        name: test
        description: Test
        directory: .
        ---

        Test prompt
      MARKDOWN

      parser = MarkdownParser.new(content)
      agent_def = parser.parse

      assert_instance_of(Agent::Definition, agent_def)
      assert_equal(:test, agent_def.name)
    end

    def test_parse_with_symbol_in_frontmatter
      content = <<~MARKDOWN
        ---
        name: test
        description: Test
        directory: .
        tools:
          - :Read
          - :Edit
        ---

        Test prompt
      MARKDOWN

      agent_def = MarkdownParser.parse(content)

      assert_equal([{ name: :Read, permissions: nil }, { name: :Edit, permissions: { allowed_paths: ["**/*"] } }], agent_def.tools)
    end

    def test_frontmatter_pattern_constant
      assert_equal(/\A---\s*\n(.*?)\n---\s*\n(.*)\z/m, MarkdownParser::FRONTMATTER_PATTERN)
    end
  end
end
