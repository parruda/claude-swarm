Effective tool design for LLM agents follows principles that maximize agent capability while minimizing cognitive load and errors.

## Principle 1: Leverage Existing Knowledge

LLM agents have extensive training on common tools and patterns. Designing tools that align with this existing knowledge means agents can use them effectively without special instruction. Filesystem operations, HTTP requests, and SQL queries are all well-understood patterns.

## Principle 2: Unified Interfaces Over Specialized APIs

Rather than creating custom APIs for each data source, unifying access through a common interface (like a filesystem) allows agents to apply the same reasoning and tools across different domains. This reduces the number of distinct tool patterns an agent must master. The filesystem abstraction pattern is a powerful implementation of this principle, exposing any data source through familiar filesystem operations.

## Principle 3: Composability

Tools should work together naturally. An agent should be able to chain operations: list files, filter results, read specific entries, and combine information. This requires tools that accept outputs from other tools as inputs.

## Principle 4: Transparency and Predictability

Agents perform better when tool behavior is predictable and transparent. Filesystem operations have well-defined semantics—agents know what `ls` does, what errors mean, and how to handle them. Custom tools with surprising behavior create confusion.

## Principle 5: Appropriate Abstraction Level

The abstraction should hide unnecessary complexity while exposing necessary details. A filesystem abstraction hides database query syntax but exposes the logical structure of data through paths.

## Principle 6: Error Semantics

Errors should map to familiar concepts. "File not found" is immediately understood. Custom error codes require explanation and increase agent confusion.