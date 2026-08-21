import ArgumentParser
import DictionaryKit
import Testing

@testable import DictionaryKitCLI

/// Tests for argument parsing, flag validation, and dictionary resolution.
@Suite("CLI arguments")
struct ArgumentTests {

    /// Parses and validates, the way ArgumentParser does for a real invocation.
    private func parse(_ arguments: [String]) throws -> DictionaryKitCommand {
        var command = try DictionaryKitCommand.parse(arguments)
        try command.validate()
        return command
    }

    // MARK: Accepted forms

    @Test("a bare search uses the default dictionary")
    func bareSearch() throws {
        let command = try parse(["--search", "apple"])
        #expect(command.search == "apple")
        #expect(command.dictionary == nil)
        #expect(!command.json)
    }

    @Test(
        "short and long spellings agree",
        arguments: [
            (["-s", "apple"], ["--search", "apple"]),
            (["-l"], ["--list"]),
            (["-s", "x", "-d", "oxford"], ["--search", "x", "--dictionary", "oxford"]),
            (["-s", "x", "-H"], ["--search", "x", "--headword-only"]),
        ])
    func shortAndLongForms(short: [String], long: [String]) throws {
        let a = try parse(short)
        let b = try parse(long)
        #expect(a.search == b.search)
        #expect(a.list == b.list)
        #expect(a.dictionary == b.dictionary)
        #expect(a.headwordOnly == b.headwordOnly)
    }

    @Test(
        "--json combines with every mode",
        arguments: [
            ["--list", "--json"],
            ["-s", "x", "--json"],
            ["-s", "x", "--json", "--html"],
            ["-s", "x", "--json", "--is-defined"],
            ["-s", "x", "--json", "-H"],
        ])
    func jsonCombinesFreely(arguments: [String]) throws {
        let command = try parse(arguments)
        #expect(command.json)
    }

    // MARK: Rejected forms

    @Test("a run with no arguments asks for a term rather than doing nothing")
    func noArguments() {
        #expect(throws: (any Error).self) { try parse([]) }
    }

    @Test(
        "--list rejects every flag that would be silently ignored",
        arguments: [
            ["--list", "--search", "apple"],
            ["--list", "--is-defined"],
            ["--list", "--headword-only"],
            ["--list", "--html"],
        ])
    func listConflicts(arguments: [String]) {
        #expect(throws: (any Error).self) { try parse(arguments) }
    }

    @Test("--is-defined and --headword-only are mutually exclusive")
    func definedAndHeadwordOnly() {
        #expect(throws: (any Error).self) { try parse(["-s", "x", "--is-defined", "-H"]) }
    }

    @Test(
        "an HTML flag is rejected where it would have no effect",
        arguments: [
            ["-s", "x", "--html", "--is-defined"],
            ["-s", "x", "--html", "-H"],
            ["-s", "x", "--html-only", "--is-defined"],
            ["-s", "x", "--html-only", "-H"],
            ["--list", "--html-only"],
        ])
    func htmlWhereItCannotApply(arguments: [String]) {
        #expect(throws: (any Error).self) { try parse(arguments) }
    }

    @Test("--html and --html-only are mutually exclusive")
    func htmlAndHTMLOnly() {
        #expect(throws: (any Error).self) { try parse(["-s", "x", "--html", "--html-only"]) }
    }

    @Test(
        "the HTML flags select a mode",
        arguments: [
            ([], HTMLMode.none),
            (["--html"], HTMLMode.included),
            (["--html-only"], HTMLMode.only),
        ])
    func htmlModeSelection(flags: [String], expected: HTMLMode) throws {
        let command = try parse(["-s", "apple"] + flags)
        #expect(command.htmlMode == expected)
    }

    @Test("validation messages name the flags involved")
    func validationMessagesAreSpecific() {
        do {
            _ = try parse(["--list", "--search", "apple"])
            Issue.record("expected a validation error")
        } catch {
            let message = "\(error)"
            #expect(message.contains("--list"))
            #expect(message.contains("--search"))
        }
    }

    // MARK: Dictionary resolution

    @Test("an alias resolves to its full dictionary name")
    func aliasResolves() {
        #expect(resolveDictionary("oxford") == DCSOxfordDictionaryOfEnglish)
        #expect(resolveDictionary("OXFORD") == DCSOxfordDictionaryOfEnglish)
        #expect(resolveDictionary("  oxford  ") == DCSOxfordDictionaryOfEnglish)
    }

    @Test("a full name is passed through untouched")
    func fullNamePassesThrough() {
        #expect(resolveDictionary(DCSOxfordDictionaryOfEnglish) == DCSOxfordDictionaryOfEnglish)
        #expect(resolveDictionary("Some Dictionary") == "Some Dictionary")
    }

    @Test("absent or blank input means the default dictionary")
    func blankMeansDefault() {
        #expect(resolveDictionary(nil) == nil)
        #expect(resolveDictionary("") == nil)
        #expect(resolveDictionary("   ") == nil)
    }

    // MARK: Configuration

    @Test("the command is named for the binary and reports the package version")
    func configuration() {
        #expect(DictionaryKitCommand.configuration.commandName == "dictionarykit")
        #expect(DictionaryKitCommand.configuration.version == DictionaryKitVersion.current)
    }
}
