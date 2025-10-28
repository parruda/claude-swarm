Agents need to recognize when to transition between abstraction levels. This is a decision-making problem that requires cost estimation.

## The Switching Decision Points

**Level 1 → Level 2**: When agent has explored enough to understand the structure
- Signal: Agent can navigate the hierarchy without errors
- Decision: Continue with filesystem for simple operations

**Level 2 → Level 3**: When filesystem operations become inefficient relative to learning cost
- Signal: Agent is performing multiple filesystem operations for what could be one specialized operation
- Decision: Learn and switch to specialized tool

## The Cost Estimation Problem

Agents must estimate:
1. **Cost of continuing**: How many operations needed? How much time/tokens?
2. **Cost of switching**: How hard is the new tool to learn? How many tokens to understand it?
3. **Benefit of switching**: How much more efficient will operations be?

Without explicit support, agents may not make this calculation correctly. They might:
- Overestimate learning cost and stay with inefficient filesystem operations
- Underestimate switching cost and waste tokens learning tools they don't need

## Architecture Support Needed

The system should:
- Make specialized tools discoverable (agents need to know they exist)
- Provide clear signals about tool availability and applicability
- Help agents estimate costs (documentation, examples, performance hints)
- Support smooth transitions (tools should work alongside filesystem, not replace it)