# frozen_string_literal: true

module SwarmMemory
  module CLI
    # CLI commands for managing SwarmMemory embeddings
    #
    # Registers with SwarmCLI to provide:
    #   swarm memory setup      - Download embedding model
    #   swarm memory status     - Check model cache status
    #   swarm memory model-path - Show cache location
    #   swarm memory defrag     - Optimize memory storage
    #   swarm memory rebuild    - Rebuild all embeddings
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
          when "model-path"
            show_model_path
          when "defrag"
            defrag_memory(subcommand_args)
          when "rebuild"
            rebuild_embeddings(subcommand_args)
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

          model_name = ENV["SWARM_MEMORY_EMBEDDING_MODEL"] || "sentence-transformers/multi-qa-MiniLM-L6-cos-v1"

          if embedder.cached?
            puts "✓ Model already cached!"
            puts "  Model: #{model_name}"
            puts "  Location: #{Informers.cache_dir}/#{model_name}/"
            puts
            puts "No download needed. Embeddings ready to use."
          else
            puts "Model not cached. Downloading..."
            puts "  Model: #{model_name}"
            puts "  Size: ~90MB (unquantized ONNX)"
            puts "  Location: #{Informers.cache_dir}"
            puts
            puts "This is a one-time download. Please wait..."
            puts

            embedder.preload!

            puts
            puts "✓ Setup complete!"
            puts "  Model: #{model_name}"
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

          model_name = ENV["SWARM_MEMORY_EMBEDDING_MODEL"] || "sentence-transformers/multi-qa-MiniLM-L6-cos-v1"

          puts "SwarmMemory Embedding Status"
          puts "=" * 50
          puts

          if embedder.cached?
            puts "Status: ✓ Model cached"
            puts "Model: #{model_name}"
            puts "Dimensions: #{embedder.dimensions}"
            puts "Cache: #{Informers.cache_dir}"
            puts
            puts "Semantic search is available for memory defragmentation."
          else
            puts "Status: ✗ Model not cached"
            puts "Model: #{model_name}"
            puts "Dimensions: #{embedder.dimensions}"
            puts
            puts "Run 'swarm memory setup' to download the model."
            puts "Or it will download automatically on first use."
          end

          exit(0)
        end

        def show_model_path
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

        def rebuild_embeddings(args)
          # Expect directory path as argument
          directory = args&.first

          unless directory && !directory.empty?
            $stderr.puts "Error: Memory directory path required"
            $stderr.puts
            $stderr.puts "Usage: swarm memory rebuild DIRECTORY"
            $stderr.puts
            $stderr.puts "Example:"
            $stderr.puts "  swarm memory rebuild .swarm/assistant-memory"
            exit(1)
          end

          unless Dir.exist?(directory)
            $stderr.puts "Error: Directory not found: #{directory}"
            exit(1)
          end

          puts "Rebuilding embeddings for memory at: #{directory}"
          puts "=" * 70
          puts

          # Initialize embedder
          begin
            embedder = SwarmMemory::Embeddings::InformersEmbedder.new
          rescue StandardError => e
            $stderr.puts "Error: #{e.message}"
            $stderr.puts
            $stderr.puts "Make sure the 'informers' gem is installed:"
            $stderr.puts "  gem install informers"
            exit(1)
          end

          # Ensure model is cached
          unless embedder.cached?
            puts "Model not cached. Downloading..."
            puts "  Model: sentence-transformers/all-MiniLM-L6-v2"
            puts "  Size: ~90MB (unquantized ONNX)"
            puts
            embedder.preload!
            puts
          end

          # Create storage with embedder
          adapter = SwarmMemory::Adapters::FilesystemAdapter.new(directory: directory)
          storage = SwarmMemory::Core::Storage.new(adapter: adapter, embedder: embedder)

          # Get all entries
          all_entries = adapter.all_entries
          total_count = all_entries.size

          if total_count.zero?
            puts "No entries found in #{directory}"
            exit(0)
          end

          puts "Found #{total_count} entries to rebuild"
          puts

          # Rebuild each entry
          processed = 0
          errors = 0

          all_entries.each do |path, entry|
            # Re-write the entry to regenerate embedding
            # The storage.write() method will automatically generate the embedding
            storage.write(
              file_path: path,
              content: entry.content,
              title: entry.title,
              metadata: entry.metadata,
              generate_embedding: true,
            )

            processed += 1
            print("\rProcessed: #{processed}/#{total_count} (#{errors} errors)")
          rescue StandardError => e
            errors += 1
            print("\rProcessed: #{processed}/#{total_count} (#{errors} errors)")
            warn("\nError rebuilding #{path}: #{e.message}")
          end

          puts
          puts
          puts "Rebuild complete!"
          puts "  Total entries: #{total_count}"
          puts "  Successfully rebuilt: #{processed}"
          puts "  Errors: #{errors}" if errors.positive?
          puts

          exit(0)
        end

        def show_help
          puts
          puts "Usage: swarm memory SUBCOMMAND"
          puts
          puts "Subcommands:"
          puts "  setup              Setup embeddings (download model ~90MB, one-time)"
          puts "  status             Check if embeddings are ready"
          puts "  model-path         Show embedding model cache path"
          puts "  defrag DIRECTORY   Defrag memory at given directory"
          puts "  rebuild DIRECTORY  Rebuild all embeddings for memory at directory"
          puts
          puts "Environment Variables:"
          puts "  SWARM_MEMORY_EMBEDDING_MODEL              Model to use (default: all-MiniLM-L6-v2)"
          puts "                                            Options: all-MiniLM-L6-v2, multi-qa-MiniLM-L6-cos-v1"
          puts "  SWARM_MEMORY_EMBEDDING_MAX_CHARS          Max chars to embed (default: 300, -1: unlimited)"
          puts
          puts "  Adaptive Thresholds (short queries use lower threshold):"
          puts "  SWARM_MEMORY_DISCOVERY_THRESHOLD          Normal query threshold (default: 0.35)"
          puts "  SWARM_MEMORY_DISCOVERY_THRESHOLD_SHORT    Short query threshold (default: 0.25)"
          puts "  SWARM_MEMORY_ADAPTIVE_WORD_CUTOFF         Word count cutoff (default: 10)"
          puts "                                            Queries < 10 words use short threshold"
          puts
          puts "  SWARM_MEMORY_SEMANTIC_WEIGHT              Semantic weight (default: 0.5)"
          puts "  SWARM_MEMORY_KEYWORD_WEIGHT               Keyword weight (default: 0.5)"
          puts
          puts "Examples:"
          puts "  swarm memory setup                            # Download model"
          puts "  swarm memory status                           # Check if ready"
          puts "  swarm memory model-path                       # Show model location"
          puts "  swarm memory defrag .swarm/assistant-memory   # Optimize memory"
          puts "  swarm memory rebuild .swarm/assistant-memory  # Rebuild embeddings"
          puts
          puts "  # Use Q&A-optimized model"
          puts "  SWARM_MEMORY_EMBEDDING_MODEL=sentence-transformers/multi-qa-MiniLM-L6-cos-v1 \\"
          puts "    swarm memory setup"
          puts
          puts "  # Rebuild with more content (850 chars)"
          puts "  SWARM_MEMORY_EMBEDDING_MAX_CHARS=850 \\"
          puts "    swarm memory rebuild .swarm/assistant-memory"
          puts
        end
      end
    end
  end
end
