# frozen_string_literal: true

module SwarmSDK
  module Tools
    module ImageFormats
      # Builds TIFF image files from raw pixel data
      # Supports RGB and grayscale color spaces
      class TiffBuilder
        class << self
          # Build TIFF header for RGB images
          # @param width [Integer] Image width in pixels
          # @param height [Integer] Image height in pixels
          # @param bpc [Integer] Bits per component (typically 8)
          # @return [String] Binary TIFF header
          def build_rgb_header(width, height, bpc)
            # Helper lambdas for TIFF tags
            long_tag  = ->(tag, count, value) { [tag, 4, count, value].pack("ssII") }
            short_tag = ->(tag, count, value) { [tag, 3, count, value].pack("ssII") }

            tag_count = 8
            header = [73, 73, 42, 8, tag_count].pack("ccsIs") # Little-endian TIFF

            tiff = header.dup
            tiff << short_tag.call(256, 1, width)                             # ImageWidth
            tiff << short_tag.call(257, 1, height)                            # ImageHeight
            tiff << long_tag.call(258, 3, header.size + (tag_count * 12) + 4) # BitsPerSample
            tiff << short_tag.call(259, 1, 1)                                 # Compression (none)
            tiff << short_tag.call(262, 1, 2)                                 # PhotometricInterpretation (RGB)
            tiff << long_tag.call(273, 1, header.size + (tag_count * 12) + 16) # StripOffsets
            tiff << short_tag.call(277, 1, 3)                                 # SamplesPerPixel
            tiff << long_tag.call(279, 1, width * height * 3)                 # StripByteCounts
            tiff << [0].pack("I")                                             # Next IFD pointer
            tiff << [bpc, bpc, bpc].pack("III")                               # BitsPerSample values
            tiff
          end

          # Build TIFF header for grayscale images
          # @param width [Integer] Image width in pixels
          # @param height [Integer] Image height in pixels
          # @param bpc [Integer] Bits per component (typically 8)
          # @return [String] Binary TIFF header
          def build_gray_header(width, height, bpc)
            long_tag  = ->(tag, count, value) { [tag, 4, count, value].pack("ssII") }
            short_tag = ->(tag, count, value) { [tag, 3, count, value].pack("ssII") }

            tag_count = 8
            header = [73, 73, 42, 8, tag_count].pack("ccsIs")

            tiff = header.dup
            tiff << short_tag.call(256, 1, width)                             # ImageWidth
            tiff << short_tag.call(257, 1, height)                            # ImageHeight
            tiff << short_tag.call(258, 1, bpc)                               # BitsPerSample
            tiff << short_tag.call(259, 1, 1)                                 # Compression (none)
            tiff << short_tag.call(262, 1, 1)                                 # PhotometricInterpretation (MinIsBlack)
            tiff << long_tag.call(273, 1, header.size + (tag_count * 12) + 4) # StripOffsets
            tiff << short_tag.call(277, 1, 1)                                 # SamplesPerPixel
            tiff << long_tag.call(279, 1, width * height)                     # StripByteCounts
            tiff << [0].pack("I")                                             # Next IFD pointer
            tiff
          end
        end
      end
    end
  end
end
