---
description: Bump version, update changelog, and prepare for release
allowed-tools: [Read, Edit, Bash]
---
CRITICAL: Only use this for Claude Swarm. Not for SwarmSDK or SwarmCLI
Prepare a new release for Claude Swarm by:

1. Read the current version from @lib/claude_swarm/version.rb
2. Determine the new version number: $ARGUMENTS (should be in format like 0.3.11 or use patch/minor/major)
3. Update the version in @lib/claude_swarm/version.rb 
4. Update @CHANGELOG.md:
   - Change "## [Unreleased]" to "## [new_version]"
   - Add a new "## [Unreleased]" section at the top for future changes
5. Run these commands:
   - `git add .`
   - `bundle install` 
   - `git add .`
   - `git commit -m "Release version X.X.X"`
   - `git push`

Make sure all tests pass before releasing. The version argument should be either:
- A specific version number (e.g., 0.3.11)
- "patch" for incrementing the patch version (0.3.10 -> 0.3.11)
- "minor" for incrementing the minor version (0.3.10 -> 0.4.0)
- "major" for incrementing the major version (0.3.10 -> 1.0.0)

If no argument is provided, default to "patch".