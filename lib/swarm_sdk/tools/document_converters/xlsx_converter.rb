# frozen_string_literal: true

module SwarmSDK
  module Tools
    module DocumentConverters
      # Converts XLSX/XLS spreadsheets to text with image extraction
      class XlsxConverter < BaseConverter
        class << self
          def gem_name
            "roo"
          end

          def format_name
            "XLSX/XLS"
          end

          def extensions
            [".xlsx", ".xls"]
          end

          # XLS files require an additional gem
          def xls_gem_available?
            gem_available?("roo-xls")
          end
        end

        # Convert a spreadsheet to text/content
        # @param file_path [String] Path to the spreadsheet file
        # @return [String, RubyLLM::Content] Converted content or error message
        def convert(file_path)
          unless self.class.available?
            return unsupported_format_reminder(self.class.format_name, self.class.gem_name)
          end

          # Check for legacy XLS files
          extension = File.extname(file_path).downcase
          if extension == ".xls" && !self.class.xls_gem_available?
            return error("Legacy .xls files require the 'roo-xls' gem. Install with: gem install roo-xls")
          end

          spreadsheet = nil

          begin
            require "roo"
            require "csv"
            require "tmpdir"

            spreadsheet = Roo::Spreadsheet.open(file_path)

            # Extract images from all sheets
            image_paths = extract_images(spreadsheet, file_path)

            output = []
            output << "Spreadsheet: #{File.basename(file_path)}"
            output << "Sheets: #{spreadsheet.sheets.size}"
            output << "=" * 60
            output << ""

            spreadsheet.sheets.each_with_index do |sheet_name, sheet_idx|
              sheet = spreadsheet.sheet(sheet_name)

              output << "Sheet #{sheet_idx + 1}: #{sheet_name}"
              output << "-" * 60

              # Add sheet dimensions
              first_row = sheet.first_row
              last_row = sheet.last_row
              first_col = sheet.first_column
              last_col = sheet.last_column

              if first_row && last_row && first_col && last_col
                row_count = last_row - first_row + 1
                col_count = last_col - first_col + 1
                output << "Dimensions: #{row_count} rows × #{col_count} columns"
                output << ""
              else
                output << "(Empty sheet)"
                output << ""
                next
              end

              # Extract data rows
              sheet.each_row_streaming(pad_cells: true) do |row|
                row_values = row.map do |cell|
                  format_cell_value(cell)
                end

                # Skip completely empty rows
                next if row_values.all? { |v| v.nil? || v.empty? }

                # Format as CSV with proper escaping
                output << CSV.generate_line(row_values).chomp
              end

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
          rescue ArgumentError => e
            error("Failed to open spreadsheet: #{e.message}")
          rescue RangeError => e
            error("Sheet access error: #{e.message}")
          rescue Zip::Error => e
            error("Corrupted or invalid XLSX file: #{e.message}")
          rescue IOError => e
            error("File reading error: #{e.message}")
          rescue StandardError => e
            error("Failed to parse spreadsheet: #{e.message}")
          ensure
            # Always clean up resources
            spreadsheet.close if spreadsheet&.respond_to?(:close)
          end
        end

        private

        # Format cell value based on type
        # @param cell [Roo::Cell] The cell to format
        # @return [String] Formatted cell value
        def format_cell_value(cell)
          return "" if cell.nil? || cell.empty?

          case cell.type
          when :string
            cell.value.to_s
          when :float, :number
            cell.value.to_s
          when :date
            cell.value.strftime("%Y-%m-%d")
          when :datetime
            cell.value.strftime("%Y-%m-%d %H:%M:%S")
          when :time
            hours = (cell.value / 3600).to_i
            minutes = ((cell.value % 3600) / 60).to_i
            seconds = (cell.value % 60).to_i
            format("%02d:%02d:%02d", hours, minutes, seconds)
          when :boolean
            cell.value ? "TRUE" : "FALSE"
          when :formula
            # Returns calculated value, not the formula itself
            cell.value.to_s
          when :link
            cell.value.to_s
          when :percentage
            (cell.value * 100).to_s + "%"
          else
            cell.value.to_s
          end
        rescue StandardError
          "[ERROR]"
        end

        # Extract images from spreadsheet
        # @param spreadsheet [Roo::Spreadsheet] The spreadsheet
        # @param _xlsx_path [String] Path to the XLSX file (unused but kept for consistency)
        # @return [Array<String>] Array of temporary file paths containing extracted images
        def extract_images(spreadsheet, _xlsx_path)
          image_paths = []

          spreadsheet.sheets.each do |sheet_name|
            # Check if the spreadsheet supports image extraction
            next unless spreadsheet.respond_to?(:images)

            images = spreadsheet.images(sheet_name)
            next unless images && !images.empty?

            images.each do |img_path|
              if img_path && File.exist?(img_path)
                image_paths << img_path
              end
            end
          end

          image_paths
        rescue StandardError
          # If image extraction fails, don't fail the entire spreadsheet read
          []
        end
      end
    end
  end
end
