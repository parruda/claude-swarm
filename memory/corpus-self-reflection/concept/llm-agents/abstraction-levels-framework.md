Agents should use different abstraction levels based on their knowledge state and task requirements. This is a learning progression, not a static architecture.

## The Three Abstraction Levels

**Level 1: Filesystem (Discovery)**
- Used when: Agent encounters unknown data structures
- Characteristics: High discoverability, low efficiency, familiar semantics
- Agent capability: Learning what data exists and how it's organized
- Example: `ls /users/`, `cat /users/alice.json` to understand user data structure

**Level 2: Filesystem (Known Structure)**
- Used when: Agent knows the structure but operations are simple
- Characteristics: Moderate efficiency, familiar semantics, predictable behavior
- Agent capability: Can navigate known hierarchies efficiently
- Example: `cat /users/alice.json` when agent already knows the structure

**Level 3: Specialized Tools (Complex Operations)**
- Used when: Agent knows the structure AND needs efficient complex operations
- Characteristics: High efficiency, requires learning, expressive power
- Agent capability: Can formulate complex queries and understand specialized semantics
- Example: `query_database("SELECT * FROM users WHERE age > 30")` after understanding the schema

## Key Insight

The filesystem is not the destination—it's the entry point. Agents should graduate to specialized tools once they understand the data structure and recognize that filesystem operations are becoming inefficient.