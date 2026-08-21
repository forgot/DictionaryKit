import ArgumentParser
import DictionaryKit
import Foundation

/// Resolves user input to a dictionary name, or `nil` to mean "use the default".
func resolveDictionary(_ input: String?) -> String? {
    guard let input, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    return DictionaryAlias(userInput: input)?.dictionaryName ?? input
}

/// Searches macOS dictionaries from the command line.
///
/// The command lives in a library rather than the executable target so it can be unit tested;
/// `Sources/dictionarykit-cli` is a thin `@main` shim over it.
public struct DictionaryKitCommand: AsyncParsableCommand {

    public static let configuration = CommandConfiguration(
        commandName: "dictionarykit",
        abstract: "Search macOS dictionaries from the command line",
        discussion: """
            Dictionaries can be named by alias ('oxford', 'french') or by full name. \
            With no --dictionary, the New Oxford American Dictionary is used.

            Run 'dictionarykit --list' to see the dictionaries installed on this Mac \
            along with the aliases that resolve to them.
            """,
        version: DictionaryKitVersion.current
    )

    @Flag(name: .shortAndLong, help: "List all available dictionaries and their aliases.")
    var list = false

    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "Dictionary to search: a short alias like 'oxford', or a full name.",
            valueName: "name"))
    var dictionary: String?

    @Option(name: .shortAndLong, help: ArgumentHelp("Term to look up.", valueName: "term"))
    var search: String?

    @Flag(help: "Include HTML-formatted definitions alongside the text.")
    var html = false

    @Flag(name: .long, help: "Emit the HTML-formatted definitions instead of the text.")
    var htmlOnly = false

    @Flag(help: "Print only 'Yes' or 'No' according to whether the term is defined.")
    var isDefined = false

    @Flag(name: [.customShort("H"), .long], help: "Print only headwords, without definitions.")
    var headwordOnly = false

    @Flag(help: "Emit JSON instead of human-readable text.")
    var json = false

    public init() {}

    public mutating func validate() throws {
        if list {
            let conflicts = [
                ("--search", search != nil), ("--is-defined", isDefined),
                ("--headword-only", headwordOnly), ("--html", html), ("--html-only", htmlOnly),
            ]
            .filter(\.1).map(\.0)
            guard conflicts.isEmpty else {
                throw ValidationError(
                    "--list cannot be combined with \(conflicts.joined(separator: ", ")).")
            }
            return
        }

        guard search != nil else {
            throw ValidationError("Provide a term with --search, or use --list.")
        }
        if isDefined && headwordOnly {
            throw ValidationError("--is-defined and --headword-only cannot be combined.")
        }
        // --html asks for HTML in addition to the text and --html-only asks for it instead,
        // so together one of them has no effect. Rejecting beats silently picking a winner.
        if html && htmlOnly {
            throw ValidationError(
                "--html and --html-only cannot be combined; --html-only already implies HTML.")
        }
        // These would otherwise be silently ignored, which reads as a bug from the outside.
        for (name, given) in [("--html", html), ("--html-only", htmlOnly)] where given {
            if isDefined || headwordOnly {
                throw ValidationError(
                    "\(name) cannot be combined with "
                        + "\(isDefined ? "--is-defined" : "--headword-only").")
            }
        }
    }

    /// Which representations of a definition the flags ask for.
    var htmlMode: HTMLMode {
        if htmlOnly { return .only }
        return html ? .included : .none
    }

    public mutating func run() async throws {
        let output = try await makeOutput()
        let status = output.emit()
        if status != 0 {
            throw ExitCode(status)
        }
    }

    /// Produces the run's output without writing to the process.
    ///
    /// Split out from ``run()`` so tests can assert on streams and exit status directly.
    func makeOutput() async throws -> CommandOutput {
        guard DictionaryService.canAccessPrivateAPIs() else {
            return Renderer.privateAPIsUnavailable()
        }

        let service = DictionaryService.shared
        if list {
            return try await listOutput(service: service)
        }
        guard let search else {
            // validate() guarantees one of --list or --search; nothing to do otherwise.
            return CommandOutput()
        }
        return try await lookUpOutput(search, service: service)
    }

    private func listOutput(service: DictionaryService) async throws -> CommandOutput {
        let dictionaries = try await service.availableDictionaries()
        let listings = dictionaries.map { descriptor in
            DictionaryListing(
                name: descriptor.name,
                shortName: descriptor.shortName,
                // A dictionary can have several aliases — 'oxford' and 'oxford-uk' both
                // point at the Oxford Dictionary of English — so show all of them.
                aliases: DictionaryAlias.aliases(for: descriptor.name).map(\.rawValue))
        }
        return try Renderer.list(listings, json: json)
    }

    private func lookUpOutput(
        _ term: String, service: DictionaryService
    ) async throws
        -> CommandOutput
    {
        let resolvedName = resolveDictionary(dictionary)
        let effectiveName = resolvedName ?? DCSNewOxfordAmericanDictionaryName

        do {
            if isDefined {
                let defined =
                    if let resolvedName {
                        try await service.isDefined(term, in: resolvedName)
                    } else {
                        try await service.isDefined(term)
                    }
                return try Renderer.defined(
                    term: term, dictionary: effectiveName, defined: defined, json: json)
            }

            let entries =
                if let resolvedName {
                    try await service.entries(matching: term, in: resolvedName)
                } else {
                    try await service.entries(matching: term)
                }
            return try Renderer.entries(
                entries, term: term, dictionary: effectiveName,
                json: json, headwordOnly: headwordOnly, htmlMode: htmlMode)

        } catch DictionaryKitError.termNotFound {
            if isDefined {
                return try Renderer.defined(
                    term: term, dictionary: effectiveName, defined: false, json: json)
            }
            // The library reports "no such word" by throwing, so route it through the same
            // renderer as an empty result rather than duplicating the message.
            return try Renderer.entries(
                [], term: term, dictionary: effectiveName,
                json: json, headwordOnly: headwordOnly, htmlMode: htmlMode)

        } catch DictionaryKitError.dictionaryUnavailable(let name) {
            return Renderer.dictionaryUnavailable(name)
        }
    }
}
