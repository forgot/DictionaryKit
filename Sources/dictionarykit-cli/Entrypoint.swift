import DictionaryKitCLI

/// Thin process entry point.
///
/// All of the command's behaviour lives in the `DictionaryKitCLI` library. Executable targets
/// cannot be imported with `@testable`, so anything left in here is untestable by definition —
/// which is why there is nothing here but the handoff.
@main
enum Entrypoint {
    static func main() async {
        await DictionaryKitCommand.main()
    }
}
