import Foundation

/// Everything an outside caller can observe from one run of the binary.
struct CLIResult {
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
    /// True when the process died from a signal rather than exiting normally.
    let crashed: Bool
}

/// A mutable box, so a background reader can hand data back without tripping strict concurrency.
private final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// Spawns the built `dictionarykit` binary.
///
/// These tests run the real process instead of importing the command, because exit codes and
/// the stdout/stderr split exist only at the process boundary — there is no function to call
/// that returns "this text went to stderr". That distinction is not academic: the CLI's
/// consumers branch on the exit code and parse stdout, and a diagnostic leaking onto stdout
/// would corrupt `--json` output for anything downstream.
enum CLI {

    /// The directory holding the products built for this test run.
    ///
    /// The bundle-relative lookup that SwiftPM's own templates use does not work here. Under
    /// `swift test`, swift-testing runs inside the toolchain's `swiftpm-testing-helper`, so
    /// `Bundle.main` points into Xcode and `Bundle.allBundles` contains no `.xctest` bundle to
    /// find. Deriving the package root from `#filePath` is stable regardless of host process.
    static let productsDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["DICTIONARYKIT_BIN_DIR"] {
            return URL(fileURLWithPath: override)
        }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DictionaryKitCLIEndToEndTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        let buildDirectory = packageRoot.appendingPathComponent(".build")

        // Prefer the configuration these tests were compiled for, but fall back so that a
        // binary built the other way is still found rather than silently skipping the suite.
        #if DEBUG
        let configurations = ["debug", "release"]
        #else
        let configurations = ["release", "debug"]
        #endif

        for configuration in configurations {
            let candidate = buildDirectory.appendingPathComponent(configuration)
            let binary = candidate.appendingPathComponent("dictionarykit")
            if FileManager.default.isExecutableFile(atPath: binary.path) {
                return candidate
            }
        }
        return buildDirectory.appendingPathComponent(configurations[0])
    }()

    static let binary = productsDirectory.appendingPathComponent("dictionarykit")

    /// Whether the binary was built for this run. The package declares a dependency on the
    /// executable target so `swift test` builds it; this guards the case where someone runs
    /// the bundle directly.
    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: binary.path)
    }

    /// A pool for the blocking subprocess work.
    ///
    /// Running a process is synchronous from start to finish, and swift-testing executes tests
    /// in parallel on Swift's cooperative thread pool. Blocking those threads deadlocks the
    /// whole run once enough tests are in flight — every worker ends up parked on a semaphore
    /// with nothing left to make progress. Hand the blocking work to Dispatch and suspend the
    /// caller instead.
    private static let subprocessQueue = DispatchQueue(
        label: "com.apprhythmia.dictionarykit.cli-tests", attributes: .concurrent)

    @discardableResult
    static func run(_ arguments: String...) async throws -> CLIResult {
        try await run(arguments)
    }

    static func run(_ arguments: [String]) async throws -> CLIResult {
        try await withCheckedThrowingContinuation { continuation in
            subprocessQueue.async {
                continuation.resume(with: Result { try runBlocking(arguments) })
            }
        }
    }

    /// Synchronous implementation. Only call this off the cooperative pool.
    private static func runBlocking(_ arguments: [String]) throws -> CLIResult {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()

        // Drain both pipes before waiting. `--html` output runs to hundreds of kilobytes,
        // well past the 64K pipe buffer, so reading them in sequence would deadlock: the
        // child blocks writing stdout while the parent blocks reading stderr.
        let errorData = Box(Data())
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errorData.value = errPipe.fileHandleForReading.readDataToEndOfFile()
            finished.signal()
        }
        let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        finished.wait()
        process.waitUntilExit()

        return CLIResult(
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData.value, as: UTF8.self),
            exitCode: process.terminationStatus,
            crashed: process.terminationReason == .uncaughtSignal)
    }

    /// How many dictionaries this machine actually has, asked of the binary itself.
    ///
    /// Tests that need real dictionary content are gated on this, so the suite still passes on
    /// a Mac — or a CI runner — with the framework present but no dictionaries installed.
    ///
    /// This uses the blocking path deliberately: `.enabled(if:)` traits are evaluated
    /// synchronously while the test plan is built, before any tests run in parallel, so the one
    /// thread it occupies here cannot starve the pool.
    static let installedDictionaryCount: Int = {
        guard isAvailable,
            let result = try? runBlocking(["--list", "--json"]),
            result.exitCode == 0,
            let listings = try? JSONSerialization.jsonObject(
                with: Data(result.standardOutput.utf8)) as? [Any]
        else { return 0 }
        return listings.count
    }()

    static var hasDictionaries: Bool { installedDictionaryCount > 0 }
}
