The most effective agent architectures combine a unified abstraction (like filesystem) with specialized tools. This hybrid approach succeeds where pure approaches fail.

## Why Pure Approaches Fail

**Pure Filesystem Approach:**
- Loses expressiveness: Complex queries become inefficient or require multiple operations
- Agents struggle with operations that don't map cleanly to hierarchies
- Performance suffers on complex operations

**Pure Specialized Tools Approach:**
- Loses discoverability: Agents can't explore unknown data without documentation
- Requires agents to know which tool to use before exploring
- Doesn't scale well when adding new data sources

## Why Hybrid Approaches Win

Combining filesystem abstraction with specialized tools provides:

1. **Discoverability** - Filesystem enables exploration and discovery of data structures
2. **Expressiveness** - Specialized tools handle complex operations efficiently
3. **Cognitive Efficiency** - Both leverage existing agent knowledge (no novel abstractions)

## Proven Combinations

**Filesystem + SQL**: Agents explore with filesystem, query with SQL (both familiar concepts)

**Filesystem + REST APIs**: Agents discover with filesystem, call APIs for complex operations

**Filesystem + Graph Queries**: Agents navigate with filesystem, traverse with graph tool

Each combination works because:
- The filesystem provides a low-friction entry point
- The specialized tool handles what filesystem can't express well
- Both tools align with existing agent knowledge
- Agents choose the right tool for each task

The hybrid approach avoids the failure modes of pure approaches by letting agents use the right abstraction for each situation.