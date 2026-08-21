import DictionaryKit
import Foundation

/// Everything a caller of the CLI can observe from one run.
///
/// The command builds one of these and only then touches the process: rendering stays a pure
/// function of its inputs, which is what makes it testable without installed dictionaries or a
/// subprocess. `Tests/DictionaryKitCLIEndToEndTests` covers the other half — that these strings
/// really do reach the streams named here.
struct CommandOutput: Equatable, Sendable {
    var standardOutput: String = ""
    var standardError: String = ""
    var exitCode: Int32 = 0

    /// Diagnostics never belong on stdout: `dictionarykit -s foo --json | jq` has to see either
    /// well-formed output or nothing at all.
    static func failure(_ message: String...) -> CommandOutput {
        CommandOutput(
            standardError: message.map { $0 + "\n" }.joined(),
            exitCode: 1)
    }

    static func success(_ text: String) -> CommandOutput {
        CommandOutput(standardOutput: text.hasSuffix("\n") ? text : text + "\n")
    }

    /// Writes the captured streams to the process and returns the status to exit with.
    @discardableResult
    func emit() -> Int32 {
        if !standardOutput.isEmpty {
            FileHandle.standardOutput.write(Data(standardOutput.utf8))
        }
        if !standardError.isEmpty {
            FileHandle.standardError.write(Data(standardError.utf8))
        }
        return exitCode
    }
}

// MARK: - JSON payloads

struct DictionaryListing: Encodable, Equatable {
    let name: String
    let shortName: String?
    let aliases: [String]
}

struct DefinedResult: Encodable, Equatable {
    let term: String
    let dictionary: String
    let defined: Bool
}

/// JSON shape for a single entry.
///
/// Deliberately not `DictionaryEntry` itself: encoding the model directly would always embed
/// the HTML, which is orders of magnitude larger than the text and would make `--json` ignore
/// `--html` while every other output mode honours it.
struct EntryPayload: Encodable, Equatable {
    let headword: String
    let title: String?
    let text: String?
    let html: String?

    init(_ entry: DictionaryEntry, htmlMode: HTMLMode) {
        headword = entry.headword
        title = entry.title
        text = htmlMode.includesText ? entry.text : nil
        html = htmlMode.includesHTML ? entry.html : nil
    }
}

/// Which representations of a definition to emit.
///
/// Modelled as one value rather than a pair of flags so that "text suppressed and HTML also
/// suppressed" cannot be expressed. `--html` and `--html-only` are rejected together at
/// validation, so there is no precedence rule to remember here.
enum HTMLMode: Equatable, Sendable {
    /// Plain text only. The default.
    case none
    /// Plain text followed by the HTML — `--html`.
    case included
    /// HTML instead of the plain text — `--html-only`.
    case only

    var includesText: Bool { self != .only }
    var includesHTML: Bool { self != .none }
}

struct SearchPayload: Encodable, Equatable {
    let term: String
    let dictionary: String
    let entries: [EntryPayload]
}

func encodeJSON(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

// MARK: - Rendering

/// Pure renderers: input values in, `CommandOutput` out, no I/O and no `DictionaryService`.
enum Renderer {

    static func list(_ listings: [DictionaryListing], json: Bool) throws -> CommandOutput {
        if json {
            return .success(try encodeJSON(listings))
        }

        guard !listings.isEmpty else {
            return .success(
                """
                No dictionaries are installed.
                Add them in System Settings › General › Language & Region, or in Dictionary.app.
                """)
        }

        var text = "Available dictionaries (\(listings.count)):\n\n"
        for listing in listings {
            text += "  • \(listing.name)\n"
            if let shortName = listing.shortName {
                text += "     short name: \(shortName)\n"
            }
            if !listing.aliases.isEmpty {
                let quoted = listing.aliases.map { "'\($0)'" }.joined(separator: ", ")
                text += "     alias\(listing.aliases.count == 1 ? "" : "es"): \(quoted)\n"
            }
        }
        text += "\nUsage:\n"
        text += "  dictionarykit --search <term> [--dictionary <alias or name>]\n"
        text += "\nWith no --dictionary, \(DCSNewOxfordAmericanDictionaryName) is used.\n"
        return .success(text)
    }

    static func defined(
        term: String, dictionary: String, defined: Bool, json: Bool
    ) throws -> CommandOutput {
        if json {
            return .success(
                try encodeJSON(DefinedResult(term: term, dictionary: dictionary, defined: defined)))
        }
        return .success(defined ? "Yes" : "No")
    }

    /// Renders search results, including the empty case.
    ///
    /// An empty result is an error in text mode (exit 1, message on stderr) but a success in
    /// JSON mode (exit 0, empty `entries`). That asymmetry is deliberate: a shell user wants a
    /// non-zero status to branch on, while a JSON consumer wants a parseable document rather
    /// than an exception for the ordinary "no such word" case.
    static func entries(
        _ entries: [DictionaryEntry],
        term: String,
        dictionary: String,
        json: Bool,
        headwordOnly: Bool,
        htmlMode: HTMLMode
    ) throws -> CommandOutput {
        if json {
            if headwordOnly {
                return .success(try encodeJSON(entries.map(\.displayName)))
            }
            return .success(
                try encodeJSON(
                    SearchPayload(
                        term: term,
                        dictionary: dictionary,
                        entries: entries.map { EntryPayload($0, htmlMode: htmlMode) })))
        }

        guard !entries.isEmpty else {
            return .failure("No entry for '\(term)' in \(dictionary).")
        }

        var text = ""
        for entry in entries {
            if headwordOnly {
                text += entry.displayName + "\n"
                continue
            }
            text += "\n=== \(entry.displayName) ===\n"
            if htmlMode.includesText, let body = entry.text {
                text += body + "\n"
            }
            if htmlMode.includesHTML, let html = entry.html {
                // The "-- HTML --" rule separates the HTML from the text above it. With
                // --html-only there is no text to separate it from, and the point of that mode
                // is markup you can pipe somewhere, so the banner would just be noise.
                if htmlMode == .included {
                    text += "\n-- HTML --\n"
                }
                text += html + "\n"
            }
        }
        return CommandOutput(standardOutput: text)
    }

    static func dictionaryUnavailable(_ name: String) -> CommandOutput {
        .failure(
            "Dictionary not available: \(name)",
            "Run 'dictionarykit --list' to see the dictionaries installed on this Mac.")
    }

    static func privateAPIsUnavailable() -> CommandOutput {
        .failure("Error: the private DictionaryServices APIs are unavailable on this system.")
    }
}
