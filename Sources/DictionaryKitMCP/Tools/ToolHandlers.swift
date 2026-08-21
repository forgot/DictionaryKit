import DictionaryKit
import Foundation
import Logging
import MCP

// MARK: - Response payloads

/// Every lookup response names the dictionary it actually used.
///
/// Without this, a client that omitted `dictionary` — or that called `set_dictionary` many
/// turns earlier — has no way to tell which dictionary answered, and silently-French results
/// for an English word look like a bug in the dictionary rather than stale session state.
private struct SearchResponse: Encodable {
    let dictionary: String
    let term: String
    let entries: [Entry]

    struct Entry: Encodable {
        let headword: String
        let title: String?
        let text: String?
        let html: String?
    }
}

private struct DictionaryInfo: Encodable {
    let name: String
    let shortName: String?
    let aliases: [String]
}

private struct BatchResponse: Encodable {
    let term: String
    let results: [Result]

    struct Result: Encodable {
        let dictionary: String
        let requested: String
        let entries: [SearchResponse.Entry]
        let error: String?
    }
}

private struct CurrentDictionaryResponse: Encodable {
    let dictionary: String
}

private struct SetDictionaryResponse: Encodable {
    let dictionary: String
    let requested: String
    let status: String
}

private extension SearchResponse.Entry {
    init(_ entry: DictionaryEntry, includeHTML: Bool) {
        self.init(
            headword: entry.headword,
            title: entry.title,
            text: entry.text,
            html: includeHTML ? entry.html : nil)
    }
}

// MARK: - Registration

/// Registers tool handlers with the server.
func registerToolHandlers(server: Server, logger: Logger, context: DictionaryContext) async {
    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: getToolDefinitions())
    }

    await server.withMethodHandler(CallTool.self) { params in
        logger.info("Tool called", metadata: ["tool": .string(params.name)])

        do {
            switch params.name {
            case "list_dictionaries":
                return try await handleListDictionaries()
            case "search_term":
                return try await handleSearchTerm(params: params, context: context)
            case "get_dictionary_info":
                return try await handleGetDictionaryInfo(params: params, context: context)
            case "batch_search":
                return try await handleBatchSearch(params: params)
            case "get_current_dictionary":
                return try await handleGetCurrentDictionary(context: context)
            case "set_dictionary":
                return try await handleSetDictionary(params: params, context: context)
            default:
                throw MCPError.invalidParams("Unknown tool: \(params.name)")
            }
        } catch let error as MCPError {
            logger.warning(
                "Tool failed",
                metadata: ["tool": .string(params.name), "error": .string("\(error)")])
            return .init(content: [.text("\(error)")], isError: true)
        } catch let error as DictionaryKitError {
            // Interpolate rather than using localizedDescription: DictionaryKitError conforms
            // to LocalizedError so both work, but interpolation cannot regress to Foundation's
            // generic "operation couldn't be completed" text.
            logger.warning(
                "Tool failed",
                metadata: ["tool": .string(params.name), "error": .string("\(error)")])
            return .init(content: [.text("\(error)")], isError: true)
        } catch {
            logger.error(
                "Unexpected tool error",
                metadata: ["tool": .string(params.name), "error": .string("\(error)")])
            return .init(content: [.text("Unexpected error: \(error)")], isError: true)
        }
    }

    logger.info("Tool handlers registered")
}

// MARK: - Handlers

private func handleListDictionaries() async throws -> CallTool.Result {
    let dictionaries = try await DictionaryService.shared.availableDictionaries()
    let items = dictionaries.map {
        DictionaryInfo(
            name: $0.name,
            shortName: $0.shortName,
            aliases: DictionaryAlias.aliases(for: $0.name).map(\.rawValue))
    }
    return .init(content: [.text(try encodeToJSON(items))], isError: false)
}

private func handleSearchTerm(
    params: CallTool.Parameters,
    context: DictionaryContext
) async throws -> CallTool.Result {
    guard let term = params.arguments?["term"]?.stringValue, !term.isEmpty else {
        throw MCPError.invalidParams("Missing required parameter: 'term'")
    }

    let requested = params.arguments?["dictionary"]?.stringValue
    let name = await resolveDictionaryName(argument: requested, context: context)
    let includeHTML = params.arguments?["include_html"]?.boolValue ?? false

    do {
        let entries = try await DictionaryService.shared.entries(matching: term, in: name)
        let response = SearchResponse(
            dictionary: name,
            term: term,
            entries: entries.map { SearchResponse.Entry($0, includeHTML: includeHTML) })
        return .init(content: [.text(try encodeToJSON(response))], isError: false)
    } catch DictionaryKitError.termNotFound {
        // No definition is an ordinary outcome, not an error.
        let response = SearchResponse(dictionary: name, term: term, entries: [])
        return .init(content: [.text(try encodeToJSON(response))], isError: false)
    } catch DictionaryKitError.dictionaryUnavailable {
        throw MCPError.invalidParams(
            "Dictionary '\(requested ?? name)' is not installed. "
                + "Call list_dictionaries to see what is available.")
    }
}

private func handleGetDictionaryInfo(
    params: CallTool.Parameters,
    context: DictionaryContext
) async throws -> CallTool.Result {
    let requested = params.arguments?["dictionary"]?.stringValue
    let name = await resolveDictionaryName(argument: requested, context: context)

    do {
        let descriptor = try await DictionaryService.shared.dictionary(named: name)
        let info = DictionaryInfo(
            name: descriptor.name,
            shortName: descriptor.shortName,
            aliases: DictionaryAlias.aliases(for: descriptor.name).map(\.rawValue))
        return .init(content: [.text(try encodeToJSON(info))], isError: false)
    } catch DictionaryKitError.dictionaryUnavailable {
        throw MCPError.invalidParams(
            "Dictionary '\(requested ?? name)' is not installed. "
                + "Call list_dictionaries to see what is available.")
    }
}

private func handleBatchSearch(params: CallTool.Parameters) async throws -> CallTool.Result {
    guard let term = params.arguments?["term"]?.stringValue, !term.isEmpty else {
        throw MCPError.invalidParams("Missing required parameter: 'term'")
    }
    let requestedNames =
        params.arguments?["dictionaries"]?.arrayValue?
        .compactMap(\.stringValue) ?? []
    guard !requestedNames.isEmpty else {
        throw MCPError.invalidParams("Missing required parameter: 'dictionaries'")
    }
    // Defaults to false for the same reason search_term does: HTML dwarfs the plain text and
    // batch multiplies it by the number of dictionaries.
    let includeHTML = params.arguments?["include_html"]?.boolValue ?? false

    var results: [BatchResponse.Result] = []
    for requested in requestedNames {
        let name = DictionaryAlias(userInput: requested)?.dictionaryName ?? requested
        do {
            let entries = try await DictionaryService.shared.entries(matching: term, in: name)
            results.append(
                .init(
                    dictionary: name, requested: requested,
                    entries: entries.map { SearchResponse.Entry($0, includeHTML: includeHTML) },
                    error: nil))
        } catch DictionaryKitError.termNotFound {
            results.append(.init(dictionary: name, requested: requested, entries: [], error: nil))
        } catch {
            // One bad dictionary shouldn't fail the whole batch, but the caller still needs to
            // know it failed rather than reading an empty list as "no definition".
            results.append(
                .init(
                    dictionary: name, requested: requested, entries: [],
                    error: "\(error)"))
        }
    }

    let response = BatchResponse(term: term, results: results)
    return .init(content: [.text(try encodeToJSON(response))], isError: false)
}

private func handleGetCurrentDictionary(context: DictionaryContext) async throws -> CallTool.Result
{
    let response = CurrentDictionaryResponse(dictionary: await context.current())
    return .init(content: [.text(try encodeToJSON(response))], isError: false)
}

private func handleSetDictionary(
    params: CallTool.Parameters,
    context: DictionaryContext
) async throws -> CallTool.Result {
    guard let requested = params.arguments?["dictionary"]?.stringValue, !requested.isEmpty else {
        throw MCPError.invalidParams("Missing required parameter: 'dictionary'")
    }

    do {
        let resolved = try await context.setCurrent(requested)
        let response = SetDictionaryResponse(
            dictionary: resolved, requested: requested, status: "set")
        return .init(content: [.text(try encodeToJSON(response))], isError: false)
    } catch DictionaryKitError.dictionaryUnavailable {
        throw MCPError.invalidParams(
            "Dictionary '\(requested)' is not installed. "
                + "Call list_dictionaries to see what is available.")
    }
}

// MARK: - Utilities

/// The single JSON encoder for every tool and resource response.
func encodeToJSON(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
