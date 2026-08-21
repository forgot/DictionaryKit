import Foundation
import Testing

@testable import DictionaryKit

/// True when the private DictionaryServices symbols resolve on this machine.
private let apisAvailable = DictionaryService.canAccessPrivateAPIs()

/// Returns the installed dictionaries, or an empty array when the APIs are unavailable.
///
/// Tests must tolerate a machine with the framework present but no dictionary content — that
/// is the normal state of a CI runner, and `#require(dictionaries.first)` would turn it into a
/// wall of failures rather than a clean skip.
private func installedDictionaries() async throws -> [DictionaryDescriptor] {
    guard apisAvailable else { return [] }
    return try await DictionaryService.shared.availableDictionaries()
}

/// Picks a dictionary likely to define ordinary English words, falling back to whatever exists.
private func englishDictionary() async throws -> DictionaryDescriptor? {
    let all = try await installedDictionaries()
    let preferred = [
        DCSNewOxfordAmericanDictionaryName,
        DCSOxfordDictionaryOfEnglish,
        DCSAppleDictionaryName,
    ]
    return all.first { preferred.contains($0.name) } ?? all.first
}

@Suite("Dictionary name constants")
struct DictionaryNameTests {

    /// Guards the failure mode that silently broke five constants.
    ///
    /// DictionaryServices matches names by exact string. A hand-transcribed name that differs
    /// by a trailing space, a typographic apostrophe, or a precomposed vs decomposed nukta
    /// renders identically and matches nothing — the alias just stops working, with no error
    /// anywhere. This asserts that every alias whose dictionary is installed matches it
    /// *exactly*, so a near miss fails loudly here instead of silently in the field.
    @Test("no alias is a near miss for an installed dictionary")
    func aliasesAreNotNearMisses() async throws {
        let installed = try await installedDictionaries()
        guard !installed.isEmpty else { return }

        let exactNames = Set(installed.map(\.name))
        func loosened(_ value: String) -> String {
            value
                .precomposedStringWithCanonicalMapping
                .replacingOccurrences(of: "\u{2019}", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }
        let loosenedNames = Dictionary(
            installed.map { (loosened($0.name), $0.name) }, uniquingKeysWith: { first, _ in first })

        for alias in DictionaryAlias.allCases {
            let name = alias.dictionaryName
            guard !exactNames.contains(name) else { continue }
            if let actual = loosenedNames[loosened(name)] {
                Issue.record(
                    """
                    Alias '\(alias.rawValue)' nearly matches an installed dictionary but not \
                    exactly, so lookups by exact name will fail.
                      constant: \(Array(name.unicodeScalars.map { "U+\(String($0.value, radix: 16, uppercase: true))" }.suffix(12)))
                      system:   \(Array(actual.unicodeScalars.map { "U+\(String($0.value, radix: 16, uppercase: true))" }.suffix(12)))
                    """)
            }
        }
    }

    @Test("no constant contains a replacement character")
    func noReplacementCharacters() {
        for alias in DictionaryAlias.allCases {
            #expect(
                !alias.dictionaryName.unicodeScalars.contains("\u{FFFD}"),
                "Alias '\(alias.rawValue)' contains U+FFFD, so it can never match a dictionary.")
        }
    }

    @Test("every alias maps to a non-empty name")
    func aliasesHaveNames() {
        for alias in DictionaryAlias.allCases {
            #expect(!alias.dictionaryName.isEmpty)
        }
    }
}

@Suite("DictionaryAlias")
struct DictionaryAliasTests {

    @Test("parses user input case-insensitively and ignores surrounding whitespace")
    func parsesUserInput() {
        #expect(DictionaryAlias(userInput: "oxford") == .oxford)
        #expect(DictionaryAlias(userInput: "OXFORD") == .oxford)
        #expect(DictionaryAlias(userInput: "  Oxford  ") == .oxford)
        #expect(DictionaryAlias(userInput: "oxford-uk") == .oxfordUK)
        #expect(DictionaryAlias(userInput: "not-an-alias") == nil)
        #expect(DictionaryAlias(userInput: "") == nil)
    }

    @Test("reports every alias for a dictionary, not just the first")
    func reportsAllAliases() {
        let oxford = DictionaryAlias.aliases(for: DCSOxfordDictionaryOfEnglish)
        #expect(oxford.contains(.oxford))
        #expect(oxford.contains(.oxfordUK), "oxford-uk maps to the same dictionary as oxford")
        #expect(DictionaryAlias.aliases(for: "Nothing Named This").isEmpty)
    }
}

@Suite(
    "DictionaryService", .enabled(if: apisAvailable, "Private DictionaryServices APIs unavailable.")
)
struct DictionaryServiceTests {

    @Test("lists installed dictionaries")
    func availableDictionaries() async throws {
        let dictionaries = try await installedDictionaries()
        // An empty list is legitimate on a machine with no dictionary content installed.
        for dictionary in dictionaries {
            #expect(!dictionary.name.isEmpty)
            #expect(dictionary.id == dictionary.name)
        }
    }

    @Test("fetches a dictionary by name")
    func dictionaryByName() async throws {
        guard let expected = try await englishDictionary() else { return }
        let retrieved = try await DictionaryService.shared.dictionary(named: expected.name)
        #expect(retrieved == expected)
    }

    @Test("resolves a name that differs only by whitespace or apostrophe form")
    func toleratesNearMissNames() async throws {
        guard let expected = try await englishDictionary() else { return }
        let sloppy = "  " + expected.name.replacingOccurrences(of: "\u{2019}", with: "'") + " "
        let retrieved = try await DictionaryService.shared.dictionary(named: sloppy)
        #expect(retrieved.name == expected.name)
    }

    @Test("unknown dictionary throws dictionaryUnavailable")
    func unknownDictionaryThrows() async throws {
        await #expect(throws: DictionaryKitError.dictionaryUnavailable("NoSuchDictionary_12345")) {
            try await DictionaryService.shared.dictionary(named: "NoSuchDictionary_12345")
        }
    }

    @Test("finds entries by name and by descriptor")
    func findsEntries() async throws {
        guard let dictionary = try await englishDictionary() else { return }
        let byName = try await DictionaryService.shared.entries(
            matching: "apple", in: dictionary.name)
        let byDescriptor = try await DictionaryService.shared.entries(
            matching: "apple", in: dictionary)
        #expect(!byName.isEmpty)
        #expect(byName == byDescriptor)
    }

    @Test("entries expose a headword and a display name")
    func entryShape() async throws {
        guard let dictionary = try await englishDictionary() else { return }
        let entries = try await DictionaryService.shared.entries(
            matching: "apple", in: dictionary.name)
        let entry = try #require(entries.first)

        #expect(!entry.headword.isEmpty)
        #expect(!entry.displayName.isEmpty)
        #expect(entry.displayName == (entry.title ?? entry.headword))
        #expect(entry.text?.isEmpty == false)
    }

    @Test("unknown term throws termNotFound")
    func unknownTermThrows() async throws {
        guard let dictionary = try await englishDictionary() else { return }
        await #expect(throws: DictionaryKitError.termNotFound("xyzabc123notaword")) {
            try await DictionaryService.shared.entries(
                matching: "xyzabc123notaword", in: dictionary.name)
        }
    }

    /// Regression test for a trap, not an error.
    ///
    /// The term range comes back from `DCSGetTermRangeInString` in UTF-16 code units. Applying
    /// it with `String.index(_:offsetBy:)` counts Characters instead, so any term whose prefix
    /// contains an emoji or other astral-plane scalar used to walk past `endIndex` and crash
    /// the process. These must all return or throw — never trap.
    @Test(
        "non-ASCII and multi-scalar terms never trap",
        arguments: ["🍎apple", "café", "naïve", "👨‍👩‍👧‍👦family", "日本", "e\u{301}cole", "apple pie"])
    func multiScalarTermsAreSafe(term: String) async throws {
        guard let dictionary = try await englishDictionary() else { return }
        do {
            _ = try await DictionaryService.shared.entries(matching: term, in: dictionary.name)
        } catch is DictionaryKitError {
            // Any DictionaryKitError is an acceptable outcome; a crash is not.
        }
    }

    @Test("isDefined agrees with entries")
    func isDefinedAgreesWithEntries() async throws {
        guard let dictionary = try await englishDictionary() else { return }
        #expect(try await DictionaryService.shared.isDefined("apple", in: dictionary.name))
        #expect(try await DictionaryService.shared.isDefined("apple", in: dictionary))
        #expect(
            try await !DictionaryService.shared.isDefined("xyzabc123notaword", in: dictionary.name))
    }

    @Test("default-dictionary overloads use the New Oxford American Dictionary")
    func defaultDictionaryOverloads() async throws {
        let installed = try await installedDictionaries()
        guard installed.contains(where: { $0.name == DCSNewOxfordAmericanDictionaryName }) else {
            return
        }
        let viaDefault = try await DictionaryService.shared.entries(matching: "apple")
        let viaName = try await DictionaryService.shared.entries(
            matching: "apple", in: DCSNewOxfordAmericanDictionaryName)
        #expect(viaDefault == viaName)
        #expect(try await DictionaryService.shared.isDefined("apple"))
    }

    @Test("alias overloads resolve to the same results as full names")
    func aliasOverloads() async throws {
        let installed = Set(try await installedDictionaries().map(\.name))
        guard installed.contains(DictionaryAlias.oxford.dictionaryName) else { return }
        let viaAlias = try await DictionaryService.shared.entries(matching: "apple", in: .oxford)
        let viaName = try await DictionaryService.shared.entries(
            matching: "apple", in: DictionaryAlias.oxford.dictionaryName)
        #expect(viaAlias == viaName)
    }
}

@Suite("Value types")
struct ValueTypeTests {

    @Test("DictionaryEntry.displayName prefers the title")
    func displayNamePrefersTitle() {
        let withTitle = DictionaryEntry(headword: "apple", title: "Apple", text: nil, html: nil)
        let withoutTitle = DictionaryEntry(headword: "apple", text: nil, html: nil)
        #expect(withTitle.displayName == "Apple")
        #expect(withoutTitle.displayName == "apple")
        #expect(withoutTitle.headword == "apple", "headword must remain the real headword")
    }

    @Test("DictionaryEntry round-trips through JSON")
    func entryCodableRoundTrip() throws {
        let entry = DictionaryEntry(
            headword: "apple", title: "Apple", text: "a fruit", html: "<p>a fruit</p>")
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(DictionaryEntry.self, from: data) == entry)
    }

    /// `error.localizedDescription` silently degrades to Foundation's generic
    /// "operation couldn't be completed" text unless the type conforms to `LocalizedError`.
    @Test(
        "errors describe themselves through both description and localizedDescription",
        arguments: [
            DictionaryKitError.privateAPIsUnavailable,
            .missingSymbol("DCSCopyAvailableDictionaries"),
            .dictionaryUnavailable("Nope"),
            .termNotFound("nope"),
            .dataUnavailable("records"),
        ])
    func errorDescriptions(error: DictionaryKitError) {
        #expect(!error.description.isEmpty)
        #expect(
            error.localizedDescription == error.description,
            "localizedDescription fell back to Foundation's generic message")
    }
}
