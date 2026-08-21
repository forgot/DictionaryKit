import DictionaryKit
import DictionaryKitMCP
import Foundation
import Logging
import MCP
import ServiceLifecycle

/// Wraps the MCP server for ServiceLifecycle.
///
/// `Service` declares only `run()`. An earlier version of this file also defined a
/// `shutdown()` method, which was never called by anything, and ended `run()` with a
/// hundred-year `Task.sleep`. The result was a server that ignored SIGINT and survived its
/// client disconnecting — every client that spawned it leaked a process.
///
/// The fix is to wait on the server's own completion and to tear it down from a graceful
/// shutdown handler.
struct MCPService: Service {
    let server: Server
    let transport: any Transport
    let logger: Logger

    func run() async throws {
        try await server.start(transport: transport) { clientInfo, _ in
            logger.info(
                "Client connected",
                metadata: [
                    "name": .string(clientInfo.name),
                    "version": .string(clientInfo.version),
                ])
        }

        // Returns when the transport closes — which is what happens when the client exits.
        await withGracefulShutdownHandler {
            await server.waitUntilCompleted()
        } onGracefulShutdown: {
            Task { await server.stop() }
        }

        logger.info("Server stopped")
    }
}

// swift-log's default handler already writes to stderr, which is what stdio transport
// requires: stdout carries JSON-RPC and nothing else may touch it.
var logger = Logger(label: "com.apprhythmia.dictionarykit.mcp")
logger.logLevel =
    ProcessInfo.processInfo.environment["LOG_LEVEL"]
    .flatMap(Logger.Level.init(rawValue:)) ?? .info

logger.info(
    "Starting DictionaryKit MCP server",
    metadata: ["version": .string(DictionaryKitVersion.current)])

if !DictionaryService.canAccessPrivateAPIs() {
    // Worth saying once at startup: every tool call will fail, and the reason is the host
    // system rather than anything the client did.
    logger.warning(
        "Private DictionaryServices APIs are unavailable; all dictionary tools will fail")
}

let server = await createServer(logger: logger)
let service = MCPService(
    server: server,
    transport: StdioTransport(logger: logger),
    logger: logger)

var configuration = ServiceGroupConfiguration(
    services: [
        .init(
            service: service,
            // The transport reaching EOF is the normal way this process ends: the client
            // exited. The default `.cancelGroup` treats a service returning as a failure and
            // exits 133 with "a service has finished unexpectedly", so say what we mean.
            successTerminationBehavior: .gracefullyShutdownGroup)
    ],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger)
// Without a bound, a service that refuses to stop hangs the process forever.
configuration.maximumGracefulShutdownDuration = .seconds(5)

try await ServiceGroup(configuration: configuration).run()
