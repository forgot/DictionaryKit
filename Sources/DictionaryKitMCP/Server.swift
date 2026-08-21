import DictionaryKit
import Logging
import MCP

/// Holds the dictionary that argument-less tool calls should use.
///
/// This is what makes `set_dictionary` meaningful. Tools resolve a dictionary in this order:
///
/// 1. the `dictionary` argument, if the caller supplied one
/// 2. otherwise, ``current()`` — whatever `set_dictionary` last set
/// 3. which starts at the New Oxford American Dictionary
///
/// Because the initial value is NOAD, a client that never calls `set_dictionary` behaves
/// exactly like `dictionarykit` invoked without `--dictionary`.
public actor DictionaryContext {
    private var currentDictionaryName: String

    public init(defaultDictionary: String = DCSNewOxfordAmericanDictionaryName) {
        self.currentDictionaryName = defaultDictionary
    }

    /// The dictionary used when a tool call omits `dictionary`.
    public func current() -> String {
        currentDictionaryName
    }

    /// Sets the session dictionary, resolving aliases and validating that it exists.
    ///
    /// - Returns: the full dictionary name that was stored.
    /// - Throws: ``DictionaryKitError/dictionaryUnavailable(_:)`` if no such dictionary is
    ///   installed. Deliberately a domain error rather than an `MCPError` — mapping to the
    ///   transport's error type is the handler's job, not this type's.
    @discardableResult
    public func setCurrent(_ name: String) async throws -> String {
        let resolved = DictionaryAlias(userInput: name)?.dictionaryName ?? name
        // Round-trips through the service so the stored value is the dictionary's real name,
        // even when the caller passed an alias or a near-miss spelling.
        let descriptor = try await DictionaryService.shared.dictionary(named: resolved)
        currentDictionaryName = descriptor.name
        return descriptor.name
    }
}

/// Resolves a tool's optional `dictionary` argument to a concrete dictionary name.
func resolveDictionaryName(
    argument: String?,
    context: DictionaryContext
) async -> String {
    guard let argument, !argument.trimmingCharacters(in: .whitespaces).isEmpty else {
        return await context.current()
    }
    return DictionaryAlias(userInput: argument)?.dictionaryName ?? argument
}

/// Creates and configures the MCP server with all capabilities.
public func createServer(
    context: DictionaryContext = DictionaryContext(),
    logger: Logger = Logger(label: "com.apprhythmia.dictionarykit.mcp")
) async -> Server {
    let server = Server(
        name: "DictionaryKit",
        version: DictionaryKitVersion.current,
        capabilities: .init(
            resources: .init(subscribe: false, listChanged: false),
            tools: .init(listChanged: false)
        )
    )

    logger.info(
        "Server created",
        metadata: ["version": .string(DictionaryKitVersion.current)])

    await registerToolHandlers(server: server, logger: logger, context: context)
    await registerResourceHandlers(server: server, logger: logger)

    return server
}
