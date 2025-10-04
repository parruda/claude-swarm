# frozen_string_literal: true

require "test_helper"
require "tempfile"

class FrontmatterParserTest < Minitest::Test
  def setup
    @temp_files = []
  end

  def teardown
    @temp_files.each(&:close!)
  end

  def test_parses_valid_frontmatter_markdown
    content = <<~MARKDOWN
      ---
      description: "Frontend developer expert in React"
      directory: ./frontend
      model: sonnet
      connections: [backend]
      allowed_tools: [Read, Edit, Write]
      ---

      You are a frontend developer specializing in React and modern JavaScript.
      Your focus is on creating responsive, accessible user interfaces.
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")
    parser = ClaudeSwarm::FrontmatterParser.parse(file.path)

    assert_equal("Frontend developer expert in React", parser.config["description"])
    assert_equal("./frontend", parser.config["directory"])
    assert_equal("sonnet", parser.config["model"])
    assert_equal(["backend"], parser.config["connections"])
    assert_equal(["Read", "Edit", "Write"], parser.config["allowed_tools"])
    assert_includes(parser.config["prompt"], "frontend developer specializing in React")
  end

  def test_uses_markdown_content_as_prompt_when_not_specified
    content = <<~MARKDOWN
      ---
      description: "Backend developer"
      directory: .
      model: opus
      ---

      You are a backend developer with expertise in:
      - API design
      - Database optimization
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")
    parser = ClaudeSwarm::FrontmatterParser.parse(file.path)

    expected_prompt = "You are a backend developer with expertise in:\n- API design\n- Database optimization"

    assert_equal(expected_prompt, parser.config["prompt"])
  end

  def test_preserves_explicit_prompt_in_frontmatter
    content = <<~MARKDOWN
      ---
      description: "Test instance"
      directory: .
      prompt: "Explicit prompt from frontmatter"
      ---

      This is markdown content that should not override the prompt.
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")
    parser = ClaudeSwarm::FrontmatterParser.parse(file.path)

    assert_equal("Explicit prompt from frontmatter", parser.config["prompt"])
  end

  def test_handles_empty_markdown_content
    content = <<~MARKDOWN
      ---
      description: "Instance with no markdown content"
      directory: .
      ---
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")
    parser = ClaudeSwarm::FrontmatterParser.parse(file.path)

    assert_nil(parser.config["prompt"])
  end

  def test_raises_error_for_missing_opening_delimiter
    content = <<~MARKDOWN
      description: "Invalid frontmatter"
      directory: .
      ---

      Some content
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::FrontmatterParser.parse(file.path)
    end

    assert_includes(error.message, "must start with frontmatter delimiter")
  end

  def test_raises_error_for_missing_closing_delimiter
    content = <<~MARKDOWN
      ---
      description: "Unclosed frontmatter"
      directory: .

      Some content without closing delimiter
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::FrontmatterParser.parse(file.path)
    end

    assert_includes(error.message, "unclosed frontmatter")
  end

  def test_raises_error_for_invalid_yaml_in_frontmatter
    content = <<~MARKDOWN
      ---
      description: "Invalid YAML"
      directory: .
      invalid_yaml: [unclosed array
      ---

      Content
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")

    error = assert_raises(ClaudeSwarm::Error) do
      ClaudeSwarm::FrontmatterParser.parse(file.path)
    end

    assert_includes(error.message, "Invalid YAML in frontmatter")
  end

  def test_handles_complex_yaml_structures
    content = <<~MARKDOWN
      ---
      description: "Complex instance"
      directory: .
      model: opus
      mcps:
        - name: "server1"
          type: stdio
          command: "mcp serve"
      hooks:
        PreToolUse:
          - matcher: "Write|Edit"
            hooks:
              - type: "command"
                command: "echo test"
      vibe: true
      ---

      Complex instance with advanced configuration.
    MARKDOWN

    file = create_temp_file(content, suffix: ".md")
    parser = ClaudeSwarm::FrontmatterParser.parse(file.path)

    assert_equal("Complex instance", parser.config["description"])
    assert(parser.config["vibe"])
    assert_equal(1, parser.config["mcps"].size)
    assert_equal("server1", parser.config["mcps"][0]["name"])
    assert(parser.config["hooks"])
  end

  private

  def create_temp_file(content, suffix: ".txt")
    file = Tempfile.new(["test", suffix])
    file.write(content)
    file.flush
    @temp_files << file
    file
  end
end
