# Adding Tables of Data

DocC supports ASCII-style tables to present structured data. This is useful for configuration options, status codes, or feature matrices.

## Rules
1. Columns are separated by pipes `|`.
2. The header row is separated from the body by hyphens `-`.
3. Alignment colons (`:`) are optional but recommended for readability.

## Basic Layout

```swift
/// | Parameter | Type | Description |
/// |:----------|:-----|:------------|
/// | `id`      | String | Unique Identifier |
/// | `count`   | Int    | Number of attempts |
```

## Grid-Based Layout (Advanced)
For more complex data, you can use grid formatting allowed by Markdown, but simple pipe tables are most compatible with Xcode's Quick Help.

## Usage in Swift
Do not indent the table syntax deeper than the `///` space.

```swift
/// Determining the output format:
///
/// | Format | Extension | Mime Type |
/// |:-------|:----------|:----------|
/// | JSON   | .json     | application/json |
/// | XML    | .xml      | text/xml |
```