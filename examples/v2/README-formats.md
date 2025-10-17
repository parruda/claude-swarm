# Configuration Format Comparison

This directory contains the same swarm configuration in both YAML and Ruby DSL formats, demonstrating the two ways to define swarms in SwarmSDK v2.

## Available Examples

### Simple Full-Stack Team

**YAML Version:** `simple-swarm-v2.yml`
- Declarative configuration
- Easy to read and maintain
- Perfect for static configurations

**Ruby DSL Version:** `simple-swarm-v2.rb`
- Programmatic configuration
- Supports Ruby language features
- Great for dynamic/conditional configurations

## Quick Start

Both files define the exact same swarm and can be used interchangeably:

```bash
# Using YAML
swarm run examples/v2/simple-swarm-v2.yml "Build authentication"

# Using Ruby DSL
swarm run examples/v2/simple-swarm-v2.rb "Build authentication"
```

## When to Use Each Format

### Use YAML When:
- ✅ Configuration is mostly static
- ✅ Non-programmers need to edit configuration
- ✅ You want simple, readable configuration
- ✅ You're sharing configs across different tools

### Use Ruby DSL When:
- ✅ You need dynamic configuration (env vars, conditionals)
- ✅ You want to reuse configuration via Ruby modules
- ✅ Complex logic is needed (loops, computed values)
- ✅ You prefer programmatic control

## Side-by-Side Comparison

### Swarm Definition

**YAML:**
```yaml
version: 2
swarm:
  name: "Full-Stack Development Team"
  lead: architect
```

**Ruby DSL:**
```ruby
SwarmSDK.build do
  name "Full-Stack Development Team"
  lead :architect
end
```

### Agent Definition

**YAML:**
```yaml
agents:
  architect:
    description: "Lead architect who coordinates the development team"
    model: gpt-5-mini
    provider: openai
    system_prompt: |
      You are the lead architect...
    tools: []
    delegates_to: [frontend_dev, backend_dev, qa_engineer]
    directory: .
```

**Ruby DSL:**
```ruby
agent :architect do
  description "Lead architect who coordinates the development team"
  model "gpt-5-mini"
  provider "openai"

  system_prompt <<~PROMPT
    You are the lead architect...
  PROMPT

  tools # Empty tools list
  delegates_to :frontend_dev, :backend_dev, :qa_engineer
  directory "."
end
```

## Key Differences

| Feature | YAML | Ruby DSL |
|---------|------|----------|
| **Multi-line strings** | `\|` or `>` syntax | Ruby heredocs (`<<~`) |
| **Empty lists** | `[]` | Call method with no args |
| **Symbols** | Strings | `:symbol` notation |
| **Comments** | `# comment` | `# comment` |
| **Conditionals** | ❌ Not supported | ✅ Full Ruby `if/else` |
| **Loops** | ❌ Not supported | ✅ Full Ruby iteration |
| **Variables** | ❌ Limited to anchors | ✅ Full Ruby variables |
| **Computed values** | ❌ Not supported | ✅ Any Ruby expression |

## Ruby DSL Advanced Features

The Ruby DSL supports features not available in YAML:

### Environment-Based Configuration

```ruby
SwarmSDK.build do
  name "Development Team"
  lead :architect

  agent :architect do
    # Conditional model based on environment
    if ENV['PRODUCTION'] == 'true'
      model "claude-opus-4"
    else
      model "gpt-5-mini"
    end

    # Dynamic base URL
    base_url ENV.fetch('API_PROXY_URL', 'http://localhost:8080/v1')
  end
end
```

### Reusable Configuration

```ruby
# Common prompt shared across agents
COMMON_EFFICIENCY_PROMPT = <<~PROMPT
  For maximum efficiency, whenever you need to perform multiple
  independent operations, invoke all relevant tools simultaneously
  rather than sequentially.
PROMPT

SwarmSDK.build do
  name "Team"
  lead :dev

  agent :dev do
    system_prompt "You are a developer.\n#{COMMON_EFFICIENCY_PROMPT}"
  end

  agent :qa do
    system_prompt "You are QA.\n#{COMMON_EFFICIENCY_PROMPT}"
  end
end
```

### Dynamic Agent Generation

```ruby
SwarmSDK.build do
  name "Multi-Service Team"
  lead :coordinator

  # Generate agents dynamically
  services = ['auth', 'payments', 'notifications']

  services.each do |service|
    agent service.to_sym do
      description "#{service.capitalize} service developer"
      model "gpt-5-mini"
      system_prompt "You develop the #{service} microservice"
    end
  end

  agent :coordinator do
    description "Service coordinator"
    # Dynamically build delegation list
    delegates_to *services.map(&:to_sym)
  end
end
```

## Migration from YAML to Ruby DSL

To convert a YAML configuration to Ruby DSL:

1. Replace `version: 2` and `swarm:` with `SwarmSDK.build do`
2. Convert `name:` to `name` method call
3. Convert `lead:` to `lead` method call
4. Replace `agents:` section with individual `agent` blocks
5. Convert field names from `key: value` to method calls: `key "value"`
6. Replace `|` multi-line strings with Ruby heredocs `<<~PROMPT`
7. Add `end` to close the `do` block

## Advanced Ruby DSL Patterns

The Ruby DSL enables sophisticated patterns not possible with YAML:

### Using Modules for Shared Configuration

```ruby
# Define reusable configuration modules
module TeamPrompts
  EFFICIENCY = <<~PROMPT
    For maximum efficiency, whenever you need to perform multiple
    independent operations, invoke all relevant tools simultaneously
    rather than sequentially.
  PROMPT

  QUALITY = <<~PROMPT
    Always write clean, well-documented code following best practices.
  PROMPT
end

SwarmSDK.build do
  name "Team"
  lead :dev

  agent :dev do
    system_prompt [
      "You are a developer.",
      TeamPrompts::EFFICIENCY,
      TeamPrompts::QUALITY,
    ].join("\n\n")
  end
end
```

### Conditional Agent Creation Based on ENV

```ruby
SwarmSDK.build do
  name "Development Team"

  # Choose lead based on environment
  lead ENV['LEAD_AGENT']&.to_sym || :architect

  agent :architect do
    # Use faster model in development
    if ENV['RAILS_ENV'] == 'development'
      model "gpt-5-mini"
    else
      model "gpt-4"
    end

    description "Lead architect"
    delegates_to :frontend, :backend
  end

  # Only create QA agent in production
  if ENV['RAILS_ENV'] == 'production'
    agent :qa do
      model "claude-opus-4"
      description "QA specialist for production"
      tools :Bash, :Read
    end
  end
end
```

### Dynamic Tool List Generation

```ruby
SwarmSDK.build do
  name "Dynamic Team"
  lead :dev

  agent :dev do
    description "Developer with dynamic tools"

    # Build tool list based on permissions
    allowed_tools = [:Read, :Grep, :Glob]

    # Add write tools only if not in read-only mode
    unless ENV['READ_ONLY'] == 'true'
      allowed_tools += [:Write, :Edit]
    end

    # Add bash only for admins
    allowed_tools << :Bash if ENV['ADMIN'] == 'true'

    # Apply tools
    tools *allowed_tools
  end
end
```

### Computed Prompt Templates

```ruby
def build_prompt(role:, tech_stack:, rules:)
  <<~PROMPT
    You are a #{role} working with #{tech_stack.join(", ")}.

    Follow these rules:
    #{rules.map { |r| "- #{r}" }.join("\n")}

    Work efficiently and communicate clearly.
  PROMPT
end

SwarmSDK.build do
  name "Full-Stack Team"
  lead :frontend

  agent :frontend do
    system_prompt build_prompt(
      role: "frontend developer",
      tech_stack: ["React", "TypeScript", "Tailwind CSS"],
      rules: [
        "Use functional components",
        "Write comprehensive tests",
        "Follow accessibility guidelines",
      ],
    )
  end

  agent :backend do
    system_prompt build_prompt(
      role: "backend developer",
      tech_stack: ["Ruby on Rails", "PostgreSQL", "Redis"],
      rules: [
        "Follow RESTful conventions",
        "Implement proper error handling",
        "Write database migrations",
      ],
    )
  end
end
```

### Dynamic Agent Generation from Configuration

```ruby
# External configuration (could be from a file, database, etc.)
SERVICES = {
  auth: { model: "gpt-4", tools: [:Bash, :Read] },
  payments: { model: "claude-sonnet-4-5", tools: [:Bash, :Read, :Write] },
  notifications: { model: "gpt-5-mini", tools: [:Read] },
}.freeze

SwarmSDK.build do
  name "Microservices Team"
  lead :coordinator

  # Generate agents dynamically from configuration
  SERVICES.each do |service_name, config|
    agent service_name do
      description "#{service_name.to_s.capitalize} service developer"
      model config[:model]
      system_prompt "You develop and maintain the #{service_name} microservice."
      tools *config[:tools]
    end
  end

  agent :coordinator do
    description "Service coordinator"
    # Dynamically build delegation list
    delegates_to *SERVICES.keys
  end
end
```

### Configuration from External Files

```ruby
require 'yaml'

# Load configuration from external file
team_config = YAML.load_file('team_config.yml')

SwarmSDK.build do
  name team_config['swarm']['name']
  lead team_config['swarm']['lead'].to_sym

  team_config['agents'].each do |agent_name, agent_config|
    agent agent_name.to_sym do
      description agent_config['description']
      model agent_config['model']
      system_prompt agent_config['system_prompt']

      # Convert tool names from strings to symbols
      tools *agent_config['tools'].map(&:to_sym) if agent_config['tools']

      # Convert delegate names from strings to symbols
      if agent_config['delegates_to']
        delegates_to *agent_config['delegates_to'].map(&:to_sym)
      end
    end
  end
end
```

## Best Practices

### For YAML Configurations

✅ **DO:**
- Use for simple, static configurations
- Keep it readable and well-commented
- Use YAML anchors for common values
- Validate with `swarm run config.yml -p "test"`

❌ **DON'T:**
- Try to add logic or conditionals
- Create overly nested structures
- Use for dynamic, environment-dependent configs
- Duplicate large blocks of text

### For Ruby DSL Configurations

✅ **DO:**
- Use for dynamic, environment-dependent configs
- Extract reusable components into modules
- Validate inputs and provide defaults
- Keep logic simple and readable
- Document complex computations

❌ **DON'T:**
- Overcomplicate with unnecessary abstractions
- Hide configuration behind too much indirection
- Forget that it executes as Ruby code
- Mix business logic with configuration
- Make configurations harder to understand than YAML

## Documentation

For more information:
- [Ruby DSL CLI Guide](../../docs/v2/user-guide/ruby-dsl-cli.md) - Using Ruby DSL with SwarmCLI
- [YAML vs Ruby DSL](../../docs/v2/guides/yaml-vs-ruby-dsl.md) - Complete comparison guide
- [Ruby DSL Guide](../../docs/v2/user-guide/ruby-dsl/README.md)
- [YAML Configuration Reference](../../docs/v2/user-guide/configuration/yaml-reference.md)
- [CLI Reference](../../docs/v2/user-guide/cli-reference.md)

## Testing Both Formats

You can verify both formats produce the same swarm:

```bash
# Test YAML version
swarm run examples/v2/simple-swarm-v2.yml -p "What can you do?"

# Test Ruby DSL version
swarm run examples/v2/simple-swarm-v2.rb -p "What can you do?"
```

Both should produce identical behavior!
