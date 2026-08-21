/// # DictionaryKit
///
/// A modern Swift library for accessing macOS Dictionary Services through an actor-based,
/// async/await interface.
///
/// ## Overview
///
/// DictionaryKit provides safe access to macOS's built-in dictionaries via private DictionaryServices APIs.
/// It uses runtime symbol loading to work across different macOS versions without compile-time linking to
/// private frameworks.
///
/// ## Key Components
///
/// - `DictionaryService`: The main actor providing dictionary access and search functionality
/// - `DictionaryDescriptor`: Metadata about an available dictionary
/// - `DictionaryEntry`: A search result containing a definition
/// - `DictionaryAlias`: Type-safe constants for referencing dictionaries by short names
/// - `DictionaryKitError`: Comprehensive error types for different failure scenarios
///
/// ## Quick Start
///
/// ```swift
/// import DictionaryKit
///
/// let service = DictionaryService.shared
///
/// // Check if private APIs are available
/// guard DictionaryService.canAccessPrivateAPIs() else {
///     print("Dictionary Services not available")
///     return
/// }
///
/// // Get all available dictionaries
/// let dictionaries = try await service.availableDictionaries()
///
/// // Search for a term
/// let entries = try await service.entries(matching: "apple", in: .oxford)
/// for entry in entries {
///     print("\\(entry.headword): \\(entry.text ?? entry.html ?? "")")
/// }
/// ```
///
/// ## Thread Safety
///
/// All public APIs are safe to call from multiple threads. The `DictionaryService` actor
/// automatically synchronizes access to internal state using Swift Concurrency.
///
/// ## Platform Requirements
///
/// - Requires macOS (see README for minimum version)
/// - Private APIs only; not suitable for App Store distribution
/// - Use for internal tools, command-line utilities, or local applications

import Foundation
import CDictionaryServicesShim

/// A thread-safe actor for accessing macOS Dictionary Services.
///
/// `DictionaryService` provides a modern async/await interface to macOS's built-in dictionaries
/// through private DictionaryServices APIs. It uses runtime symbol loading to safely access these
/// private APIs without compile-time linking.
///
/// The actor ensures thread safety for concurrent dictionary operations and gracefully handles
/// platforms where private APIs are unavailable.
///
/// Example:
/// ```swift
/// let service = DictionaryService.shared
/// guard DictionaryService.canAccessPrivateAPIs() else { return }
/// let dictionaries = try await service.availableDictionaries()
/// let entries = try await service.entries(matching: "apple", in: .oxford)
/// ```
///
/// > Note: Private APIs are not suitable for App Store distribution.
public actor DictionaryService {

    /// Format options for retrieving dictionary record data.
    ///
    /// These values correspond to the `version` parameter in `DCSRecordCopyData`.
    /// Different formats provide varying levels of styling and CSS inclusion.
    private enum RecordFormat: Int {
        /// HTML with popover-specific CSS styles (used for display in Dictionary.app popovers)
        case htmlWithPopoverCSS = 2
        /// Plain text format without markup
        case text = 3
    }

    /// Internal handle wrapping a dictionary reference and its metadata.
    ///
    /// Maintains the Core Foundation dictionary reference alongside its descriptor
    /// for efficient lookup and access. Instances are cached in `handlesByName`.
    ///
    /// `ref` is a strong reference: `DCSDictionaryRef` imports as `AnyObject`, so ARC keeps
    /// the underlying dictionary alive for as long as the handle is cached.
    private struct DictionaryHandle {
        /// The opaque Core Foundation reference to the dictionary
        let ref: DCSDictionaryRef
        /// Metadata about the dictionary
        let descriptor: DictionaryDescriptor
    }

    /// The default dictionary used when no specific dictionary is specified.
    ///
    /// Set to "New Oxford American Dictionary" which is commonly available on macOS systems.
    /// This dictionary is used by methods that don't require an explicit dictionary parameter.
    private static let defaultDictionaryName = DCSNewOxfordAmericanDictionaryName

    /// Cache of dictionary handles indexed by dictionary name for fast lookup
    private var handlesByName: [String: DictionaryHandle] = [:]

    /// Secondary index keyed by ``normalizedKey(for:)``, used when an exact name lookup fails.
    private var handlesByNormalizedName: [String: DictionaryHandle] = [:]

    /// Sorted list of all available dictionary descriptors
    private var descriptors: [DictionaryDescriptor] = []

    /// Flag tracking whether dictionaries have been loaded from the system
    private var didLoad = false

    /// List of required DictionaryServices symbols that must be available.
    ///
    /// Used by `canAccessPrivateAPIs()` to verify all necessary private APIs can be loaded.
    ///
    /// `DCSRecordGetTitle` is deliberately absent even though the service calls it. The title
    /// is optional metadata and the shim returns `NULL` when the symbol is missing, so listing
    /// it here would make `canAccessPrivateAPIs()` report `false` — disabling the whole
    /// library — on any macOS release that happens not to export it.
    private static let requiredSymbols: [String] = [
        "DCSCopyAvailableDictionaries",
        "DCSDictionaryGetName",
        "DCSDictionaryGetShortName",
        "DCSCopyRecordsForSearchString",
        "DCSRecordCopyData",
        "DCSRecordGetHeadword",
        "DCSGetTermRangeInString",
    ]

    /// Builds a forgiving lookup key for a dictionary name.
    ///
    /// DictionaryServices matches names by exact string, and the names it reports contain
    /// traps: a trailing space on the Hebrew dictionary, a typographic apostrophe in the
    /// Oxford American Writer's Thesaurus, and Indic names that mix precomposed and
    /// decomposed nukta forms. A caller who retypes one of those by hand gets a string that
    /// looks identical and matches nothing.
    ///
    /// Normalizing to NFC, trimming whitespace, and folding typographic punctuation to ASCII
    /// makes those near misses resolve instead of failing silently. Exact matches are always
    /// tried first, so this never changes the result for a correct name.
    private static func normalizedKey(for name: String) -> String {
        name
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Looks up a cached handle, falling back to a normalized comparison.
    private func handle(named name: String) -> DictionaryHandle? {
        handlesByName[name] ?? handlesByNormalizedName[Self.normalizedKey(for: name)]
    }

    /// Extracts the substring covered by a `CFRange` expressed in UTF-16 code units.
    ///
    /// Returns `nil` if the range is out of bounds or does not land on Character boundaries,
    /// which lets callers surface an error instead of trapping.
    private static func substring(of string: String, utf16Range range: CFRange) -> String? {
        guard range.location >= 0, range.length >= 0 else { return nil }
        let utf16 = string.utf16
        guard
            let start = utf16.index(
                utf16.startIndex, offsetBy: range.location, limitedBy: utf16.endIndex),
            let end = utf16.index(start, offsetBy: range.length, limitedBy: utf16.endIndex),
            let startIndex = String.Index(start, within: string),
            let endIndex = String.Index(end, within: string)
        else { return nil }
        return String(string[startIndex..<endIndex])
    }

    /// Ensures that private DictionaryServices symbols are available.
    ///
    /// Helper method that throws an error if `canAccessPrivateAPIs()` returns false.
    ///
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if symbols cannot be loaded
    private func ensureSymbolsAvailable() throws {
        guard DictionaryService.canAccessPrivateAPIs() else {
            throw DictionaryKitError.privateAPIsUnavailable
        }
    }

    /// Loads all available dictionaries from the system if not already loaded.
    ///
    /// This method performs one-time initialization, querying DictionaryServices for all
    /// installed dictionaries and caching their handles and descriptors. Subsequent calls
    /// return immediately if dictionaries are already loaded.
    ///
    /// The loading process:
    /// 1. Verifies private APIs are available
    /// 2. Retrieves the set of all dictionaries via `DCSCopyAvailableDictionaries`
    /// 3. Iterates through each dictionary to extract name and short name
    /// 4. Creates descriptors and handles for each dictionary
    /// 5. Sorts descriptors alphabetically and caches handles by name
    ///
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if symbols cannot be loaded
    /// - Throws: `DictionaryKitError.missingSymbol` if a required symbol fails to load
    private func ensureLoaded() throws {
        if didLoad { return }
        try ensureSymbolsAvailable()

        guard let loadedSet = dkds_copy_available_dictionaries() else {
            throw DictionaryKitError.missingSymbol("DCSCopyAvailableDictionaries")
        }

        let count = CFSetGetCount(loadedSet)
        var dictionaries = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(loadedSet, &dictionaries)

        var nextDescriptors: [DictionaryDescriptor] = []
        var nextHandles: [String: DictionaryHandle] = [:]
        var nextNormalizedHandles: [String: DictionaryHandle] = [:]

        for pointer in dictionaries {
            guard let pointer else { continue }

            // `DCSDictionaryRef` is `const void *` in C, but the CF_RETURNS_* annotations put
            // the header in a CF-audited region, so Swift imports it as `AnyObject` rather
            // than `UnsafeRawPointer`. That is what makes this safe: once converted, each
            // reference is a genuine object and ARC retains it for as long as the handle
            // holding it lives. Taking it unretained here is correct — the set owns the +1.
            let dictionaryRef: DCSDictionaryRef = Unmanaged<AnyObject>.fromOpaque(pointer)
                .takeUnretainedValue()

            guard let nameString = dkds_get_dictionary_name(dictionaryRef) as String? else {
                continue
            }
            let shortName = dkds_get_dictionary_short_name(dictionaryRef) as String?

            let descriptor = DictionaryDescriptor(name: nameString, shortName: shortName)
            let handle = DictionaryHandle(ref: dictionaryRef, descriptor: descriptor)

            nextDescriptors.append(descriptor)
            nextHandles[nameString] = handle
            // First writer wins, so an exact name is never shadowed by another entry's
            // normalized form.
            let key = Self.normalizedKey(for: nameString)
            if nextNormalizedHandles[key] == nil {
                nextNormalizedHandles[key] = handle
            }
        }

        descriptors = nextDescriptors.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        handlesByName = nextHandles
        handlesByNormalizedName = nextNormalizedHandles
        didLoad = true
    }

    /// Core implementation for searching a dictionary using a cached handle.
    ///
    /// This private method performs the actual dictionary search and record processing:
    /// 1. Identifies the term's range within the search string using `DCSGetTermRangeInString`
    /// 2. Trims the term to match what the dictionary expects
    /// 3. Retrieves matching records via `DCSCopyRecordsForSearchString`
    /// 4. Extracts headword, text, and HTML data for each record
    /// 5. Constructs `DictionaryEntry` objects from the results
    ///
    /// - Parameters:
    ///   - term: The search term
    ///   - handle: The cached dictionary handle to search in
    /// - Returns: An array of matching dictionary entries
    /// - Throws: `DictionaryKitError.termNotFound` if the term range cannot be determined
    /// - Throws: `DictionaryKitError.dataUnavailable` if records cannot be retrieved
    private func entries(
        matching term: String, handle: DictionaryHandle
    ) throws -> [DictionaryEntry] {
        let cfTerm = term as CFString
        let fullRange = CFRange(location: 0, length: CFStringGetLength(cfTerm))
        let termRange = dkds_get_term_range_in_string(handle.ref, cfTerm, fullRange)

        guard termRange.location != kCFNotFound else {
            throw DictionaryKitError.termNotFound(term)
        }

        // `termRange` is measured in UTF-16 code units, so it must be applied through the
        // UTF-16 view. Walking it with `String.index(_:offsetBy:)` counts Characters instead
        // and runs past `endIndex` — a trap, not an error — for any term containing an
        // emoji, an astral-plane scalar, or a multi-scalar grapheme.
        guard let trimmedTerm = Self.substring(of: term, utf16Range: termRange) else {
            throw DictionaryKitError.termNotFound(term)
        }

        guard
            let recordArray = dkds_copy_records_for_search_string(
                handle.ref, trimmedTerm as CFString)
        else {
            throw DictionaryKitError.dataUnavailable("Records for term \(trimmedTerm)")
        }

        let recordCount = CFArrayGetCount(recordArray)
        var entries: [DictionaryEntry] = []
        entries.reserveCapacity(recordCount)

        for i in 0..<recordCount {
            guard let recordValue = CFArrayGetValueAtIndex(recordArray, i) else {
                continue
            }
            let recordRef = recordValue
            guard let headword = dkds_get_record_headword(recordRef) as String? else {
                continue
            }
            let title = dkds_get_record_title(recordRef) as String?
            let text = dkds_record_copy_data(recordRef, RecordFormat.text.rawValue) as String?
            let html =
                dkds_record_copy_data(recordRef, RecordFormat.htmlWithPopoverCSS.rawValue)
                as String?

            entries.append(
                DictionaryEntry(headword: headword, title: title, text: text, html: html))
        }

        return entries
    }

}

// MARK: - Public API

extension DictionaryService {

    /// Shared singleton instance of DictionaryService.
    ///
    /// Use this instance for all dictionary operations. Thread-safe access is guaranteed through
    /// the actor model.
    public static let shared = DictionaryService()

    /// Checks if private Dictionary Services APIs are available on this system.
    ///
    /// This static method checks whether the required private symbols from DictionaryServices
    /// framework can be loaded at runtime. Always call this before attempting to use the service.
    ///
    /// - Returns: `true` if all required private APIs are available, `false` otherwise
    ///
    /// Example:
    /// ```swift
    /// if DictionaryService.canAccessPrivateAPIs() {
    ///     let dictionaries = try await service.availableDictionaries()
    /// } else {
    ///     print("Dictionary Services not available")
    /// }
    /// ```
    public static func canAccessPrivateAPIs() -> Bool {
        guard dkds_load_library() else { return false }
        return requiredSymbols.allSatisfy { dkds_has_symbol($0) }
    }

    /// Retrieves all available dictionaries on this system.
    ///
    /// Returns a list of all installed dictionaries accessible through Dictionary Services.
    /// Dictionaries are sorted alphabetically by name.
    ///
    /// - Returns: An array of `DictionaryDescriptor` objects for all available dictionaries
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    /// - Throws: `DictionaryKitError.missingSymbol` if required symbols fail to load
    ///
    /// Example:
    /// ```swift
    /// let dictionaries = try await service.availableDictionaries()
    /// for dict in dictionaries {
    ///     print(dict.name)
    /// }
    /// ```
    public func availableDictionaries() async throws -> [DictionaryDescriptor] {
        try ensureLoaded()
        return descriptors
    }

    /// Retrieves a specific dictionary by its name.
    ///
    /// - Parameters:
    ///   - name: The full name of the dictionary to retrieve
    /// - Returns: A `DictionaryDescriptor` for the requested dictionary
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the dictionary is not installed
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// let descriptor = try await service.dictionary(named: DCSOxfordDictionaryOfEnglish)
    /// ```
    public func dictionary(named name: String) async throws -> DictionaryDescriptor {
        try ensureLoaded()
        guard let handle = handle(named: name) else {
            throw DictionaryKitError.dictionaryUnavailable(name)
        }
        return handle.descriptor
    }

    /// Searches for entries matching a term in a specific dictionary.
    ///
    /// Searches the specified dictionary for all entries matching the given term and returns
    /// both plain text and HTML-formatted definitions.
    ///
    /// - Parameters:
    ///   - term: The term to search for
    ///   - name: The full name of the dictionary to search in
    /// - Returns: An array of `DictionaryEntry` objects with matching results
    /// - Throws: `DictionaryKitError.termNotFound` if no matching term is found
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the dictionary is not installed
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// let entries = try await service.entries(
    ///     matching: "apple",
    ///     in: DCSOxfordDictionaryOfEnglish
    /// )
    /// ```
    public func entries(matching term: String, in name: String) async throws -> [DictionaryEntry] {
        try ensureLoaded()
        guard let handle = handle(named: name) else {
            throw DictionaryKitError.dictionaryUnavailable(name)
        }
        return try entries(matching: term, handle: handle)
    }

    /// Searches for entries matching a term using a dictionary descriptor.
    ///
    /// Searches the dictionary specified by the descriptor for all entries matching the given term.
    /// This is a convenience method that takes a previously retrieved `DictionaryDescriptor`.
    ///
    /// - Parameters:
    ///   - term: The term to search for
    ///   - descriptor: The `DictionaryDescriptor` of the dictionary to search in
    /// - Returns: An array of `DictionaryEntry` objects with matching results
    /// - Throws: `DictionaryKitError.termNotFound` if no matching term is found
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the dictionary is no longer available
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// let descriptors = try await service.availableDictionaries()
    /// if let oxford = descriptors.first(where: { $0.name == DCSOxfordDictionaryOfEnglish }) {
    ///     let entries = try await service.entries(matching: "apple", in: oxford)
    /// }
    /// ```
    public func entries(
        matching term: String, in descriptor: DictionaryDescriptor
    ) async throws -> [DictionaryEntry] {
        try await entries(matching: term, in: descriptor.name)
    }

    /// Search for entries using a type-safe dictionary alias
    ///
    /// This is a convenience method that provides compile-time safety when using predefined dictionary aliases.
    ///
    /// - Parameters:
    ///   - term: The term to search for
    ///   - alias: The dictionary alias to search in
    /// - Returns: Array of matching entries
    /// - Throws: `DictionaryKitError` if the operation fails
    ///
    /// Example:
    /// ```swift
    /// let entries = try await service.entries(matching: "apple", in: .oxford)
    /// let entries = try await service.entries(matching: "bonjour", in: .french)
    /// ```
    public func entries(
        matching term: String, in alias: DictionaryAlias
    ) async throws -> [DictionaryEntry] {
        try await entries(matching: term, in: alias.dictionaryName)
    }

    /// Searches for entries matching a term in the default dictionary.
    ///
    /// Searches the default dictionary (New Oxford American Dictionary) for all entries matching the given term.
    /// This is a convenience method for quick lookups without specifying a dictionary.
    ///
    /// - Parameters:
    ///   - term: The term to search for
    /// - Returns: An array of `DictionaryEntry` objects with matching results
    /// - Throws: `DictionaryKitError.termNotFound` if no matching term is found
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the default dictionary is not installed
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// // Search in default dictionary (New Oxford American Dictionary)
    /// let entries = try await service.entries(matching: "apple")
    /// ```
    public func entries(matching term: String) async throws -> [DictionaryEntry] {
        try await entries(matching: term, in: Self.defaultDictionaryName)
    }

    /// Checks if a term is defined in a specific dictionary.
    ///
    /// This is a lightweight boolean check that determines whether a term exists in the dictionary
    /// without retrieving the full definition data. Useful for validation or conditional logic.
    ///
    /// - Parameters:
    ///   - term: The term to check
    ///   - name: The full name of the dictionary to check in
    /// - Returns: `true` if the term is defined, `false` if not found
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the dictionary is not installed
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// let isDefined = try await service.isDefined("apple", in: DCSOxfordDictionaryOfEnglish)
    /// if isDefined {
    ///     print("Term exists in dictionary")
    /// }
    /// ```
    public func isDefined(_ term: String, in name: String) async throws -> Bool {
        do {
            _ = try await entries(matching: term, in: name)
            return true
        } catch DictionaryKitError.termNotFound {
            return false
        }
    }

    /// Checks if a term is defined using a dictionary descriptor.
    ///
    /// - Parameters:
    ///   - term: The term to check
    ///   - descriptor: The `DictionaryDescriptor` of the dictionary to check in
    /// - Returns: `true` if the term is defined, `false` if not found
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the dictionary is no longer available
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// let descriptors = try await service.availableDictionaries()
    /// if let oxford = descriptors.first(where: { $0.name == DCSOxfordDictionaryOfEnglish }) {
    ///     let isDefined = try await service.isDefined("apple", in: oxford)
    /// }
    /// ```
    public func isDefined(_ term: String, in descriptor: DictionaryDescriptor) async throws -> Bool
    {
        try await isDefined(term, in: descriptor.name)
    }

    /// Checks if a term is defined using a type-safe dictionary alias.
    ///
    /// - Parameters:
    ///   - term: The term to check
    ///   - alias: The dictionary alias to check in
    /// - Returns: `true` if the term is defined, `false` if not found
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the dictionary is not installed
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// let isDefined = try await service.isDefined("apple", in: .oxford)
    /// let isFrenchWord = try await service.isDefined("bonjour", in: .french)
    /// ```
    public func isDefined(_ term: String, in alias: DictionaryAlias) async throws -> Bool {
        try await isDefined(term, in: alias.dictionaryName)
    }

    /// Checks if a term is defined in the default dictionary.
    ///
    /// Checks the default dictionary (New Oxford American Dictionary) for the term.
    /// This is a convenience method for quick validation without specifying a dictionary.
    ///
    /// - Parameters:
    ///   - term: The term to check
    /// - Returns: `true` if the term is defined in the default dictionary, `false` if not found
    /// - Throws: `DictionaryKitError.dictionaryUnavailable` if the default dictionary is not installed
    /// - Throws: `DictionaryKitError.privateAPIsUnavailable` if private APIs cannot be accessed
    ///
    /// Example:
    /// ```swift
    /// // Check in default dictionary (New Oxford American Dictionary)
    /// let isDefined = try await service.isDefined("apple")
    /// ```
    public func isDefined(_ term: String) async throws -> Bool {
        try await isDefined(term, in: Self.defaultDictionaryName)
    }

}
