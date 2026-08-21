/// A single dictionary entry (definition) for a search result.
///
/// `DictionaryEntry` represents one matching entry from a dictionary search, containing
/// both plain text and HTML-formatted versions of the definition.
///
/// Example:
/// ```swift
/// let entries = try await service.entries(matching: "apple", in: .oxford)
/// for entry in entries {
///     if let text = entry.text {
///         print("Definition: \(text)")
///     }
/// }
/// ```
public struct DictionaryEntry: Sendable, Equatable, Codable {
    /// The headword being defined (e.g., "apple").
    ///
    /// This is the term the dictionary indexes the entry under. It is not always the
    /// best thing to show a reader — see ``title`` and ``displayName``.
    public let headword: String

    /// The entry's display title, if the dictionary provides one.
    ///
    /// Some dictionaries distinguish the indexed headword from the title shown in the UI.
    /// Prefer ``displayName``, which falls back to ``headword`` when this is `nil`.
    public let title: String?

    /// Plain text version of the definition, if available.
    ///
    /// May be `nil` if the dictionary does not provide text format definitions.
    public let text: String?

    /// HTML-formatted version of the definition, if available.
    ///
    /// Includes styling and formatting markup. May be `nil` if the dictionary does not
    /// provide HTML format definitions.
    public let html: String?

    /// The best label to show a reader: ``title`` when the dictionary supplies one,
    /// otherwise ``headword``.
    public var displayName: String { title ?? headword }

    public init(headword: String, title: String? = nil, text: String?, html: String?) {
        self.headword = headword
        self.title = title
        self.text = text
        self.html = html
    }
}
