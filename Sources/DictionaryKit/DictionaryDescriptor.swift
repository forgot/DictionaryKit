/// Metadata about an available dictionary on the system.
///
/// `DictionaryDescriptor` provides information about an installed dictionary, including its
/// full name and optional short name. Use this to identify and work with specific dictionaries.
///
/// Descriptors are returned by `DictionaryService.availableDictionaries()` and used in search methods.
///
/// Example:
/// ```swift
/// let descriptors = try await service.availableDictionaries()
/// for descriptor in descriptors {
///     print("\(descriptor.name) (\(descriptor.shortName ?? "no short name"))")
/// }
/// ```
public struct DictionaryDescriptor: Identifiable, Sendable, Hashable, Codable {
    /// Unique identifier for this dictionary, equal to its full name.
    public var id: String { name }

    /// The full name of the dictionary (e.g., "Oxford Dictionary of English").
    ///
    /// Use this name when searching with `entries(matching:in:)` method.
    public let name: String

    /// An optional short display name for the dictionary, if available.
    ///
    /// May be `nil` if the dictionary does not provide a short name.
    public let shortName: String?
}
