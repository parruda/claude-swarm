# frozen_string_literal: true

module SwarmCLI
  module UI
    module Formatters
      # Number formatting utilities for terminal display
      class Number
        class << self
          # Format number with thousand separators
          # 5922 → "5,922"
          # 1500000 → "1,500,000"
          def format(num)
            return "0" if num.nil? || num.zero?

            num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
          end

          # Format number with compact units (K, M, B)
          # 5922 → "5.9K"
          # 1500000 → "1.5M"
          # 1500000000 → "1.5B"
          def compact(num)
            return "0" if num.nil? || num.zero?

            case num
            when 0...1_000
              num.to_s
            when 1_000...1_000_000
              "#{(num / 1_000.0).round(1)}K"
            when 1_000_000...1_000_000_000
              "#{(num / 1_000_000.0).round(1)}M"
            else
              "#{(num / 1_000_000_000.0).round(1)}B"
            end
          end

          # Format bytes with units (KB, MB, GB)
          # 1024 → "1.0 KB"
          # 1500000 → "1.4 MB"
          def bytes(num)
            return "0 B" if num.nil? || num.zero?

            case num
            when 0...1024
              "#{num} B"
            when 1024...1024**2
              "#{(num / 1024.0).round(1)} KB"
            when 1024**2...1024**3
              "#{(num / 1024.0**2).round(1)} MB"
            else
              "#{(num / 1024.0**3).round(1)} GB"
            end
          end
        end
      end
    end
  end
end
