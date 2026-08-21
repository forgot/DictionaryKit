/// The version of DictionaryKit, shared by the library, the CLI, and the MCP server.
///
/// SwiftPM has no version field in `Package.swift` — package versions come from git tags —
/// and build plugins run sandboxed without access to git, so there is no way to derive this
/// automatically at build time. It is therefore maintained by hand here and nowhere else.
///
/// `Scripts/release.sh` refuses to build a release whose tag doesn't match ``current``.
public enum DictionaryKitVersion {
    /// The current version, without a leading `v`.
    public static let current = "0.1.0"
}
