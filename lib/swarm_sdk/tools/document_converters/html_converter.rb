# frozen_string_literal: true

module SwarmSDK
  module Tools
    module DocumentConverters
      # Converter for HTML to Markdown
      # Uses reverse_markdown gem if available, otherwise falls back to simple regex-based conversion
      class HtmlConverter < BaseConverter
        class << self
          def gem_name
            "reverse_markdown"
          end

          def format_name
            "HTML"
          end

          def extensions
            [".html", ".htm"]
          end
        end

        # Convert HTML string to Markdown
        # @param html [String] HTML content to convert
        # @return [String] Markdown content
        def convert_string(html)
          if self.class.available?
            convert_with_gem(html)
          else
            convert_simple(html)
          end
        end

        # Convert HTML file to Markdown
        # @param file_path [String] Path to HTML file
        # @return [String] Markdown content
        def convert(file_path)
          html = File.read(file_path)
          convert_string(html)
        rescue StandardError => e
          error("Failed to read HTML file: #{e.message}")
        end

        private

        # Convert HTML to Markdown using reverse_markdown gem
        # @param html [String] HTML content
        # @return [String] Markdown content
        def convert_with_gem(html)
          require "reverse_markdown"

          ReverseMarkdown.convert(html, unknown_tags: :bypass, github_flavored: true)
        rescue StandardError
          # Fallback to simple conversion if gem conversion fails
          convert_simple(html)
        end

        # Simple regex-based HTML to Markdown conversion (fallback)
        # @param html [String] HTML content
        # @return [String] Markdown content
        def convert_simple(html)
          # Remove script and style tags
          content = html.gsub(%r{<script[^>]*>.*?</script>}im, "")
          content = content.gsub(%r{<style[^>]*>.*?</style>}im, "")

          # Convert common HTML elements
          content = content.gsub(%r{<h1[^>]*>(.*?)</h1>}im, "\n# \\1\n")
          content = content.gsub(%r{<h2[^>]*>(.*?)</h2>}im, "\n## \\1\n")
          content = content.gsub(%r{<h3[^>]*>(.*?)</h3>}im, "\n### \\1\n")
          content = content.gsub(%r{<h4[^>]*>(.*?)</h4>}im, "\n#### \\1\n")
          content = content.gsub(%r{<h5[^>]*>(.*?)</h5>}im, "\n##### \\1\n")
          content = content.gsub(%r{<h6[^>]*>(.*?)</h6>}im, "\n###### \\1\n")
          content = content.gsub(%r{<p[^>]*>(.*?)</p>}im, "\n\\1\n")
          content = content.gsub(%r{<br\s*/?>}i, "\n")
          content = content.gsub(%r{<strong[^>]*>(.*?)</strong>}im, "**\\1**")
          content = content.gsub(%r{<b[^>]*>(.*?)</b>}im, "**\\1**")
          content = content.gsub(%r{<em[^>]*>(.*?)</em>}im, "_\\1_")
          content = content.gsub(%r{<i[^>]*>(.*?)</i>}im, "_\\1_")
          content = content.gsub(%r{<code[^>]*>(.*?)</code>}im, "`\\1`")
          content = content.gsub(%r{<a[^>]*href=["']([^"']*)["'][^>]*>(.*?)</a>}im, "[\\2](\\1)")
          content = content.gsub(%r{<li[^>]*>(.*?)</li>}im, "- \\1\n")

          # Remove remaining HTML tags
          content = content.gsub(/<[^>]+>/, "")

          # Decode HTML entities
          content = content.gsub("&lt;", "<")
          content = content.gsub("&gt;", ">")
          content = content.gsub("&amp;", "&")
          content = content.gsub("&quot;", "\"")
          content = content.gsub("&#39;", "'")
          content = content.gsub("&nbsp;", " ")

          # Clean up whitespace
          content = content.gsub(/\n\n\n+/, "\n\n")
          content.strip
        end
      end
    end
  end
end
