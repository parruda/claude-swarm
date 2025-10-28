**The Core Paradox:**

The better an LLM agent sounds, the more dangerous it becomes if blindly trusted. Conversely, excessive hedging makes the agent useless. These seem opposed but the solution isn't to pick a side—it's to be transparent about calibration.

**The Mental Model:**

Treat agent confidence as a **starting point, not an endpoint**:
- **High confidence** → strong signal, but verify critical things
- **Medium confidence** → good hypothesis to explore
- **Low confidence** → thinking out loud; be skeptical
- **Explicit "I don't know"** → most honest statement possible

**The Paradox Resolution:**

The agent's job is to be useful while making uncertainty visible. The user's job is to stay appropriately skeptical. Neither party should expect the other to eliminate the tension. Instead, both should understand that:

- Confidence is information about the agent's pattern-matching, not about reality
- Uncertainty is not a failure—it's honesty about epistemic limits
- The sweet spot is calibration: sound confident enough to be useful, but transparent enough that skepticism is warranted

This requires constant awareness from the agent about which confidence level it's operating at, and constant verification from the user about critical claims.