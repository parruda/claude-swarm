# frozen_string_literal: true

module SwarmSDK
  module Tools
    module DocumentConverters
      # Converts DOCX documents to text with image extraction
      class DocxConverter < BaseConverter
        class << self
          def gem_name
            "docx"
          end

          def format_name
            "DOCX"
          end

          def extensions
            [".docx", ".doc"]
          end
        end

        # Convert a DOCX document to text/content
        # @param file_path [String] Path to the DOCX file
        # @return [String, RubyLLM::Content] Converted content or error message
        def convert(file_path)
          unless self.class.available?
            return unsupported_format_reminder(self.class.format_name, self.class.gem_name)
          end

          # Check for legacy DOC format
          if File.extname(file_path).downcase == ".doc"
            return error("DOC format is not supported. Please convert to DOCX first.")
          end

          begin
            require "docx"
            require "tmpdir"

            doc = Docx::Document.open(file_path)

            # Extract images from the DOCX
            image_paths = ImageExtractors::DocxImageExtractor.extract_images(doc, file_path)

            output = []
            output << "Document: #{File.basename(file_path)}"
            output << "=" * 60
            output << ""

            # Extract paragraphs
            paragraphs = doc.paragraphs.map(&:text).reject(&:empty?)

            # Check for empty document
            if paragraphs.empty? && doc.tables.empty?
              output << "(Document is empty - no paragraphs or tables)"
            else
              output += paragraphs

              # Extract tables with enhanced formatting
              if doc.tables.any?
                output << ""
                output << "Tables:"
                output << "-" * 60

                doc.tables.each_with_index do |table, idx|
                  output << ""
                  output << "Table #{idx + 1} (#{table.row_count} rows × #{table.column_count} columns):"

                  table.rows.each do |row|
                    output << row.cells.map(&:text).join(" | ")
                  end
                end
              end
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
          rescue Zip::Error => e
            error("Invalid or corrupted DOCX file: #{e.message}")
          rescue Errno::ENOENT => e
            error("File not found or missing document.xml: #{e.message}")
          rescue StandardError => e
            error("Failed to parse DOCX file: #{e.message}")
          end
        end
      end
    end
  end
end
