# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

The first release of the Swift rewrite. DictionaryKit began as an Objective-C library by
[Mattt](https://mat.tt/); this fork rewrites it for Swift 6 and adds a command-line tool and an
MCP server. Everything below is relative to the archived
[Objective-C original](https://github.com/NSHipster/DictionaryKit).

### Added

- `DictionaryService`, an actor with an async API for listing dictionaries, searching, and
  checking whether a term is defined. Overloads accept a full name, a `DictionaryAlias`, a
  `DictionaryDescriptor`, or nothing at all — the last defaulting to the New Oxford American
  Dictionary.
- `DictionaryAlias`: 57 short names such as `oxford` and `french`, usable from Swift, from the
  command line, and in MCP tool calls.
- `DictionaryKitError`, one error type covering unavailable private APIs, missing symbols,
  unknown dictionaries, unknown terms, and unreadable data. It conforms to `LocalizedError`, so
  `localizedDescription` carries the real message.
- `DictionaryEntry.title` alongside `headword`, and `displayName` preferring the title. Some
  dictionaries index an entry under one word and display another — the idiom "upset the
  applecart" lives under "apple".
- 60 dictionary name constants, up from 18, covering the Indic, Asian, and European
  dictionaries macOS ships.
- `dictionarykit`, a command-line tool: `--search`, `--dictionary`, `--list`, `--json`,
  `--is-defined`, `--headword-only`, `--html`, and `--html-only`. Definitions go to stdout and
  diagnostics to stderr, and a failed lookup exits non-zero, so its output is safe to pipe.
- `dictionarykit-mcp-server`, an MCP server exposing six tools and two resources over stdio.
  A session dictionary lets a client set one once rather than naming it on every call, and
  every response reports the dictionary actually used.
- `DictionaryKitMCP`, a library target for embedding those tools in another server.
- Release tooling: `Scripts/release.sh` builds a universal `.artifactbundle.zip`, so `mise`
  installs a prebuilt binary instead of compiling from source.

### Changed

- Rewritten in Swift 6 under strict concurrency. Dictionary access is serialized through an
  actor and the public API is `async`.
- Private DictionaryServices symbols are resolved at runtime by a C shim rather than linked at
  build time. A macOS release that moves or renames them yields
  `canAccessPrivateAPIs() == false` and thrown errors instead of a crash at launch.
- Dictionary lookup falls back to a normalized comparison — NFC, whitespace-trimmed,
  apostrophe-folded — when an exact match fails, so a name that differs only invisibly from the
  system's still resolves.
- Minimum platform is macOS 15; minimum toolchain is Swift 6.0.

### Fixed

- `DCSOxfordAmericanWritersThesaurus` could never match. It spelled the name with an ASCII
  apostrophe where macOS uses U+2019, so the two rendered identically and compared unequal.

### Removed

- The Objective-C API. `TTTDictionary` and `TTTDictionaryEntry` are gone; this release keeps
  the original's approach and its dictionary name constants, but none of its types.

[Unreleased]: https://github.com/forgot/DictionaryKit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/forgot/DictionaryKit/releases/tag/v0.1.0
