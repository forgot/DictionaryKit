import DictionaryKit
import Foundation
import Testing

/// The CLI's observable contract: exit codes, which stream output lands on, and the JSON shape.
///
/// This is the surface other programs bind to — the Python wrapper in a sibling project parses
/// stdout and branches on the exit code — so it is pinned here rather than left to a README.
@Suite(
    "CLI contract",
    .enabled(if: CLI.isAvailable, "The dictionarykit binary was not built for this test run."))
struct CLIContractTests {

    private static let installed = CLI.hasDictionaries

    private func json(_ result: CLIResult) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8))
    }

    // MARK: Always available, no dictionaries required

    @Test("--version reports the package version on stdout")
    func version() async throws {
        let result = try await CLI.run("--version")

        #expect(result.exitCode == 0)
        #expect(
            result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                == DictionaryKitVersion.current)
        #expect(result.standardError.isEmpty)
    }

    @Test("--help succeeds and documents every flag on stdout")
    func help() async throws {
        let result = try await CLI.run("--help")

        #expect(result.exitCode == 0)
        #expect(result.standardError.isEmpty)
        for flag in [
            "--list", "--dictionary", "--search", "--html", "--html-only", "--is-defined",
            "--headword-only", "--json",
        ] {
            #expect(result.standardOutput.contains(flag), "--help omits \(flag)")
        }
    }

    @Test(
        "a usage error exits 64 with an empty stdout",
        arguments: [
            [],
            ["--list", "--search", "apple"],
            ["-s", "x", "--is-defined", "-H"],
            ["-s", "x", "--html", "-H"],
            ["--list", "--html"],
        ])
    func usageErrors(arguments: [String]) async throws {
        let result = try await CLI.run(arguments)

        // 64 is EX_USAGE, what ArgumentParser exits with for a validation failure. Callers
        // use it to tell "you invoked me wrong" apart from "that word isn't defined".
        #expect(result.exitCode == 64)
        #expect(result.standardOutput.isEmpty, "usage errors must not pollute stdout")
        #expect(result.standardError.contains("Error:"))
    }

    // MARK: Requiring installed dictionaries

    @Test(
        "a found term exits 0 and writes only to stdout",
        .enabled(if: installed, "No dictionaries installed."))
    func foundTerm() async throws {
        let result = try await CLI.run("-s", "apple")

        #expect(result.exitCode == 0)
        #expect(result.standardError.isEmpty)
        #expect(result.standardOutput.contains("=== "))
    }

    @Test(
        "an unknown term exits 1 with the message on stderr and nothing on stdout",
        .enabled(if: installed, "No dictionaries installed."))
    func unknownTerm() async throws {
        let result = try await CLI.run("-s", "zzznotaword")

        #expect(result.exitCode == 1)
        #expect(result.standardOutput.isEmpty, "the not-found message must not reach stdout")
        #expect(result.standardError.contains("No entry for 'zzznotaword'"))
    }

    @Test(
        "--headword-only prints bare headwords, and nothing at all when there is no match",
        .enabled(if: installed, "No dictionaries installed."))
    func headwordOnly() async throws {
        let found = try await CLI.run("-s", "apple", "-H")
        #expect(found.exitCode == 0)
        #expect(!found.standardOutput.contains("==="))
        #expect(found.standardOutput.contains("apple"))

        let missing = try await CLI.run("-s", "zzznotaword", "-H")
        #expect(missing.exitCode == 1)
        #expect(missing.standardOutput.isEmpty)
    }

    @Test(
        "--is-defined answers Yes or No and succeeds either way",
        .enabled(if: installed, "No dictionaries installed."))
    func isDefined() async throws {
        let yes = try await CLI.run("-s", "apple", "--is-defined")
        #expect(yes.exitCode == 0)
        #expect(yes.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "Yes")

        // Exit 0 for "No" is deliberate and load-bearing: an undefined word is a valid answer,
        // not a failure, and callers read the word rather than the status here.
        let no = try await CLI.run("-s", "zzznotaword", "--is-defined")
        #expect(no.exitCode == 0)
        #expect(no.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "No")
        #expect(no.standardError.isEmpty)
    }

    @Test(
        "--json emits the documented envelope",
        .enabled(if: installed, "No dictionaries installed."))
    func jsonEnvelope() async throws {
        let result = try await CLI.run("-s", "apple", "--json")

        #expect(result.exitCode == 0)
        #expect(result.standardError.isEmpty)
        let payload = try #require(try json(result) as? [String: Any])
        #expect(Set(payload.keys) == ["term", "dictionary", "entries"])
        #expect(payload["term"] as? String == "apple")
        #expect(payload["dictionary"] as? String == DCSNewOxfordAmericanDictionaryName)
        #expect((payload["entries"] as? [Any])?.isEmpty == false)
    }

    @Test(
        "an unknown term in --json mode is an empty list, not an error",
        .enabled(if: installed, "No dictionaries installed."))
    func jsonUnknownTerm() async throws {
        let result = try await CLI.run("-s", "zzznotaword", "--json")

        #expect(result.exitCode == 0, "JSON consumers get a parseable document, not a failure")
        #expect(result.standardError.isEmpty)
        let payload = try #require(try json(result) as? [String: Any])
        #expect((payload["entries"] as? [Any])?.isEmpty == true)
    }

    @Test(
        "--json withholds html until it is asked for",
        .enabled(if: installed, "No dictionaries installed."))
    func jsonHTML() async throws {
        let without = try await CLI.run("-s", "apple", "--json")
        #expect(!without.standardOutput.contains("\"html\""))

        let with = try await CLI.run("-s", "apple", "--json", "--html")
        #expect(with.standardOutput.contains("\"html\""))
        // HTML is far larger than the text; this also exercises draining a pipe past its buffer.
        #expect(with.standardOutput.count > without.standardOutput.count)
        #expect(with.exitCode == 0)
    }

    @Test(
        "--html-only emits markup instead of the text",
        .enabled(if: installed, "No dictionaries installed."))
    func htmlOnly() async throws {
        let text = try await CLI.run("-s", "apple")
        let htmlOnly = try await CLI.run("-s", "apple", "--html-only")

        #expect(htmlOnly.exitCode == 0)
        #expect(htmlOnly.standardError.isEmpty)
        #expect(htmlOnly.standardOutput.contains("<"), "expected markup")
        #expect(!htmlOnly.standardOutput.contains("-- HTML --"))
        #expect(
            htmlOnly.standardOutput != text.standardOutput,
            "--html-only should not produce the same output as the default")
    }

    @Test(
        "--html-only drops the text key from JSON but keeps html",
        .enabled(if: installed, "No dictionaries installed."))
    func htmlOnlyJSON() async throws {
        let result = try await CLI.run("-s", "apple", "--html-only", "--json")

        #expect(result.exitCode == 0)
        let payload = try #require(try json(result) as? [String: Any])
        let entries = try #require(payload["entries"] as? [[String: Any]])
        let first = try #require(entries.first)
        #expect(first["html"] is String)
        #expect(first["text"] == nil)
    }

    @Test("--html and --html-only together are a usage error")
    func htmlFlagsConflict() async throws {
        let result = try await CLI.run("-s", "apple", "--html", "--html-only")

        #expect(result.exitCode == 64)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("--html-only"))
    }

    @Test(
        "an alias selects a dictionary and the response names the one used",
        .enabled(if: installed, "No dictionaries installed."))
    func aliasResolution() async throws {
        let result = try await CLI.run("-s", "apple", "-d", "oxford", "--json")
        try withKnownIssue("the Oxford Dictionary of English is not installed on this Mac") {
            #expect(result.exitCode == 0)
            let payload = try #require(try json(result) as? [String: Any])
            #expect(payload["dictionary"] as? String == DCSOxfordDictionaryOfEnglish)
        } when: {
            result.standardError.contains("Dictionary not available")
        }
    }

    @Test(
        "an unknown dictionary exits 1 and points at --list",
        .enabled(if: installed, "No dictionaries installed."))
    func unknownDictionary() async throws {
        let result = try await CLI.run("-s", "apple", "-d", "no-such-dictionary")

        #expect(result.exitCode == 1)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("Dictionary not available"))
        #expect(result.standardError.contains("--list"))
    }

    @Test(
        "--list --json describes each dictionary with its aliases",
        .enabled(if: installed, "No dictionaries installed."))
    func listJSON() async throws {
        let result = try await CLI.run("--list", "--json")

        #expect(result.exitCode == 0)
        let listings = try #require(try json(result) as? [[String: Any]])
        #expect(!listings.isEmpty)
        for listing in listings {
            #expect(listing["name"] is String)
            #expect(listing["aliases"] is [Any])
        }
    }

    @Test("--list survives having no dictionaries installed")
    func listAlwaysSucceeds() async throws {
        let result = try await CLI.run("--list")

        #expect(result.exitCode == 0, "an empty dictionary set is not a CLI failure")
        #expect(!result.standardOutput.isEmpty)
    }

    // MARK: Regressions

    @Test(
        "a term of astral-plane characters is handled rather than crashing the process",
        .enabled(if: installed, "No dictionaries installed."))
    func astralPlaneTerm() async throws {
        // These used to trap: a UTF-16 range from DCSGetTermRangeInString was applied with a
        // Character-based index, killing the process with a signal instead of throwing.
        for term in ["🍎🍏notaword", "🇯🇵", "e\u{301}\u{20DD}"] {
            let result = try await CLI.run("-s", term)
            #expect(!result.crashed, "'\(term)' crashed the process")
            #expect(result.exitCode == 0 || result.exitCode == 1)
        }
    }

    @Test(
        "no mode ever writes a diagnostic to stdout",
        .enabled(if: installed, "No dictionaries installed."),
        arguments: [
            ["-s", "zzznotaword"],
            ["-s", "zzznotaword", "-H"],
            ["-s", "apple", "-d", "no-such-dictionary"],
            ["-s", "apple", "-d", "no-such-dictionary", "--json"],
        ])
    func diagnosticsNeverOnStandardOutput(arguments: [String]) async throws {
        let result = try await CLI.run(arguments)

        #expect(result.exitCode != 0)
        #expect(
            result.standardOutput.isEmpty,
            "\(arguments) wrote a diagnostic to stdout, which would corrupt a pipeline")
    }
}
