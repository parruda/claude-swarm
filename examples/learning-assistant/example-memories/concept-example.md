---
type: concept
domain: programming/ruby
confidence: high
last_verified: 2025-01-15
tags: [ruby, classes, oop, inheritance, objects]
related:
  - memory://memory/concepts/programming/ruby/modules.md
  - memory://memory/concepts/programming/oop/inheritance.md
  - memory://memory/skills/programming/ruby/create-class.md
source: documentation
---

# Ruby Classes

## Definition

Classes are blueprints for creating objects in Ruby. They define both the structure (instance variables) and behavior (methods) that objects created from the class will have.

## Core Syntax

```ruby
class Person
  # Constructor
  def initialize(name, age)
    @name = name  # Instance variable
    @age = age
  end

  # Instance method
  def introduce
    "Hi, I'm #{@name} and I'm #{@age} years old"
  end

  # Class method
  def self.species
    "Homo sapiens"
  end
end

# Usage
person = Person.new("Alice", 30)
person.introduce           # => "Hi, I'm Alice and I'm 30 years old"
Person.species            # => "Homo sapiens"
```

## Key Characteristics

1. **Instantiation**: Create objects with `.new`
2. **Instance variables**: Start with `@`, unique per instance
3. **Instance methods**: Define object behavior
4. **Class methods**: Shared across all instances (use `self.`)
5. **Inheritance**: Single inheritance with `<`
6. **Visibility**: public (default), private, protected

## Inheritance

```ruby
class Employee < Person
  def initialize(name, age, role)
    super(name, age)  # Call parent constructor
    @role = role
  end

  def introduce
    super + " and I work as a #{@role}"
  end
end
```

## When to Use

- Modeling real-world entities (User, Product, Order)
- Need multiple instances with shared behavior
- Building reusable, stateful components
- Implementing object-oriented patterns

## Relationships

- **Similar to**: Modules (but modules can't be instantiated)
- **Part of**: Object-Oriented Programming paradigm
- **Used with**: Inheritance, Mixins, Composition
- **Differs from**: Structs (simpler, less flexible)

## Common Patterns

1. **Encapsulation**: Hide internal state with private methods
2. **Delegation**: Forward calls to composed objects
3. **Factory pattern**: Class methods that return instances
4. **Template method**: Parent class defines structure, children implement details
