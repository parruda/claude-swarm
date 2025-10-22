# frozen_string_literal: true

module SwarmMemory
  module CLI
    # CLI commands for managing SwarmMemory embeddings
    #
    # Registers with SwarmCLI to provide:
    #   swarm memory setup      - Download embedding model
    #   swarm memory status     - Check model cache status
    #   swarm memory cache-dir  - Show cache location
    class Commands
      class << self
        # Execute memory command (called by SwarmCLI)
        #
        # @param args [Array<String>] Command arguments (e.g., ["defrag", ".swarm/memory"])
        # @return [void]
        def execute(args)
          subcommand = args.first
          subcommand_args = args[1..] # Remaining args after subcommand

          case subcommand
          when "setup"
            setup_embeddings
          when "status"
            show_status
          when "cache-path"
            show_cache_path
          when "defrag"
            defrag_memory(subcommand_args)
          else
            show_help
            exit(1)
          end
        rescue StandardError => e
          $stderr.puts "Error: #{e.message}"
          exit(1)
        end

        private

        def setup_embeddings
          puts "Setting up SwarmMemory embeddings..."
          puts

          begin
            embedder = SwarmMemory::Embeddings::InformersEmbedder.new
          rescue StandardError => e
            $stderr.puts "Error: #{e.message}"
            $stderr.puts
            $stderr.puts "Make sure the 'informers' gem is installed:"
            $stderr.puts "  gem install informers"
            exit(1)
          end

          if embedder.cached?
            puts "✓ Model already cached!"
            puts "  Location: #{Informers.cache_dir}/sentence-transformers/all-MiniLM-L6-v2/"
            puts
            puts "No download needed. Embeddings ready to use."
          else
            puts "Model not cached. Downloading..."
            puts "  Model: sentence-transformers/all-MiniLM-L6-v2"
            puts "  Size: ~90MB (unquantized ONNX)"
            puts "  Location: #{Informers.cache_dir}"
            puts
            puts "This is a one-time download. Please wait..."
            puts

            embedder.preload!

            puts
            puts "✓ Setup complete!"
            puts "  Model cached and ready to use."
            puts "  Semantic search is now available."
          end

          exit(0)
        end

        def show_status
          begin
            embedder = SwarmMemory::Embeddings::InformersEmbedder.new
          rescue StandardError => e
            $stderr.puts "Error: #{e.message}"
            $stderr.puts
            $stderr.puts "Make sure the 'informers' gem is installed:"
            $stderr.puts "  gem install informers"
            exit(1)
          end

          puts "SwarmMemory Embedding Status"
          puts "=" * 50
          puts

          if embedder.cached?
            puts "Status: ✓ Model cached"
            puts "Model: sentence-transformers/all-MiniLM-L6-v2"
            puts "Dimensions: #{embedder.dimensions}"
            puts "Cache: #{Informers.cache_dir}"
            puts
            puts "Semantic search is available for memory defragmentation."
          else
            puts "Status: ✗ Model not cached"
            puts "Model: sentence-transformers/all-MiniLM-L6-v2"
            puts "Dimensions: #{embedder.dimensions}"
            puts
            puts "Run 'swarm memory setup' to download the model."
            puts "Or it will download automatically on first use."
          end

          exit(0)
        end

        def show_cache_path
          puts Informers.cache_dir
          exit(0)
        end

        def defrag_memory(args)
          # Expect directory path as argument
          directory = args&.first

          unless directory && !directory.empty?
            $stderr.puts "Error: Memory directory path required"
            $stderr.puts
            $stderr.puts "Usage: swarm memory defrag DIRECTORY"
            $stderr.puts
            $stderr.puts "Example:"
            $stderr.puts "  swarm memory defrag .swarm/assistant-memory"
            exit(1)
          end

          unless Dir.exist?(directory)
            $stderr.puts "Error: Directory not found: #{directory}"
            exit(1)
          end

          puts "Defragmenting memory at: #{directory}"
          puts "=" * 70
          puts

          # Create storage
          adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: directory)
          storage = SwarmMemory::Core::Storage.new(adapter: adapter)

          # Create defrag tool
          defrag = SwarmMemory::Tools::MemoryDefrag.new(storage: storage)

          # Run full analysis
          puts "Running full defrag analysis..."
          puts
          result = defrag.execute(action: "full", dry_run: false)
          puts result

          exit(0)
        end

        def show_help
          puts
          puts "Usage: swarm memory SUBCOMMAND"
          puts
          puts "Subcommands:"
          puts "  setup              Setup embeddings (download model ~90MB, one-time)"
          puts "  status             Check if embeddings are ready"
          puts "  cache-path         Show model cache path"
          puts "  defrag DIRECTORY   Defrag memory at given directory"
          puts
          puts "Examples:"
          puts "  swarm memory setup                            # Download model"
          puts "  swarm memory status                           # Check if ready"
          puts "  swarm memory cache-path                       # Show cache location"
          puts "  swarm memory defrag .swarm/assistant-memory   # Optimize memory"
          puts
        end
      end
    end
  end
end
