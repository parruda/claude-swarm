# frozen_string_literal: true

module SwarmSDK
  module Tools
    module DocumentConverters
      # Converts PDF documents to text with image extraction
      class PdfConverter < BaseConverter
        class << self
          def gem_name
            "pdf-reader"
          end

          def format_name
            "PDF"
          end

          def extensions
            [".pdf"]
          end
        end

        # Convert a PDF document to text/content
        # @param file_path [String] Path to the PDF file
        # @return [String, RubyLLM::Content] Converted content or error message
        def convert(file_path)
          unless self.class.available?
            return unsupported_format_reminder(self.class.format_name, self.class.gem_name)
          end

          begin
            require "pdf-reader"
            require "tmpdir"
            require "fileutils"

            reader = PDF::Reader.new(file_path)
            output = []
            output << "PDF Document: #{File.basename(file_path)}"
            output << "=" * 60
            output << "Pages: #{reader.page_count}"
            output << ""

            # Extract images from the PDF
            image_paths = ImageExtractors::PdfImageExtractor.extract_images(reader, file_path)

            # Extract text from each page
            reader.pages.each_with_index do |page, index|
              output << "Page #{index + 1}:"
              output << "-" * 60
              text = page.text.strip
              output << (text.empty? ? "(No text content on this page)" : text)
              output << ""
            end

            text_content = output.join("\n")

            # If there are images, return Content with attachments
            if image_paths.any?
              content = RubyLLM::Content.new(text_content)
              image_paths.each do |image_path|
                content.add_attachment(image_path)
              end
              content
            else
              # No images, return just text
              text_content
            end
          rescue PDF::Reader::MalformedPDFError => e
            error("PDF file is malformed: #{e.message}")
          rescue PDF::Reader::UnsupportedFeatureError => e
            error("PDF contains unsupported features: #{e.message}")
          rescue StandardError => e
            error("Failed to parse PDF file: #{e.message}")
          end
        end
      end
    end
  end
end
