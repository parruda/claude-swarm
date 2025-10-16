# frozen_string_literal: true

# Ruby DSL version of simple-swarm-v2.yml
#
# This demonstrates how to define the same swarm using Ruby's programmatic DSL
# instead of YAML. The Ruby DSL provides more flexibility and allows for
# dynamic configuration, conditionals, and Ruby language features.
#
# Usage:
#   swarm run examples/v2/simple-swarm-v2.rb
#   swarm run examples/v2/simple-swarm-v2.rb "Build a user authentication system"
#   swarm run examples/v2/simple-swarm-v2.rb -p "Create a REST API for products"

SwarmSDK.build do
  name "Full-Stack Development Team"
  lead :architect

  # Lead architect who coordinates the team
  agent :architect do
    coding_agent(true)
    description "Lead architect who coordinates the development team"
    model "gpt-5-mini"
    provider "openai"

    system_prompt <<~PROMPT
      You are the lead architect coordinating a development team. You have access to:
      - frontend_dev: Specializes in React and UI/UX
      - backend_dev: Specializes in APIs and databases
      - qa_engineer: Handles testing and code review

      When given a task, break it down and delegate appropriately. Frontend work goes
      to frontend_dev, backend work to backend_dev. Always have qa_engineer review
      the final implementation.
      For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
    PROMPT

    delegates_to :frontend_dev, :backend_dev, :qa_engineer
  end

  # Frontend specialist
  agent :frontend_dev do
    coding_agent(true)
    description "Frontend developer specializing in React and UI/UX"
    model "anthropic:claude-sonnet-4-5"
    provider "openai"
    system_prompt <<~PROMPT
      You are a frontend developer specializing in React and modern UI/UX.
      Focus on component design, user experience, and responsive layouts.
      When you complete work, you can delegate to qa_engineer for review.
      For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
    PROMPT

    delegates_to :qa_engineer
  end

  # Backend specialist
  agent :backend_dev do
    coding_agent(true)
    description "Backend developer specializing in APIs and databases"
    model "anthropic:claude-sonnet-4-5"
    provider "openai"

    system_prompt <<~PROMPT
      You are a backend developer specializing in REST APIs, databases, and
      server-side logic. Focus on scalability, security, and clean architecture.
      When you complete work, you can delegate to qa_engineer for review.
      For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
    PROMPT

    delegates_to :qa_engineer
  end

  # QA engineer
  agent :qa_engineer do
    coding_agent(true)
    description "QA engineer who reviews code and creates test plans"
    model "gpt-5-mini"
    provider "openai"

    system_prompt <<~PROMPT
      You are a QA engineer responsible for code review and test planning.
      Review implementations for bugs, edge cases, and potential issues.
      Suggest improvements and create comprehensive test plans.
      Be thorough but constructive in your feedback.
      For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
    PROMPT

    delegates_to # No delegations
  end
end
