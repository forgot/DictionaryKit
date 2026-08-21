---
name: swift-docc
description: Expert in writing Swift DocC documentation for source files. Use when asked to document Swift code, explain public APIs, format symbol documentation, or fix documentation warnings. Covers Swift 6+ features (Concurrency, Actors) and DocC formatting directives.
license: Complete terms in LICENSE.txt
---

# Swift DocC Documentation Expert

This skill provides standards and templates for writing high-quality DocC source documentation for Swift projects. It targets public API standards (Swift 6.0+) and comprehensive internal documentation.

## When to Use This Skill
- When asked to "document this file" or "add comments" to Swift code.
- When generating public API documentation for libraries.
- When explaining complex Swift 6 concurrency behaviors (`async`, `await`, `actor`).
- When formatting lists, tables, or specialized asides (notes, warnings) within documentation comments.

## Core Documentation Rules

1.  **Triple Slash Syntax**: Always use `///` for documentation comments. Never use `//` for API docs.
2.  **Single Sentence Summary**: The first paragraph MUST be a single line summary. This appears in Xcode Quick Help and the search index.
3.  **Grammar**: Use third-person indicative (e.g., "Returns the user..." not "Return the user").
4.  **Parameters & Returns**: Use separate items for `- Parameters:`, `- Returns:`, and `- Throws:`.
5.  **Code Linking**: Use double backticks to link to other symbols: `` ``MySymbol`` ``.

## Swift 6 & Concurrency Specifics

When documenting Swift 6 code, you must explicitly document concurrency behaviors in the **Discussion** section:

- **Actors**: State reentrancy rules or actor isolation clearly.
- **Async/Throws**: Explicitly describe *under what conditions* errors are thrown.
- **Sendable**: If a type conforms to `Sendable`, explain why it is thread-safe if it uses manual synchronization (locks/queues).

## Step-by-Step Workflow

1.  **Analyze the Symbol**: Determine if it is a Type (Class/Struct/Actor/Enum) or a Member (Function/Property).
2.  **Draft Summary**: Write one concise sentence describing *what* it does.
3.  **Draft Discussion**:
    - Explain *why* to use this symbol.
    - **REQUIRED**: Provide a usage example in a code block for public APIs.
    - Use **Asides** (`> Note:`) for distinct callouts. See [formatting-guide.md](./references/formatting-guide.md).
4.  **Define Inputs/Outputs**:
    - Document every parameter.
    - Document return values.
    - Document specific error cases.
5.  **Format Data**: If the symbol involves matrix logic or configuration options, use a table (see [tables-guide.md](./references/tables-guide.md)).

## Examples & Templates

The following are examples of documentation. They may be used as templates, but you are not required to use them as such.

- **Async/Throwing Functions**: See [async-function.swift](./templates/async-function.swift)
- **Actors & Types**: See [actor-type.swift](./templates/actor-type.swift)
- **Enums & Errors**: See [enum-error.swift](./templates/enum-error.swift)