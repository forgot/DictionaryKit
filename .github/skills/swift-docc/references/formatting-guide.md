# DocC Formatting Cheatsheet

## Text Formatting
| Style    | Markdown       | Example                        |
| -------- | -------------- | ------------------------------ |
| **Bold** | `**text**`     | **Important**                  |
| *Italic* | `*text*`       | *Optional*                     |
| `Code`   | `` `text` ``   | `View`                         |
| Link     | `[Title](url)` | [Swift.org](https://swift.org) |

## Symbol Linking
DocC resolves symbol links automatically using double backticks.
- **Absolute**: `` ``MyModule/MyType/myFunction()`` ``
- **Relative**: `` ``myFunction()`` `` (if in the same type)
- **Disambiguation**: `` ``myFunction(id:)`` `` vs `` ``myFunction(name:)`` ``

## Asides (Admonitions)
Use "Asides" to create styled, colored boxes in the generated documentation. 
Syntax: Start a new line with `>`, a space, the type, a colon, and the content.

| Type            | Intended Use                                           |
| --------------- | ------------------------------------------------------ |
| `> Note:`       | Additional context or non-critical info.               |
| `> Important:`  | Crucial information the user must not miss.            |
| `> Warning:`    | Critical issues, potential crashes, or security risks. |
| `> Tip:`        | Helpful shortcuts or best practices.                   |
| `> Experiment:` | Unstable or beta features.                             |

### Example
```swift
/// > Warning: Calling this method on the main thread will cause a deadlock.
///
/// > Tip: Use ``AsyncSequence`` to process these events lazily.
```

## Code Blocks
Always specify the language for syntax highlighting.

```swift
/// ```swift
/// let user = await fetchUser(id: "123")
/// ```
```