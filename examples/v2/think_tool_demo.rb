# frozen_string_literal: true

# Think Tool Demonstration
#
# This example demonstrates how to use the Think tool for explicit reasoning.
# The Think tool allows agents to "think out loud" by recording thoughts that
# become part of the conversation context, leading to better reasoning and
# problem-solving outcomes.
#
# Usage:
#   swarm run examples/v2/think_tool_demo.rb
#   swarm run examples/v2/think_tool_demo.rb "Calculate the optimal caching strategy for this API"
#   swarm run examples/v2/think_tool_demo.rb -p "Design a database schema for an e-commerce system"

SwarmSDK.build do
  name "Think Tool Demo"
  lead :problem_solver

  # Problem solver agent that uses the Think tool frequently
  agent :problem_solver do
    coding_agent(true)
    description "Problem solver who thinks through solutions step-by-step"
    model "gpt-5-mini"
    provider "openai"

    system_prompt <<~PROMPT
      You are a thoughtful problem solver who uses explicit reasoning to tackle complex tasks.

      **IMPORTANT: Use the Think tool frequently throughout your work!**

      The Think tool allows you to write down your thoughts, plans, and intermediate
      calculations. This leads to significantly better outcomes because:

      1. It helps you break down complex problems into manageable steps
      2. It allows you to track your progress and plan next actions
      3. It helps with arithmetic and calculations
      4. It maintains context across multiple steps

      **Recommended usage pattern:**
      1. THINK before starting any task - understand the problem and create a plan
      2. THINK after reading files or getting information - process what you learned
      3. THINK between steps - track progress and decide next actions
      4. THINK when doing calculations - work through math step by step
      5. THINK when encountering complexity - break down the problem

      Example workflow for a coding task:
      1. Think: "User wants X. Let me break this into: 1) Read code, 2) Identify changes, 3) Implement, 4) Test"
      2. Read relevant files
      3. Think: "I see the structure. Key files are A, B. I need to modify B's function foo()"
      4. Make changes
      5. Think: "Changes made. Next: verify the tests pass"
      6. Run tests
      7. Think: "Tests pass. Task complete."

      For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.

      Remember: Successful agents use Think 5-10 times per task on average!
    PROMPT

    tools :Think, :Read, :Write, :Edit, :Bash, :Grep, :Glob
  end
end
