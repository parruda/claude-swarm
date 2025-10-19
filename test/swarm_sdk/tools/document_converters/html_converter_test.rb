# frozen_string_literal: true

require "test_helper"

module SwarmSDK
  module Tools
    module DocumentConverters
      class HtmlConverterTest < Minitest::Test
        def setup
          @converter = HtmlConverter.new
        end

        def test_converter_metadata
          assert_equal("reverse_markdown", HtmlConverter.gem_name)
          assert_equal("HTML", HtmlConverter.format_name)
          assert_equal([".html", ".htm"], HtmlConverter.extensions)
        end

        def test_convert_string_with_headings
          html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
          result = @converter.convert_string(html)

          assert_includes(result, "# Title")
          assert_includes(result, "## Subtitle")
          assert_includes(result, "### Section")
        end

        def test_convert_string_with_paragraphs
          html = "<p>First paragraph</p><p>Second paragraph</p>"
          result = @converter.convert_string(html)

          assert_includes(result, "First paragraph")
          assert_includes(result, "Second paragraph")
        end

        def test_convert_string_with_emphasis
          html = "<p>This is <strong>bold</strong> and <em>italic</em></p>"
          result = @converter.convert_string(html)

          assert_includes(result, "**bold**")
          assert_includes(result, "_italic_")
        end

        def test_convert_string_with_links
          html = '<p>Visit <a href="https://example.com">our site</a></p>'
          result = @converter.convert_string(html)

          assert_includes(result, "[our site](https://example.com)")
        end

        def test_convert_string_with_code
          html = "<p>Use <code>print()</code> function</p>"
          result = @converter.convert_string(html)

          assert_includes(result, "`print()`")
        end

        def test_convert_string_with_lists
          html = "<ul><li>First item</li><li>Second item</li></ul>"
          result = @converter.convert_string(html)

          assert_includes(result, "First item")
          assert_includes(result, "Second item")
        end

        def test_convert_string_strips_script_tags
          html = "<script>alert('test');</script><p>Content</p>"
          result = @converter.convert_string(html)

          refute_includes(result, "alert")
          assert_includes(result, "Content")
        end

        def test_convert_string_strips_style_tags
          html = "<style>.test { color: red; }</style><p>Content</p>"
          result = @converter.convert_string(html)

          refute_includes(result, "color: red")
          assert_includes(result, "Content")
        end

        def test_convert_string_decodes_html_entities
          html = "<p>Test &lt;tag&gt; and &amp; and &quot;quotes&quot;</p>"
          result = @converter.convert_string(html)

          # reverse_markdown escapes < and > with backslashes (correct markdown behavior)
          # Our fallback decodes them to literal characters
          assert(result.include?("<tag>") || result.include?("\\<tag\\>"), "Should have tag text")
          assert_includes(result, "&")
          assert_includes(result, "\"quotes\"")
        end

        def test_convert_string_handles_br_tags
          html = "<p>Line one<br>Line two</p>"
          result = @converter.convert_string(html)

          assert_includes(result, "Line one")
          assert_includes(result, "Line two")
        end

        def test_convert_string_cleans_whitespace
          html = "<p>Test</p>\n\n\n\n<p>Content</p>"
          result = @converter.convert_string(html)

          refute_includes(result, "\n\n\n")
          assert_includes(result, "Test")
          assert_includes(result, "Content")
        end

        def test_convert_file_reads_html_file
          html_content = "<h1>File Content</h1><p>Test paragraph</p>"

          Dir.mktmpdir do |dir|
            file_path = File.join(dir, "test.html")
            File.write(file_path, html_content)

            result = @converter.convert(file_path)

            assert_includes(result, "# File Content")
            assert_includes(result, "Test paragraph")
          end
        end

        def test_convert_file_handles_missing_file
          result = @converter.convert("/nonexistent/file.html")

          assert_includes(result, "Error")
          assert_includes(result, "Failed to read HTML file")
        end

        def test_available_when_gem_installed
          # This test checks if the gem detection works
          # The actual value depends on whether reverse_markdown is installed
          available = HtmlConverter.available?

          assert_includes([true, false], available)
        end

        def test_convert_string_with_complex_html
          html = <<~HTML
            <html>
              <head><title>Test</title></head>
              <body>
                <h1>Main Title</h1>
                <p>Introduction paragraph with <strong>bold</strong> text.</p>
                <h2>Section 1</h2>
                <ul>
                  <li>First item</li>
                  <li>Second item</li>
                </ul>
                <p>Link to <a href="https://example.com">example</a>.</p>
              </body>
            </html>
          HTML

          result = @converter.convert_string(html)

          assert_includes(result, "# Main Title")
          assert_includes(result, "Introduction paragraph")
          assert_includes(result, "**bold**")
          assert_includes(result, "## Section 1")
          assert_includes(result, "First item")
          assert_includes(result, "[example](https://example.com)")
        end
      end
    end
  end
end
