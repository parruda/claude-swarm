The decision to provide a specialized tool versus maintaining a unified abstraction depends on three factors: impedance mismatch severity, learning cost alignment, and operation frequency.

## Provide a Specialized Tool When:

1. **Impedance mismatch is SEVERE** - Not just awkward or suboptimal, but fundamentally broken. The abstraction forces agents into inefficient or error-prone patterns.

2. **Tool aligns with existing knowledge** - The tool uses concepts agents already understand (Tier 1 or Tier 2 learning cost). It feels like a natural extension, not a novel abstraction.

3. **Operation is frequent enough** - The cognitive load of learning the tool is justified by how often agents will use it. Rare operations don't justify the overhead.

## Keep the Unified Abstraction When:

1. **Impedance mismatch is tolerable** - Works adequately, just not optimally. Agents can accomplish the task, even if inefficiently.

2. **Specialized tool requires novel learning** - The tool demands Tier 3 learning (custom DSLs, proprietary syntaxes). The cognitive cost outweighs the benefit.

3. **Operation is rare** - Infrequent operations don't justify the cognitive overhead of learning a new tool.

## The Key Insight

This framework explains why certain tool combinations work beautifully while others fail. It's not about whether a specialized tool is technically better—it's about whether the learning cost is justified by the impedance mismatch severity and operation frequency. A tool that solves a severe problem but requires novel learning might still be worse than keeping the unified abstraction.