# SwarmSDK & SwarmCLI Documentation

**Version 2.0** | **Last Updated**: January 2025

Welcome to the official documentation for SwarmSDK and SwarmCLI - a Ruby framework for orchestrating multiple AI agents as a collaborative team.

---

## 📚 Getting Started

**New to SwarmSDK?** Start here:

### For SDK Users
- **[Getting Started with SwarmSDK](guides/getting-started.md)** ⭐ START HERE
  Learn the basics: installation, core concepts, your first swarm (YAML & Ruby DSL)

### For CLI Users
- **[Getting Started with SwarmCLI](guides/quick-start-cli.md)** ⭐ START HERE
  Command-line interface: interactive REPL and automation modes

---

## 📖 Comprehensive Tutorial

**Ready to master SwarmSDK?** This tutorial covers 100% of features:

- **[SwarmSDK Complete Tutorial](guides/complete-tutorial.md)**
  In-depth guide covering every single feature with progressive complexity:
  - Part 1: Fundamentals (agents, models, tools)
  - Part 2: Tools & Permissions (all 11 tools, path/command permissions)
  - Part 3: Agent Collaboration (delegation patterns, markdown agents)
  - Part 4: Hooks System (all 12 events, 6 actions)
  - Part 5: Node Workflows (multi-stage pipelines, transformers)
  - Part 6: Advanced Configuration (MCP, providers, context management)
  - Part 7: Production Features (logging, cost tracking, error handling)
  - Part 8: Best Practices (architecture, testing, optimization)

---

## 📚 Reference Documentation

**Quick lookups and complete API reference:**

### Command-Line Interface
- **[CLI Reference](reference/cli.md)**
  Complete reference for all swarm commands: `run`, `migrate`, `mcp serve`, `mcp tools`

### Ruby DSL API
- **[Ruby DSL Reference](reference/ruby-dsl.md)**
  Complete programmatic API: `SwarmSDK.build`, agent DSL, permissions DSL, node DSL, hooks

### YAML Configuration
- **[YAML Configuration Reference](reference/yaml.md)**
  Complete YAML structure: agents, tools, permissions, hooks, MCP servers

---

## 🛠️ Integration Guides

### Rails Integration
- **[Rails Integration Guide](guides/rails-integration.md)**
  Comprehensive guide for integrating SwarmSDK into Ruby on Rails applications:
  - Background jobs (ActiveJob, Sidekiq)
  - Controller actions (synchronous endpoints)
  - Model enhancements (AI validations, auto-generation)
  - Rake tasks (batch processing, automation)
  - Action Cable (real-time streaming)
  - Testing strategies (RSpec, VCR, mocking)
  - Security considerations
  - Deployment (Docker, monitoring, health checks)

---

## 🎯 Documentation by Feature

### Core Features
- **Agents**: [Getting Started](guides/getting-started.md#core-concepts) | [Tutorial Part 1](guides/complete-tutorial.md#part-1-fundamentals)
- **Tools**: [Tutorial Part 2](guides/complete-tutorial.md#part-2-tools-and-permissions)
- **Delegation**: [Tutorial Part 3](guides/complete-tutorial.md#part-3-agent-collaboration)
- **Hooks**: [Tutorial Part 4](guides/complete-tutorial.md#part-4-hooks-system)
- **Node Workflows**: [Tutorial Part 5](guides/complete-tutorial.md#part-5-node-workflows)

### Configuration
- **YAML**: [Getting Started](guides/getting-started.md#configuration-formats) | [YAML Reference](reference/yaml.md)
- **Ruby DSL**: [Getting Started](guides/getting-started.md#configuration-formats) | [Ruby DSL Reference](reference/ruby-dsl.md)
- **Permissions**: [Tutorial Part 2](guides/complete-tutorial.md#permissions-system) | [YAML Reference](reference/yaml.md#permissions-configuration)

### Advanced Features
- **MCP Servers**: [Tutorial Part 6](guides/complete-tutorial.md#mcp-server-integration)
- **Custom Providers**: [Tutorial Part 6](guides/complete-tutorial.md#custom-providers-and-models)
- **Context Management**: [Tutorial Part 6](guides/complete-tutorial.md#context-window-management)
- **Rate Limiting**: [Tutorial Part 6](guides/complete-tutorial.md#rate-limiting)

### Production
- **Logging**: [Tutorial Part 7](guides/complete-tutorial.md#structured-logging)
- **Error Handling**: [Tutorial Part 7](guides/complete-tutorial.md#error-handling-and-recovery)
- **Testing**: [Tutorial Part 8](guides/complete-tutorial.md#testing-strategies) | [Rails Guide](guides/rails-integration.md#testing-strategies)
- **Best Practices**: [Tutorial Part 8](guides/complete-tutorial.md#best-practices)

---

## 🚀 Quick Links by Role

### I want to...

**Learn SwarmSDK from scratch**
→ [Getting Started with SwarmSDK](guides/getting-started.md)

**Use the command-line interface**
→ [Getting Started with SwarmCLI](guides/quick-start-cli.md)

**Master all SwarmSDK features**
→ [Complete Tutorial](guides/complete-tutorial.md)

**Integrate with Rails**
→ [Rails Integration Guide](guides/rails-integration.md)

**Look up a specific CLI command**
→ [CLI Reference](reference/cli.md)

**Look up a Ruby DSL method**
→ [Ruby DSL Reference](reference/ruby-dsl.md)

**Look up a YAML configuration option**
→ [YAML Reference](reference/yaml.md)

---

## 📊 Documentation Structure

```
docs/v2/
├── README.md                           # This file - documentation index
│
├── guides/                             # User-facing guides
│   ├── getting-started.md             # SDK quick start (YAML + Ruby DSL)
│   ├── quick-start-cli.md             # CLI quick start
│   ├── complete-tutorial.md           # 100% feature coverage tutorial
│   └── rails-integration.md           # Rails integration guide
│
└── reference/                          # Complete API references
    ├── cli.md                          # CLI command reference
    ├── ruby-dsl.md                     # Ruby DSL API reference
    └── yaml.md                         # YAML configuration reference
```

---

## 🎓 Learning Paths

### Path 1: Beginner → Intermediate
1. [Getting Started with SwarmSDK](guides/getting-started.md) - Core concepts and first swarm
2. [Getting Started with SwarmCLI](guides/quick-start-cli.md) - Command-line usage
3. [Complete Tutorial Parts 1-3](guides/complete-tutorial.md) - Fundamentals, tools, delegation

### Path 2: Intermediate → Advanced
1. [Complete Tutorial Parts 4-6](guides/complete-tutorial.md) - Hooks, workflows, advanced config
2. [Rails Integration](guides/rails-integration.md) - Production integration patterns
3. [Complete Tutorial Parts 7-8](guides/complete-tutorial.md) - Production features and best practices

### Path 3: Reference & API
1. [Ruby DSL Reference](reference/ruby-dsl.md) - Complete programmatic API
2. [YAML Reference](reference/yaml.md) - Complete configuration format
3. [CLI Reference](reference/cli.md) - All command-line options

---

## 💡 Key Concepts

### SwarmSDK
A Ruby framework for orchestrating multiple AI agents that work together as a team. Each agent has:
- **Role**: Specialized expertise (backend developer, code reviewer, etc.)
- **Tools**: Capabilities (Read files, Write files, Run bash commands, etc.)
- **Delegation**: Ability to delegate subtasks to other agents
- **Hooks**: Custom logic that runs at key points in execution

### SwarmCLI
A command-line interface for running SwarmSDK swarms with two modes:
- **Interactive (REPL)**: Conversational interface for exploration and iteration
- **Non-Interactive**: One-shot execution perfect for automation and scripting

### Configuration Formats
- **YAML**: Declarative, easy to read, great for shell-based hooks
- **Ruby DSL**: Programmatic, dynamic, full Ruby power, IDE support

---

## 🔍 Search by Topic

| Topic | Guide | Reference |
|-------|-------|-----------|
| **Installation** | [SDK Guide](guides/getting-started.md#installation) | - |
| **First Swarm** | [SDK Guide](guides/getting-started.md#your-first-swarm) | - |
| **CLI Commands** | [CLI Guide](guides/quick-start-cli.md#commands-overview) | [CLI Ref](reference/cli.md) |
| **REPL Mode** | [CLI Guide](guides/quick-start-cli.md#interactive-mode-repl) | [CLI Ref](reference/cli.md#interactive-mode) |
| **Tools** | [Tutorial Part 2](guides/complete-tutorial.md#part-2-tools-and-permissions) | [YAML Ref](reference/yaml.md#tools) |
| **Permissions** | [Tutorial Part 2](guides/complete-tutorial.md#permissions-system) | [YAML Ref](reference/yaml.md#permissions-configuration) |
| **Delegation** | [Tutorial Part 3](guides/complete-tutorial.md#part-3-agent-collaboration) | [Ruby DSL Ref](reference/ruby-dsl.md#delegates_to) |
| **Hooks** | [Tutorial Part 4](guides/complete-tutorial.md#part-4-hooks-system) | [YAML Ref](reference/yaml.md#hooks-configuration) |
| **Workflows** | [Tutorial Part 5](guides/complete-tutorial.md#part-5-node-workflows) | [Ruby DSL Ref](reference/ruby-dsl.md#node-builder-dsl) |
| **MCP Servers** | [Tutorial Part 6](guides/complete-tutorial.md#mcp-server-integration) | [YAML Ref](reference/yaml.md#mcp_servers) |
| **Rails** | [Rails Guide](guides/rails-integration.md) | - |
| **Testing** | [Tutorial Part 8](guides/complete-tutorial.md#testing-strategies) | - |

---

## 📝 Documentation Standards

All documentation in this directory follows these principles:

✅ **100% Accurate** - All information verified against source code
✅ **Comprehensive** - Every feature documented
✅ **Progressive** - Simple → Intermediate → Advanced
✅ **Practical** - Real-world examples throughout
✅ **Both Formats** - YAML and Ruby DSL for everything
✅ **User-Focused** - Written for developers using SwarmSDK, not implementers

---

## 🤝 Contributing

Found an issue or want to improve the documentation?

1. Check existing documentation is accurate and up-to-date
2. Follow the established structure and style
3. Include both YAML and Ruby DSL examples where applicable
4. Test all code examples before submitting
5. Keep explanations clear and concise

---

## 📄 Version History

### v2.0 (January 2025)
- Complete documentation rewrite
- Consolidated from 261 files to 7 focused documents
- 100% feature coverage
- Added Rails integration guide
- Added comprehensive tutorial
- Complete CLI, Ruby DSL, and YAML references

---

## 📚 Additional Resources

- **GitHub Repository**: [parruda/claude-swarm](https://github.com/parruda/claude-swarm)
- **RubyGems**: [swarm_sdk](https://rubygems.org/gems/swarm_sdk) | [swarm_cli](https://rubygems.org/gems/swarm_cli)
- **Issues & Support**: [GitHub Issues](https://github.com/parruda/claude-swarm/issues)

---

**Ready to get started?** → [Getting Started with SwarmSDK](guides/getting-started.md) or [Getting Started with SwarmCLI](guides/quick-start-cli.md)
