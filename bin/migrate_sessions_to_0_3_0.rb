#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"

# Migration script to update session files from old format to new format
# Changes:
# - Renames start_directory file to root_directory
# - Updates session_metadata.json to change "start_directory" to "root_directory"

class SessionMigrator
  def initialize
    @claude_swarm_home = ENV["CLAUDE_SWARM_HOME"] || File.expand_path("~/.claude-swarm")
    @sessions_dir = File.join(@claude_swarm_home, "sessions")
    @migrated_count = 0
    @error_count = 0
    @already_migrated_count = 0
  end

  def run
    puts "Claude Swarm Session Migration"
    puts "=" * 50
    puts "This script will migrate session files from the old format to the new format:"
    puts "- Rename 'start_directory' files to 'root_directory'"
    puts "- Update 'start_directory' to 'root_directory' in session_metadata.json"
    puts
    puts "Sessions directory: #{@sessions_dir}"

    unless Dir.exist?(@sessions_dir)
      puts "\nError: Sessions directory not found!"
      exit(1)
    end

    puts "\nSearching for sessions to migrate..."

    sessions = find_sessions_to_migrate

    if sessions.empty?
      puts "\nNo sessions found that need migration."
      exit(0)
    end

    puts "\nFound #{sessions.length} session(s) to migrate:"
    sessions.each { |session| puts "  - #{session}" }

    print("\nProceed with migration? (y/N): ")
    response = gets.chomp.downcase

    unless response == "y"
      puts "Migration cancelled."
      exit(0)
    end

    puts "\nMigrating sessions..."
    migrate_sessions(sessions)

    puts "\n" + "=" * 50
    puts "Migration complete!"
    puts "  Migrated: #{@migrated_count}"
    puts "  Already migrated: #{@already_migrated_count}"
    puts "  Errors: #{@error_count}"
  end

  private

  def find_sessions_to_migrate
    sessions = []

    Dir.glob(File.join(@sessions_dir, "*/*")).each do |session_dir|
      next unless File.directory?(session_dir)

      start_dir_file = File.join(session_dir, "start_directory")
      root_dir_file = File.join(session_dir, "root_directory")

      # Only include sessions that have start_directory file
      next unless File.exist?(start_dir_file)

      if File.exist?(root_dir_file)
        # Both files exist - session partially migrated or has issues
        puts "Warning: Session #{session_dir} has both start_directory and root_directory files"
      end
      sessions << session_dir
    end

    sessions
  end

  def migrate_sessions(sessions)
    sessions.each do |session_dir|
      puts "\nMigrating: #{session_dir}"
      migrate_session(session_dir)
    end
  end

  def migrate_session(session_dir)
    # Step 1: Rename start_directory file to root_directory
    start_dir_file = File.join(session_dir, "start_directory")
    root_dir_file = File.join(session_dir, "root_directory")

    if File.exist?(start_dir_file)
      if File.exist?(root_dir_file)
        puts "  ⚠️  root_directory file already exists, checking content..."
        start_content = File.read(start_dir_file).strip
        root_content = File.read(root_dir_file).strip

        if start_content == root_content
          puts "  ✓ Files have same content, removing start_directory"
          File.delete(start_dir_file)
        else
          puts "  ❌ ERROR: Files have different content!"
          puts "     start_directory: #{start_content}"
          puts "     root_directory: #{root_content}"
          @error_count += 1
          return
        end
      else
        FileUtils.mv(start_dir_file, root_dir_file)
        puts "  ✓ Renamed start_directory to root_directory"
      end
    else
      puts "  ⚠️  No start_directory file found"
    end

    # Step 2: Update session_metadata.json
    metadata_file = File.join(session_dir, "session_metadata.json")

    if File.exist?(metadata_file)
      metadata = JSON.parse(File.read(metadata_file))

      if metadata.key?("start_directory")
        # Store the value
        root_dir_value = metadata["start_directory"]

        # Check if root_directory already exists
        if metadata.key?("root_directory")
          if metadata["root_directory"] == root_dir_value # rubocop:disable Metrics/BlockNesting
            puts "  ✓ root_directory already correct in metadata"
          else
            puts "  ❌ ERROR: Conflicting values in metadata!"
            puts "     start_directory: #{metadata["start_directory"]}"
            puts "     root_directory: #{metadata["root_directory"]}"
            @error_count += 1
            return
          end
        else
          # Add root_directory
          metadata["root_directory"] = root_dir_value
        end

        # Remove start_directory
        metadata.delete("start_directory")

        # Write back the updated metadata
        File.write(metadata_file, JSON.pretty_generate(metadata))
        puts "  ✓ Updated session_metadata.json"
      elsif metadata.key?("root_directory")
        puts "  ✓ Metadata already migrated"
        @already_migrated_count += 1
        return
      else
        puts "  ⚠️  No directory field in metadata"
      end
    else
      puts "  ⚠️  No session_metadata.json found"
    end

    @migrated_count += 1
    puts "  ✅ Session migrated successfully"
  rescue StandardError => e
    puts "  ❌ ERROR: #{e.message}"
    puts "     #{e.backtrace.first}"
    @error_count += 1
  end
end

# Run the migration
if __FILE__ == $PROGRAM_NAME
  migrator = SessionMigrator.new
  migrator.run
end
