# DictionaryKit

Read macOS's built-in dictionaries from Swift, from the command line, or from an AI assistant.

This is a Swift 6 fork of [NSHipster/DictionaryKit](https://github.com/NSHipster/DictionaryKit),
rewritten around an actor-based async API and extended with a CLI and an MCP server.

> [!WARNING]
> DictionaryKit reaches macOS's dictionaries through the private DictionaryServices framework.
> Apps using it **cannot be distributed on the App Store**. It is meant for personal tools,
> command-line utilities, and local applications.

## Requirements

macOS 15 or later, and Swift 6.0 or later to build.

Symbols are resolved at runtime, so a macOS release that moves or changes DictionaryServices
degrades to `canAccessPrivateAPIs() == false` and thrown errors rather than a crash.

## Install

### The command-line tool and MCP server

<details open>
<summary><b>mise</b> — recommended</summary>

```sh
mise use -g spm:forgot/DictionaryKit
```

Releases ship a prebuilt universal `.artifactbundle.zip`, so this installs in seconds rather
than compiling. To install only one of the two executables:

```sh
mise use -g "spm:forgot/DictionaryKit[filter_bins=dictionarykit]"
```

or equivalently in a config file:

```toml
# mise.toml
[tools]
"spm:forgot/DictionaryKit" = { version = "latest", filter_bins = "dictionarykit" }
```

Quote the argument — zsh reads `[…]` as a glob. To pin a version, append it after the
options and keep the tag's leading `v`: `"spm:forgot/DictionaryKit[…]@v0.1.0"`.

`filter_bins` narrows which binaries are linked out of the prebuilt bundle; it does not fall
back to compiling. Building from source is a separate opt-in — `artifactbundle = false`.
</details>

<details>
<summary><b>mint</b></summary>

```sh
mint install forgot/DictionaryKit dictionarykit
mint install forgot/DictionaryKit dictionarykit-mcp-server
```

Mint always builds from source, so the first install takes a minute.
</details>

<details>
<summary><b>SwiftPM</b></summary>

```sh
git clone https://github.com/forgot/DictionaryKit.git
cd DictionaryKit
swift package experimental-install --product dictionarykit
swift package experimental-install --product dictionarykit-mcp-server
```

This installs into `~/.swiftpm/bin`, which is not on `PATH` by default:

```sh
echo 'export PATH="$HOME/.swiftpm/bin:$PATH"' >> ~/.zshrc
```
</details>

<details>
<summary><b>From source</b></summary>

```sh
git clone https://github.com/forgot/DictionaryKit.git
cd DictionaryKit
swift build -c release
cp "$(swift build -c release --show-bin-path)"/dictionarykit* /usr/local/bin/
```
</details>

### As a library

```swift
.package(url: "https://github.com/forgot/DictionaryKit.git", from: "0.1.0")
```

Then depend on `DictionaryKit` (the library) or `DictionaryKitMCP` (to embed the MCP tools in
your own server).

## The command-line tool

```sh
dictionarykit --search apple                  # New Oxford American Dictionary
dictionarykit -d oxford -s apple              # by alias
dictionarykit -d french -s bonjour
dictionarykit -d "Oxford Thesaurus of English" -s happy   # or by full name

dictionarykit --list                          # what's installed, and their aliases
dictionarykit -s apple --json                 # machine-readable
dictionarykit -s apple --is-defined           # Yes / No
```

| Option                 | Effect                                                            |
| ---------------------- | ----------------------------------------------------------------- |
| `-s, --search <term>`  | Term to look up. Required unless `--list` is given.               |
| `-d, --dictionary <n>` | Alias or full name. Defaults to New Oxford American Dictionary.   |
| `-l, --list`           | List installed dictionaries with their aliases.                   |
| `--json`               | Emit JSON instead of text.                                        |
| `--is-defined`         | Print `Yes` or `No` instead of the definition.                    |
| `-H, --headword-only`  | Print headwords only.                                             |
| `--html`               | Include the HTML-formatted definition alongside the text.         |
| `--html-only`          | Emit the HTML instead of the text.                                |
| `--version`, `-h`      | Version, help.                                                    |

Definitions go to stdout; diagnostics go to stderr, and a failed lookup exits non-zero — so
`dictionarykit -s word --json | jq` behaves.

`--html` and `--html-only` differ in what they replace: `--html` appends the markup under a
`-- HTML --` rule, while `--html-only` emits the markup in place of the text, with no rule to
separate it from. In `--json`, `--html` adds an `html` key and `--html-only` swaps `text` for
`html`. The HTML is around thirty times the size of the text, so ask for it deliberately.

## The MCP server

Exposes the dictionaries to MCP clients such as Claude Code, Claude Desktop, and VS Code.

```json
{
  "mcpServers": {
    "dictionarykit": {
      "command": "dictionarykit-mcp-server"
    }
  }
}
```

Use the absolute path from `which dictionarykit-mcp-server` if the client doesn't inherit your
`PATH`. Claude Desktop's config lives at
`~/Library/Application Support/Claude/claude_desktop_config.json`; VS Code uses `.vscode/mcp.json`
(see [`.vscode/mcp.json.example`](.vscode/mcp.json.example)). Restart the client afterwards.

### Tools

| Tool                     | Purpose                                                    |
| ------------------------ | ---------------------------------------------------------- |
| `list_dictionaries`      | Installed dictionaries, with their aliases                  |
| `search_term`            | Look up a term — `term`, optional `dictionary`, `include_html` |
| `get_dictionary_info`    | Metadata for one dictionary — optional `dictionary`         |
| `batch_search`           | One term across several dictionaries                        |
| `get_current_dictionary` | Which dictionary argument-less lookups will use             |
| `set_dictionary`         | Set that dictionary for the rest of the session             |

`dictionary` accepts an alias or a full name, and is **optional**: when omitted, the session
dictionary is used, which starts at the New Oxford American Dictionary. So `set_dictionary`
once and the following lookups all use it — and every response names the dictionary it
actually used, so a stale session setting is never invisible.

`include_html` defaults to `false`; the HTML is many times larger than the text.

### Resources

- `dictionary://list` — installed dictionaries
- `dictionary://aliases` — every alias, its dictionary, and whether that dictionary is installed

### Configuration

`LOG_LEVEL` sets verbosity (`trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`;
default `info`). Logs go to stderr; stdout carries JSON-RPC only.

## The library

```swift
import DictionaryKit

let service = DictionaryService.shared

guard DictionaryService.canAccessPrivateAPIs() else { return }

for dictionary in try await service.availableDictionaries() {
    print(dictionary.name, dictionary.shortName ?? "")
}

// By alias, by full name, by descriptor, or by default (New Oxford American).
let entries = try await service.entries(matching: "apple", in: .oxford)
let byName  = try await service.entries(matching: "apple", in: DCSOxfordDictionaryOfEnglish)
let byDefault = try await service.entries(matching: "apple")

for entry in entries {
    print(entry.displayName)        // title if the dictionary has one, else headword
    print(entry.text ?? "")
}

// Cheap existence check.
if try await service.isDefined("apple", in: .oxford) { /* … */ }
```

`entries(matching:in:)` and `isDefined(_:in:)` each take a `String`, a `DictionaryAlias`, or a
`DictionaryDescriptor`, plus a no-dictionary overload that uses the default.

Errors are a single enum:

```swift
do {
    let entries = try await service.entries(matching: "apple", in: .oxford)
} catch DictionaryKitError.termNotFound(let term) {
} catch DictionaryKitError.dictionaryUnavailable(let name) {
} catch DictionaryKitError.privateAPIsUnavailable {
}
```

`missingSymbol(String)` and `dataUnavailable(String)` round out the cases.

## Dictionary aliases

`DictionaryAlias` gives 57 short names for dictionaries, usable in Swift, on the CLI, and in
MCP tool calls. Common ones:

| Alias                       | Dictionary                         |
| --------------------------- | ---------------------------------- |
| `apple`                     | Apple Dictionary                   |
| `oxford`, `oxford-uk`       | Oxford Dictionary of English       |
| `oxford-us`, `american`     | New Oxford American Dictionary     |
| `thesaurus`, `thesaurus-uk` | Oxford Thesaurus of English        |
| `thesaurus-us`              | Oxford American Writer's Thesaurus |
| `french`, `german`, `spanish`, `italian` | the corresponding Oxford bilingual dictionary |
| `japanese`, `chinese`, `korean`          | the corresponding bilingual dictionary       |
| `wikipedia`                 | Wikipedia                          |

Run `dictionarykit --list` for the ones actually installed on your Mac — which dictionaries
exist depends on the languages you've enabled. The full set lives in
[`DictionaryAlias.swift`](Sources/DictionaryKit/DictionaryAlias.swift), and the matching
`DCS*` name constants in
[`DictionaryNames.swift`](Sources/DictionaryKit/DictionaryNames.swift).

## How it works

The C target resolves DictionaryServices symbols at runtime with `dlopen`/`dlsym`, so nothing
private is linked at build time and a missing symbol becomes an error rather than a crash. The
Swift layer wraps that in an actor.

[ARCHITECTURE.md](ARCHITECTURE.md) covers the framework search paths, the Core Foundation
ownership rules the shim encodes, and why dictionary names get normalized before lookup.

## Troubleshooting

**"Private DictionaryServices APIs are unavailable"** — the framework wasn't found at any known
path. This is what a macOS release that relocated it looks like; see the path list in
[ARCHITECTURE.md](ARCHITECTURE.md#where-the-framework-is-looked-for).

**"Dictionary not available"** — it isn't installed. Run `dictionarykit --list`, and add
dictionaries in Dictionary.app under Settings.

**No entries for a word you expect** — try another dictionary. Coverage varies, and bilingual
dictionaries often don't define English words.

**An MCP client shows the server as failed** — check the binary path resolves for the client
(`which dictionarykit-mcp-server`), then run `LOG_LEVEL=debug dictionarykit-mcp-server` in a
terminal to see startup errors. It reads JSON-RPC on stdin, so it will simply wait.

## Development

```sh
Scripts/test.sh              # build + test
```

Tests that need dictionary content skip themselves when none is installed. The CLI is covered
both by unit tests and by a suite that spawns the real binary to pin its exit codes and
stdout/stderr split — see [CONTRIBUTING.md](CONTRIBUTING.md#tests).

### Cutting a release

Releases ship a prebuilt universal `.artifactbundle.zip`, which is what lets `mise` install in
seconds instead of compiling. It's built locally — there is no CI.

1. Bump `DictionaryKitVersion.current`, add the `CHANGELOG.md` entry, and commit.

2. Build the bundle:

   ```sh
   Scripts/release.sh 0.2.0
   ```

   It refuses a dirty tree or a version that disagrees with the source, runs the tests, builds
   universal binaries, signs them, and writes `.release/dictionarykit.artifactbundle.zip`.

3. Tag, push, and publish **with the zip attached** — `mise` finds the prebuilt binaries by
   looking for a `*.artifactbundle.zip` asset on the release:

   ```sh
   git tag -a v0.2.0 -m 'v0.2.0' && git push origin v0.2.0
   gh release create v0.2.0 .release/dictionarykit.artifactbundle.zip \
       --title 'v0.2.0' --notes-file CHANGELOG.md
   ```

The bundle is an optimization, not a requirement: `mise` builds from source when a release has
no matching asset, and `mint` always does. See
[CONTRIBUTING.md](CONTRIBUTING.md#releasing) for how to verify the prebuilt path is actually
being used.

## License

MIT. DictionaryKit is a fork of [NSHipster/DictionaryKit](https://github.com/NSHipster/DictionaryKit)
by [Mattt](https://mat.tt/), first released in 2014. The original copyright is retained
in [LICENSE](LICENSE) alongside the fork's.
