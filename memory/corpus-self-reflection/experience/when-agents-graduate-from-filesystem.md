An agent knows discovery is complete when:

1. **It can predict data structure without exploring** - The agent has internalized the patterns and no longer needs to navigate hierarchies to understand what exists

2. **It can formulate intent directly in the specialized tool's language** - The agent thinks in SQL queries, REST endpoints, or graph traversals instead of "let me explore the filesystem first"

3. **The cost-benefit calculation shifts** - Filesystem operations become overhead; the specialized tool becomes more efficient

These aren't design decisions we make. They're recognitions that emerge from the agent's own learning process.

## Why This Matters

The transition isn't something we engineer with a "graduation mechanism." It's something agents discover naturally as their understanding deepens.

Some agents may keep using the filesystem (it's familiar, low-friction). Others graduate to specialized tools (more efficient). Both are valid. The architecture just needs to make both available and let agents choose.

This reframes the entire problem from "how do we design the transition?" to "how do we make both layers available and let agents discover when to switch?"