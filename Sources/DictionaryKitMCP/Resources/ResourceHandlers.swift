import DictionaryKit
import Foundation
import Logging
import MCP

private struct DictionaryListEntry: Encodable {
    let name: String
    let shortName: String?
    let aliases: [String]
}

private struct AliasEntry: Encodable {
    let alias: String
    let dictionary: String
    let installed: Bool
}

/// Registers resource handlers with the server.
func registerResourceHandlers(server: Server, logger: Logger) async {
    await server.withMethodHandler(ListResources.self) { _ in
        .init(resources: getResourceDefinitions())
    }

    await server.withMethodHandler(ReadResource.self) { params in
        logger.debug("Resource read", metadata: ["uri": .string(params.uri)])

        switch params.uri {
        case "dictionary://list":
            return .init(contents: try await generateDictionaryList(uri: params.uri))
        case "dictionary://aliases":
            return .init(contents: try await generateDictionaryAliases(uri: params.uri))
        default:
            throw MCPError.invalidParams("Unknown resource URI: \(params.uri)")
        }
    }

    logger.info("Resource handlers registered")
}

/// Lists the dictionaries installed on this system.
private func generateDictionaryList(uri: String) async throws -> [Resource.Content] {
    let dictionaries = try await DictionaryService.shared.availableDictionaries()
    let entries = dictionaries.map {
        DictionaryListEntry(
            name: $0.name,
            shortName: $0.shortName,
            aliases: DictionaryAlias.aliases(for: $0.name).map(\.rawValue))
    }
    return [.text(try encodeToJSON(entries), uri: uri, mimeType: "application/json")]
}

/// Lists every alias and the dictionary name it maps to.
///
/// Generated from `DictionaryAlias.allCases` rather than written out by hand. A hardcoded
/// table here previously advertised invented names such as "French-English Dictionary" that
/// matched no installed dictionary, so every lookup a client built from this resource failed.
///
/// `installed` reports whether the target is actually present on this machine, which lets a
/// client pick a working dictionary without a second round-trip.
private func generateDictionaryAliases(uri: String) async throws -> [Resource.Content] {
    let installed = Set(
        try await DictionaryService.shared.availableDictionaries().map(\.name))

    let entries = DictionaryAlias.allCases.map {
        AliasEntry(
            alias: $0.rawValue,
            dictionary: $0.dictionaryName,
            installed: installed.contains($0.dictionaryName))
    }
    return [.text(try encodeToJSON(entries), uri: uri, mimeType: "application/json")]
}
