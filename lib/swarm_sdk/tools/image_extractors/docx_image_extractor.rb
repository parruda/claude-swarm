# frozen_string_literal: true

module SwarmSDK
  module Tools
    module ImageExtractors
      # Extracts images from DOCX documents
      # DOCX files are ZIP archives with images stored in word/media/
      class DocxImageExtractor
        class << self
          # Extract all images from a DOCX document
          # @param doc [Docx::Document] The DOCX document instance
          # @param docx_path [String] Path to the DOCX file
          # @return [Array<String>] Array of temporary file paths containing extracted images
          def extract_images(doc, docx_path)
            image_paths = []
            temp_dir = Dir.mktmpdir("docx_images_#{File.basename(docx_path, ".*")}")

            # DOCX files are ZIP archives with images in word/media/
            doc.zip.glob("word/media/*").each do |entry|
              next unless entry.file?

              # Check if it's an image by extension
              next unless entry.name.match?(/\.(png|jpe?g|gif|bmp|tiff?)$/i)

              output_path = File.join(temp_dir, File.basename(entry.name))

              File.open(output_path, "wb") do |f|
                f.write(doc.zip.read(entry.name))
              end

              image_paths << output_path
            end

            image_paths
          rescue StandardError
            # If image extraction fails, don't fail the entire document read
            []
          end
        end
      end
    end
  end
end
