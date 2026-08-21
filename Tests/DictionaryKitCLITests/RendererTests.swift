import DictionaryKit
import Foundation
import Testing

@testable import DictionaryKitCLI

/// Tests for the CLI's rendering layer.
///
/// These are deliberately free of `DictionaryService`: the renderers are pure functions of
/// their inputs, so the whole suite runs on a machine with no dictionaries installed — which
/// is the case the old suite could never cover.
@Suite("CLI rendering")
struct RendererTests {

    private func entry(
        _ headword: String, title: String? = nil, text: String? = "definition",
        html: String? = "<p>definition</p>"
    ) -> DictionaryEntry {
        DictionaryEntry(headword: headword, title: title, text: text, html: html)
    }

    private func json(_ output: CommandOutput) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(output.standardOutput.utf8))
    }

    // MARK: Text output

    @Test("an entry is printed under a '=== … ===' header")
    func textHeader() throws {
        let output = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .none)

        #expect(output.standardOutput.contains("=== apple ==="))
        #expect(output.standardOutput.contains("definition"))
        #expect(output.exitCode == 0)
        #expect(output.standardError.isEmpty)
    }

    @Test("the header shows the title when the dictionary supplies one")
    func textHeaderPrefersTitle() throws {
        let output = try Renderer.entries(
            [entry("upset the applecart", title: "apple")], term: "upset the applecart",
            dictionary: "NOAD", json: false, headwordOnly: false, htmlMode: .none)

        #expect(output.standardOutput.contains("=== apple ==="))
        #expect(!output.standardOutput.contains("=== upset the applecart ==="))
    }

    @Test("--headword-only prints one bare name per entry")
    func headwordOnly() throws {
        let output = try Renderer.entries(
            [entry("set"), entry("Set", title: "Seth")], term: "set", dictionary: "NOAD",
            json: false, headwordOnly: true, htmlMode: .none)

        #expect(output.standardOutput == "set\nSeth\n")
        #expect(!output.standardOutput.contains("==="))
        #expect(!output.standardOutput.contains("definition"))
    }

    @Test("HTML is withheld unless it is asked for")
    func htmlOnlyWhenRequested() throws {
        let without = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .none)
        #expect(!without.standardOutput.contains("-- HTML --"))

        let with = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .included)
        #expect(with.standardOutput.contains("-- HTML --"))
        #expect(with.standardOutput.contains("<p>definition</p>"))
    }

    // MARK: --html-only

    @Test("--html-only replaces the text rather than adding to it")
    func htmlOnlyReplacesText() throws {
        let output = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .only)

        #expect(output.standardOutput.contains("<p>definition</p>"))
        #expect(!output.standardOutput.contains("definition\n"), "the plain text should be gone")
        #expect(output.exitCode == 0)
    }

    @Test("--html-only drops the '-- HTML --' banner, which has nothing to separate")
    func htmlOnlyHasNoBanner() throws {
        let only = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .only)
        #expect(!only.standardOutput.contains("-- HTML --"))

        // The banner exists to divide HTML from the text above it, so --html keeps it.
        let included = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .included)
        #expect(included.standardOutput.contains("-- HTML --"))
    }

    @Test("--html-only still labels each entry, so several stay distinguishable")
    func htmlOnlyKeepsHeaders() throws {
        let output = try Renderer.entries(
            [entry("bank"), entry("bank")], term: "bank", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .only)

        #expect(output.standardOutput.components(separatedBy: "=== bank ===").count == 3)
    }

    @Test("--html-only omits text and keeps html in JSON")
    func htmlOnlyJSON() throws {
        let output = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: true, headwordOnly: false, htmlMode: .only)

        let payload = try #require(try json(output) as? [String: Any])
        let entries = try #require(payload["entries"] as? [[String: Any]])
        #expect(entries[0]["html"] as? String == "<p>definition</p>")
        #expect(entries[0]["text"] == nil, "--html-only should drop the text key entirely")
        #expect(entries[0]["headword"] as? String == "apple")
    }

    @Test("an entry with no HTML degrades to its header rather than failing")
    func htmlOnlyWithoutHTML() throws {
        let output = try Renderer.entries(
            [entry("apple", html: nil)], term: "apple", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .only)

        #expect(output.exitCode == 0)
        #expect(output.standardOutput.contains("=== apple ==="))
        #expect(!output.standardOutput.contains("definition"))
    }

    @Test(
        "each mode emits exactly the representations it names",
        arguments: [
            (HTMLMode.none, true, false),
            (HTMLMode.included, true, true),
            (HTMLMode.only, false, true),
        ])
    func modesEmitWhatTheyName(mode: HTMLMode, text: Bool, html: Bool) throws {
        let output = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: true, headwordOnly: false, htmlMode: mode)

        let payload = try #require(try json(output) as? [String: Any])
        let entries = try #require(payload["entries"] as? [[String: Any]])
        #expect((entries[0]["text"] != nil) == text)
        #expect((entries[0]["html"] != nil) == html)
    }

    // MARK: The empty result, which differs by mode on purpose

    @Test("no entries is an error in text mode, reported on stderr")
    func emptyIsAnErrorInTextMode() throws {
        let output = try Renderer.entries(
            [], term: "zzznotaword", dictionary: "NOAD",
            json: false, headwordOnly: false, htmlMode: .none)

        #expect(output.exitCode == 1)
        #expect(output.standardOutput.isEmpty, "a diagnostic must never reach stdout")
        #expect(output.standardError.contains("No entry for 'zzznotaword' in NOAD."))
    }

    @Test("no entries is a success with an empty list in JSON mode")
    func emptyIsSuccessInJSONMode() throws {
        let output = try Renderer.entries(
            [], term: "zzznotaword", dictionary: "NOAD",
            json: true, headwordOnly: false, htmlMode: .none)

        #expect(output.exitCode == 0)
        #expect(output.standardError.isEmpty)
        let payload = try #require(try json(output) as? [String: Any])
        #expect(payload["term"] as? String == "zzznotaword")
        #expect(payload["dictionary"] as? String == "NOAD")
        #expect((payload["entries"] as? [Any])?.isEmpty == true)
    }

    // MARK: JSON output

    @Test("JSON carries the term, the dictionary used, and the entries")
    func jsonEnvelope() throws {
        let output = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "Oxford Dictionary of English",
            json: true, headwordOnly: false, htmlMode: .none)

        let payload = try #require(try json(output) as? [String: Any])
        #expect(Set(payload.keys) == ["term", "dictionary", "entries"])
        #expect(payload["dictionary"] as? String == "Oxford Dictionary of English")

        let entries = try #require(payload["entries"] as? [[String: Any]])
        #expect(entries.count == 1)
        #expect(entries[0]["headword"] as? String == "apple")
    }

    @Test("JSON keeps headword and title distinct")
    func jsonSeparatesHeadwordFromTitle() throws {
        let output = try Renderer.entries(
            [entry("upset the applecart", title: "apple")], term: "upset the applecart",
            dictionary: "NOAD", json: true, headwordOnly: false, htmlMode: .none)

        let payload = try #require(try json(output) as? [String: Any])
        let entries = try #require(payload["entries"] as? [[String: Any]])
        #expect(entries[0]["headword"] as? String == "upset the applecart")
        #expect(entries[0]["title"] as? String == "apple")
    }

    @Test("JSON omits the html key unless --html is given")
    func jsonHTMLIsOptional() throws {
        let without = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: true, headwordOnly: false, htmlMode: .none)
        #expect(!without.standardOutput.contains("\"html\""))

        let with = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: true, headwordOnly: false, htmlMode: .included)
        #expect(with.standardOutput.contains("\"html\""))
    }

    @Test("JSON with --headword-only is a flat array of names")
    func jsonHeadwordOnly() throws {
        let output = try Renderer.entries(
            [entry("set"), entry("Set", title: "Seth")], term: "set", dictionary: "NOAD",
            json: true, headwordOnly: true, htmlMode: .none)

        #expect(try json(output) as? [String] == ["set", "Seth"])
    }

    @Test("every JSON mode emits parseable JSON on stdout", arguments: [true, false])
    func jsonAlwaysParses(headwordOnly: Bool) throws {
        let output = try Renderer.entries(
            [entry("apple")], term: "apple", dictionary: "NOAD",
            json: true, headwordOnly: headwordOnly, htmlMode: .none)
        #expect(throws: Never.self) { try json(output) }
    }

    // MARK: --is-defined

    @Test("--is-defined prints Yes or No and always succeeds", arguments: [true, false])
    func definedText(defined: Bool) throws {
        let output = try Renderer.defined(
            term: "apple", dictionary: "NOAD", defined: defined, json: false)

        #expect(output.standardOutput == (defined ? "Yes\n" : "No\n"))
        #expect(output.exitCode == 0, "a defined/undefined answer is not a failure")
        #expect(output.standardError.isEmpty)
    }

    @Test("--is-defined --json reports a boolean")
    func definedJSON() throws {
        let output = try Renderer.defined(
            term: "apple", dictionary: "NOAD", defined: false, json: true)

        let payload = try #require(try json(output) as? [String: Any])
        #expect(payload["defined"] as? Bool == false)
        #expect(payload["term"] as? String == "apple")
        #expect(output.exitCode == 0)
    }

    // MARK: Listing

    @Test("the listing counts dictionaries and pluralises aliases correctly")
    func listing() throws {
        let output = try Renderer.list(
            [
                DictionaryListing(name: "A", shortName: "a", aliases: ["one"]),
                DictionaryListing(name: "B", shortName: nil, aliases: ["two", "three"]),
            ], json: false)

        #expect(output.standardOutput.contains("Available dictionaries (2):"))
        #expect(output.standardOutput.contains("alias: 'one'"))
        #expect(output.standardOutput.contains("aliases: 'two', 'three'"))
        #expect(output.standardOutput.contains("short name: a"))
        #expect(output.exitCode == 0)
    }

    @Test("an empty listing explains how to install dictionaries instead of failing")
    func emptyListing() throws {
        let output = try Renderer.list([], json: false)

        #expect(output.exitCode == 0, "no dictionaries is not an error")
        #expect(output.standardOutput.contains("No dictionaries are installed."))
        #expect(output.standardOutput.contains("System Settings"))
    }

    @Test("the JSON listing exposes name, shortName, and every alias")
    func listingJSON() throws {
        let output = try Renderer.list(
            [DictionaryListing(name: "A", shortName: nil, aliases: ["one", "two"])], json: true)

        let payload = try #require(try json(output) as? [[String: Any]])
        #expect(payload[0]["name"] as? String == "A")
        #expect(payload[0]["aliases"] as? [String] == ["one", "two"])
    }

    // MARK: Failures

    @Test("an unavailable dictionary explains how to find the right name")
    func unavailableDictionary() {
        let output = Renderer.dictionaryUnavailable("nope")

        #expect(output.exitCode == 1)
        #expect(output.standardOutput.isEmpty)
        #expect(output.standardError.contains("Dictionary not available: nope"))
        #expect(output.standardError.contains("--list"))
    }

    @Test("unavailable private APIs fail rather than reporting an empty dictionary set")
    func unavailablePrivateAPIs() {
        let output = Renderer.privateAPIsUnavailable()

        #expect(output.exitCode == 1)
        #expect(output.standardOutput.isEmpty)
        #expect(output.standardError.contains("unavailable"))
    }

    @Test("a failure never writes to stdout")
    func failuresStayOffStandardOutput() throws {
        let failures = [
            Renderer.dictionaryUnavailable("nope"),
            Renderer.privateAPIsUnavailable(),
            try Renderer.entries(
                [], term: "x", dictionary: "NOAD",
                json: false, headwordOnly: false, htmlMode: .none),
        ]
        for output in failures {
            #expect(output.exitCode != 0)
            #expect(output.standardOutput.isEmpty)
            #expect(!output.standardError.isEmpty)
        }
    }
}
