# Contributing to Claude Swarm

Thank you for your interest in contributing to Claude Swarm!

## Development Setup

```bash
# Clone the repository
git clone https://github.com/parruda/claude-swarm.git
cd claude-swarm

# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Run linter
bundle exec rubocop -A
```

## Running Tests

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby test/test_swarm_sdk.rb

# Run with coverage
COVERAGE=true bundle exec rake test
```

## Code Style

We use RuboCop for code style enforcement:

```bash
# Check style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -A
```

## Documentation

Documentation is in `docs/v2/` and follows this structure:
- `guides/` - User guides and tutorials
- `api/` - API reference documentation
- `architecture/` - System architecture docs
- `examples/` - Code examples

Update documentation when adding features.

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Update documentation
6. Run tests and linter
7. Submit pull request

## Questions?

Open an issue on GitHub for questions or discussions.
