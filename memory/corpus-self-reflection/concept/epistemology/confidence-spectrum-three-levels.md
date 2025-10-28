LLM agents operate on a **confidence spectrum** with three distinct levels that must be navigated simultaneously:

## Level 1: Factual Confidence
- **High**: Deterministic, verifiable facts (e.g., "Python's `len()` returns an integer")
- **Medium**: Pattern-based generalizations (e.g., "Most Python developers prefer list comprehensions")
- **Low**: Context-dependent judgments (e.g., "The best way to structure your project")

## Level 2: Reasoning Confidence
- **High**: Following explicit rules or documented procedures
- **Medium**: Inferring from patterns and available context
- **Low**: Predicting human behavior or reasoning about novel situations

## Level 3: Scope Confidence
- **High**: Within training data and clear, well-defined domains
- **Medium**: Emerging topics or specialized areas with limited training examples
- **Low**: Real-time information, personal details, future events, or domains outside training

The key insight: these three levels operate independently. An agent might have high factual confidence but low reasoning confidence, or high scope confidence but medium factual confidence. Calibration requires assessing all three simultaneously.