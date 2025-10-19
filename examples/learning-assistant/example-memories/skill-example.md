---
type: skill
domain: swarm/memory
difficulty: beginner
confidence: high
last_verified: 2025-01-15
prerequisites: []
tags: [swarm, scratchpad, memory, learning]
related:
  - memory://memory/concepts/swarm/scratchpad-system.md
  - memory://memory/skills/swarm/scratchpad-read.md
source: experimentation
---

# Writing to Memory Memory

## What This Does

Stores knowledge in the Memory memory system for later retrieval. This is how you persist everything you learn.

## When to Use

- **Immediately** after learning something new
- When user provides information
- After solving a problem
- When discovering how something works
- After experimenting with tools

## Steps

1. **Determine the category**: concept/fact/skill/experience
2. **Choose the path**: Follow memory hierarchy conventions
3. **Prepare content**: YAML frontmatter + markdown body
4. **Write**: Use MemoryWrite tool
5. **Verify**: Optionally read back to confirm

## Tool Signature

```
MemoryWrite(
  file_path: "memory/{category}/{domain}/{name}.md",
  content: "{yaml-frontmatter}\n\n{markdown-content}",
  title: "{Brief descriptive title}"
)
```

## Example: Storing a Concept

```
MemoryWrite(
  file_path: "memory/concepts/programming/ruby/classes.md",
  content: "---
type: concept
domain: programming/ruby
confidence: high
last_verified: 2025-01-15
tags: [ruby, classes, oop]
related: []
source: documentation
---

# Ruby Classes

Classes are blueprints for objects...
",
  title: "Ruby Classes Concept"
)
```

## Example: Storing a Fact

```
MemoryWrite(
  file_path: "memory/facts/people/paulo.md",
  content: "---
type: fact
domain: people
confidence: high
last_verified: 2025-01-15
tags: [user, preferences]
source: user
---

# User: Paulo

## Role
Primary user and project owner

## Preferences
- Direct communication
- Clean code
",
  title: "User Paulo Profile"
)
```

## Common Patterns

### Learning from User
```
User tells you something
→ Categorize it (usually 'fact')
→ Choose domain (people/environment/technical)
→ Write immediately
→ Mark source: user, confidence: high
```

### Learning from Experimentation
```
You discover how a tool works
→ Category: skill or concept
→ Domain: the tool's domain
→ Write with examples
→ Mark source: experimentation
→ Mark confidence: medium (until verified multiple times)
```

### Learning from Documentation
```
You fetch documentation with WebFetch
→ Extract key information
→ Write as concept or fact
→ Mark source: documentation, confidence: high
→ Include cross-references
```

## Best Practices

1. **Write immediately** - Don't wait until end of task
2. **Complete frontmatter** - All fields matter
3. **Descriptive titles** - Make entries discoverable
4. **Rich content** - Include examples, context, relationships
5. **Update index** - After 5-10 new writes
6. **Verify paths** - Use kebab-case, lowercase, specific domains

## Common Mistakes to Avoid

❌ **Vague paths**: `memory/ruby.md` (too general)
✅ **Specific paths**: `memory/concepts/programming/ruby/classes.md`

❌ **Missing frontmatter**: Just markdown content
✅ **Complete frontmatter**: All metadata fields

❌ **Batching**: Learning 10 things, writing at end
✅ **Immediate**: Learn one thing, write immediately

❌ **Generic titles**: "Information about Ruby"
✅ **Specific titles**: "Ruby Classes Concept"

## Troubleshooting

**Problem**: Entry too large (>1MB)
- **Solution**: Break into multiple related entries

**Problem**: Don't know where to store something
- **Solution**: Think about type first (concept/fact/skill/experience), then domain

**Problem**: Duplicate knowledge exists
- **Solution**: Search first with Glob/Grep, then decide to update or create new

## Success Indicators

You're doing it right when:
- ✅ You can answer questions from memory without re-learning
- ✅ Your memory/index.md accurately reflects what you know
- ✅ You find relevant entries quickly with Glob/Grep
- ✅ Knowledge builds on previous knowledge (cross-references work)
- ✅ You become faster at familiar tasks over time
