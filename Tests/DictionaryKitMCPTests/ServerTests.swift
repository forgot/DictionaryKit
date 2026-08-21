import Foundation
import MCP
import Testing

@testable import DictionaryKit
@testable import DictionaryKitMCP

private let apisAvailable = DictionaryService.canAccessPrivateAPIs()

private func installedNames() async throws -> Set<String> {
    guard apisAvailable else { return [] }
    return Set(try await DictionaryService.shared.availableDictionaries().map(\.name))
}

/// Decodes the JSON payload a tool returned in its first text content block.
private func payload(_ content: [Tool.Content]) throws -> [String: Any] {
    guard case .text(let string, _, _) = try #require(content.first) else {
        Issue.record("Expected a text content block")
        return [:]
    }
    let object = try JSONSerialization.jsonObject(with: Data(string.utf8))
    return object as? [String: Any] ?? [:]
}

@Suite("Tool definitions")
struct ToolDefinitionTests {

    @Test("exposes the documented tool set")
    func toolSet() {
        let names = Set(getToolDefinitions().map(\.name))
        #expect(
            names == [
                "list_dictionaries", "search_term", "get_dictionary_info",
                "batch_search", "get_current_dictionary", "set_dictionary",
            ])
    }

    /// `dictionary` being required is what made `set_dictionary` pointless: a client could
    /// never omit it, so the session dictionary was never consulted.
    @Test("dictionary is optional wherever a session default applies")
    func dictionaryIsOptional() throws {
        for name in ["search_term", "get_dictionary_info"] {
            let tool = try #require(getToolDefinitions().first { $0.name == name })
            guard case .object(let schema) = tool.inputSchema,
                case .array(let required)? = schema["required"]
            else {
                Issue.record("\(name) has no required list")
                continue
            }
            let requiredNames = required.compactMap(\.stringValue)
            #expect(!requiredNames.contains("dictionary"), "\(name) still requires 'dictionary'")
        }
    }

    @Test("only set_dictionary is marked as mutating")
    func readOnlyHints() throws {
        for tool in getToolDefinitions() {
            let expected = tool.name != "set_dictionary"
            #expect(
                tool.annotations.readOnlyHint == expected,
                "\(tool.name) has the wrong readOnlyHint")
        }
    }

    @Test("every tool documents its parameters")
    func toolsHaveDescriptions() {
        for tool in getToolDefinitions() {
            #expect(tool.description?.isEmpty == false, "\(tool.name) has no description")
        }
    }
}

@Suite("Session dictionary")
struct DictionaryContextTests {

    @Test("starts at the New Oxford American Dictionary")
    func startsAtDefault() async {
        let context = DictionaryContext()
        #expect(await context.current() == DCSNewOxfordAmericanDictionaryName)
    }

    @Test("an explicit argument wins over the session dictionary")
    func argumentWinsOverSession() async {
        let context = DictionaryContext(defaultDictionary: "Session Dictionary")
        let resolved = await resolveDictionaryName(argument: "oxford", context: context)
        #expect(resolved == DCSOxfordDictionaryOfEnglish, "an alias argument should resolve")

        let fallback = await resolveDictionaryName(argument: nil, context: context)
        #expect(fallback == "Session Dictionary")

        let blank = await resolveDictionaryName(argument: "   ", context: context)
        #expect(blank == "Session Dictionary", "a blank argument should not override the session")
    }

    @Test("unknown names are passed through as full dictionary names")
    func unknownNamesPassThrough() async {
        let context = DictionaryContext()
        let resolved = await resolveDictionaryName(
            argument: "Some Dictionary Nobody Aliased", context: context)
        #expect(resolved == "Some Dictionary Nobody Aliased")
    }

    @Test(
        "set_dictionary accepts an alias",
        .enabled(if: apisAvailable, "Private DictionaryServices APIs unavailable."))
    func setCurrentAcceptsAlias() async throws {
        guard try await installedNames().contains(DCSOxfordDictionaryOfEnglish) else { return }
        let context = DictionaryContext()
        // Used to fail: validation compared the raw input against full names only.
        let stored = try await context.setCurrent("oxford")
        #expect(stored == DCSOxfordDictionaryOfEnglish)
        #expect(await context.current() == DCSOxfordDictionaryOfEnglish)
    }

    @Test(
        "set_dictionary rejects a dictionary that isn't installed",
        .enabled(if: apisAvailable, "Private DictionaryServices APIs unavailable."))
    func setCurrentRejectsUnknown() async throws {
        let context = DictionaryContext()
        await #expect(throws: DictionaryKitError.self) {
            try await context.setCurrent("No Such Dictionary 12345")
        }
        #expect(
            await context.current() == DCSNewOxfordAmericanDictionaryName,
            "a failed set must leave the session dictionary untouched")
    }
}

@Suite(
    "Tool handlers over a live server",
    .enabled(if: apisAvailable, "Private DictionaryServices APIs unavailable."))
struct ToolHandlerTests {

    /// Runs a client and server against each other over the SDK's in-memory transport, which
    /// exercises the real registration and dispatch path rather than reimplementing it.
    private func withClient<T>(
        context: DictionaryContext = DictionaryContext(),
        _ body: (Client) async throws -> T
    ) async throws -> T {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = await createServer(context: context)
        try await server.start(transport: serverTransport)
        defer { Task { await server.stop() } }

        let client = Client(name: "tests", version: "1")
        try await client.connect(transport: clientTransport)
        defer { Task { await client.disconnect() } }

        return try await body(client)
    }

    @Test("initializes and lists tools")
    func listsTools() async throws {
        let names = try await withClient { client in
            try await client.listTools().tools.map(\.name)
        }
        #expect(names.contains("search_term"))
        #expect(names.count == 6)
    }

    /// The headline bug: the schema advertised aliases and the handler passed the raw string
    /// straight through, so every alias returned "Dictionary 'oxford' not found".
    @Test("search_term accepts an alias")
    func searchAcceptsAlias() async throws {
        guard try await installedNames().contains(DCSOxfordDictionaryOfEnglish) else { return }
        let result = try await withClient { client in
            try await client.callTool(
                name: "search_term", arguments: ["term": "apple", "dictionary": "oxford"])
        }
        #expect(result.isError != true)
        let body = try payload(result.content)
        #expect(body["dictionary"] as? String == DCSOxfordDictionaryOfEnglish)
        #expect((body["entries"] as? [Any])?.isEmpty == false)
    }

    @Test("search_term falls back to the session dictionary and names what it used")
    func searchUsesSessionDictionary() async throws {
        let installed = try await installedNames()
        guard installed.contains(DCSNewOxfordAmericanDictionaryName),
            installed.contains(DCSOxfordDictionaryOfEnglish)
        else { return }

        let context = DictionaryContext()
        try await withClient(context: context) { client in
            var result = try await client.callTool(
                name: "search_term", arguments: ["term": "apple"])
            var body = try payload(result.content)
            #expect(body["dictionary"] as? String == DCSNewOxfordAmericanDictionaryName)

            _ = try await client.callTool(
                name: "set_dictionary", arguments: ["dictionary": "oxford"])

            result = try await client.callTool(name: "search_term", arguments: ["term": "apple"])
            body = try payload(result.content)
            #expect(
                body["dictionary"] as? String == DCSOxfordDictionaryOfEnglish,
                "set_dictionary must change what an argument-less search uses")
        }
    }

    @Test("search_term omits HTML unless asked")
    func searchOmitsHTMLByDefault() async throws {
        guard try await installedNames().contains(DCSNewOxfordAmericanDictionaryName) else {
            return
        }
        try await withClient { client in
            let plain = try await client.callTool(name: "search_term", arguments: ["term": "apple"])
            let plainBody = try payload(plain.content)
            let firstPlain = try #require((plainBody["entries"] as? [[String: Any]])?.first)
            #expect(firstPlain["html"] == nil)

            let rich = try await client.callTool(
                name: "search_term", arguments: ["term": "apple", "include_html": true])
            let richBody = try payload(rich.content)
            let firstRich = try #require((richBody["entries"] as? [[String: Any]])?.first)
            #expect(firstRich["html"] != nil)
        }
    }

    @Test("a term with no definition is an empty result, not an error")
    func unknownTermIsNotAnError() async throws {
        guard try await installedNames().contains(DCSNewOxfordAmericanDictionaryName) else {
            return
        }
        let result = try await withClient { client in
            try await client.callTool(name: "search_term", arguments: ["term": "xyzabc123notaword"])
        }
        #expect(result.isError != true)
        let body = try payload(result.content)
        #expect((body["entries"] as? [Any])?.isEmpty == true)
    }

    @Test("an uninstalled dictionary is reported as an error")
    func unknownDictionaryIsAnError() async throws {
        let result = try await withClient { client in
            try await client.callTool(
                name: "search_term",
                arguments: ["term": "apple", "dictionary": "No Such Dictionary 12345"])
        }
        #expect(result.isError == true)
    }

    @Test("batch_search reports per-dictionary results")
    func batchSearch() async throws {
        guard try await installedNames().contains(DCSOxfordDictionaryOfEnglish) else { return }
        let result = try await withClient { client in
            try await client.callTool(
                name: "batch_search",
                arguments: [
                    "term": "apple", "dictionaries": ["oxford", "No Such Dictionary 12345"],
                ])
        }
        let body = try payload(result.content)
        let results = try #require(body["results"] as? [[String: Any]])
        #expect(results.count == 2)
        #expect(results[0]["dictionary"] as? String == DCSOxfordDictionaryOfEnglish)
        // A dictionary that failed must say so, or an empty list reads as "no definition".
        #expect(results[1]["error"] != nil)
    }
}

@Suite(
    "Resources",
    .enabled(if: apisAvailable, "Private DictionaryServices APIs unavailable."))
struct ResourceTests {

    @Test("declares both resources")
    func resourceDefinitions() {
        #expect(
            Set(getResourceDefinitions().map(\.uri)) == [
                "dictionary://list", "dictionary://aliases",
            ])
    }

    /// This resource used to be a hardcoded table of 16 invented names such as
    /// "French-English Dictionary", none of which matched any installed dictionary. A client
    /// that read it and fed the values back into `search_term` failed every time.
    @Test("dictionary://aliases matches DictionaryAlias, and installed flags are truthful")
    func aliasesResourceIsGenerated() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        let server = await createServer()
        try await server.start(transport: serverTransport)
        defer { Task { await server.stop() } }
        let client = Client(name: "tests", version: "1")
        try await client.connect(transport: clientTransport)
        defer { Task { await client.disconnect() } }

        let contents = try await client.readResource(uri: "dictionary://aliases")
        let first = try #require(contents.first)
        let json = try #require(first.text, "Expected text content")
        let entries = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])

        #expect(entries.count == DictionaryAlias.allCases.count)

        let installed = try await installedNames()
        let expected = Dictionary(
            uniqueKeysWithValues: DictionaryAlias.allCases.map { ($0.rawValue, $0.dictionaryName) })
        for entry in entries {
            let alias = try #require(entry["alias"] as? String)
            let dictionary = try #require(entry["dictionary"] as? String)
            #expect(
                dictionary == expected[alias], "alias '\(alias)' does not match DictionaryAlias")
            #expect(
                entry["installed"] as? Bool == installed.contains(dictionary),
                "alias '\(alias)' reports the wrong installed state")
        }
    }
}
