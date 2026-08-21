# Architecture

How DictionaryKit reaches macOS's dictionaries, and why it is built this way.

## Layers

```
┌──────────────────────────────────────────────────┐
│  DictionaryKit (Swift)                           │
│  DictionaryService actor · async/await · errors  │
└───────────────────────┬──────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────┐
│  CDictionaryServicesShim (C)                     │
│  dlopen/dlsym · CF ownership annotations         │
└───────────────────────┬──────────────────────────┘
                        │
┌───────────────────────▼──────────────────────────┐
│  DictionaryServices.framework (private, macOS)   │
└──────────────────────────────────────────────────┘
```

## Why a C shim at all

DictionaryServices is a private framework. Linking against it at build time would mean
declaring symbols that may not exist on a given macOS release, and the failure mode for a
missing symbol at load time is the process refusing to start.

Instead, the shim resolves every symbol at runtime with `dlopen` and `dlsym`. A missing
symbol becomes a `NULL` function pointer, which becomes a Swift error — never a crash, and
never a launch failure on a machine where the framework has moved or changed.

### Where the framework is looked for

`dkds_try_load` tries these paths in order, taking the first that loads
(`Sources/CDictionaryServicesShim/DictionaryServicesShim.c`):

1. `/System/Library/Frameworks/CoreServices.framework/Frameworks/DictionaryServices.framework/DictionaryServices`
2. `/System/Library/PrivateFrameworks/DictionaryServices.framework/DictionaryServices`
3. `/System/Library/PrivateFrameworks/DictionaryServicesCore.framework/DictionaryServicesCore`

**If `canAccessPrivateAPIs()` starts returning `false` after a macOS upgrade, this list is the
first place to look.** Apple has moved this framework before, and adding the new path here is
usually the entire fix.

Loading happens exactly once per process, guarded by `pthread_once`, so concurrent first calls
from several threads cannot race.

### The symbol-wrapping pattern

Every private function is wrapped the same way:

```c
CFArrayRef dkds_copy_records_for_search_string(DCSDictionaryRef dictionary, CFStringRef string) {
    typedef CFArrayRef (*fn_t)(DCSDictionaryRef, CFStringRef);
    fn_t fn = (fn_t)dkds_lookup("DCSCopyRecordsForSearchString");
    if (fn == NULL) {
        return NULL;
    }
    return fn(dictionary, string);
}
```

The private symbol is named only as a string. Nothing in the built binary references
`DCSCopyRecordsForSearchString` as a linker symbol.

## Memory management

This is the part worth understanding before changing anything in the shim.

The header annotates each function with `CF_RETURNS_RETAINED` or `CF_RETURNS_NOT_RETAINED`.
Those annotations are not documentation — they are what tells the Swift importer the ownership
convention of the underlying Core Foundation call, so ARC inserts the right retains and
releases. Get one wrong and you have a leak or a double-free, with no compiler complaint.

The naming convention encodes the same fact, so the two can be checked against each other:

| Prefix         | Wraps        | Ownership | Annotation                |
| -------------- | ------------ | --------- | ------------------------- |
| `dkds_copy_*`  | `DCS…Copy…`  | +1 owned  | `CF_RETURNS_RETAINED`     |
| `dkds_get_*`   | `DCS…Get…`   | +0 unowned| `CF_RETURNS_NOT_RETAINED` |

There is a second subtlety. `DCSDictionaryRef` is `const void *` in C, but because the
annotations put the header in a CF-audited region, **Swift imports it as `AnyObject`, not
`UnsafeRawPointer`**. That is what makes caching dictionary references safe: once converted,
they are real objects and ARC keeps them alive for as long as `DictionaryService` holds them.
`ensureLoaded()` converts each set member with
`Unmanaged<AnyObject>.fromOpaque(_:).takeUnretainedValue()`, taking it at +0 because the
enclosing `CFSet` owns the +1.

## Concurrency

`DictionaryService` is an actor. Its mutable state — the handle caches, the descriptor list,
and the load flag — is isolated, so concurrent callers are serialized by the runtime with no
locks in the code. Everything crossing the boundary (`DictionaryDescriptor`,
`DictionaryEntry`, `DictionaryAlias`, `DictionaryKitError`) is `Sendable`.

There is one honest caveat: **the search path has no cancellation points.** `dlsym` and the
Core Foundation calls beneath it are synchronous, so a `Task` cancelled mid-lookup will not
stop early. Lookups are fast enough that this has not mattered in practice, but the public
methods being `async` should not be read as implying cancellation support.

## What a lookup does

`entries(matching:in:)` on a name:

1. `ensureLoaded()` — on first call only, load the framework, enumerate dictionaries via
   `DCSCopyAvailableDictionaries`, and build two indexes: one keyed by exact name, one keyed
   by a normalized form.
2. Resolve the requested name to a handle. Exact match first; on a miss, retry against the
   normalized index.
3. `DCSGetTermRangeInString` finds the term's extent within the query. **The returned
   `CFRange` is in UTF-16 code units**, so it is applied through `String.utf16` — walking it
   with `String.index(_:offsetBy:)` counts Characters instead and traps on emoji and other
   multi-scalar graphemes.
4. `DCSCopyRecordsForSearchString` returns matching records.
5. For each record, read the headword, the optional title, the plain text, and the HTML.

### Why names are normalized

DictionaryServices matches dictionary names by exact string, and the names it reports are
full of traps:

- the Hebrew dictionary's name ends in a space
- the Oxford American Writer's Thesaurus uses a typographic apostrophe (U+2019)
- the Assamese and Odia names use precomposed nukta singletons (U+09DF, U+0B5C) where the
  obvious way to type them produces decomposed pairs — and Unicode's composition exclusions
  mean NFC will not convert between the two
- Apple's own Assamese name is internally inconsistent, precomposed before the bullet and
  decomposed after it

Every one of those renders identically to the correct string and matches nothing, so a
mistranscribed constant is invisible on the page and fails at runtime. Lookups therefore fall
back to a key that is NFC-normalized, whitespace-trimmed, apostrophe-folded, and lowercased.
Exact matches are always tried first, so this never changes the result for a correct name — it
only rescues a near miss instead of failing silently.

`DictionaryNameTests.aliasesAreNotNearMisses` guards the constants themselves, failing loudly
if one ever drifts into near-miss territory again.

## Targets

| Target                     | Kind       | Role                                                |
| -------------------------- | ---------- | --------------------------------------------------- |
| `CDictionaryServicesShim`  | C          | Runtime symbol loading and CF ownership annotations  |
| `DictionaryKit`            | Swift lib  | The actor, models, aliases, and name constants       |
| `DictionaryKitMCP`         | Swift lib  | MCP tools, resources, and session state              |
| `DictionaryKitCLI`         | Swift lib  | The `dictionarykit` command: parsing and rendering   |
| `dictionarykit-cli`        | Executable | `@main` handoff to `DictionaryKitCommand`            |
| `dictionarykit-mcp-server` | Executable | stdio transport and process lifecycle                |

Both executables are deliberately trivial. Swift cannot `@testable import` an executable
target, so whatever is left in one cannot be reached by a unit test. The rule that follows: an
executable target holds process startup and nothing else, and everything worth testing lives in
a library beside it.

The capitalised targets are libraries and the lowercase hyphenated ones are executables, which
is the quickest way to read `Sources/`.

## How the CLI is tested

The command is split so that each half can be tested by the technique that suits it.

`Renderer` in `Sources/DictionaryKitCLI/CommandOutput.swift` is a set of pure functions from
values to a `CommandOutput` — the stdout text, the stderr text, and the exit status. Nothing in
it touches `DictionaryService` or the process, so `DictionaryKitCLITests` covers every output
mode on a machine with no dictionaries installed at all.

`DictionaryKitCLIEndToEndTests` spawns the built binary instead of importing it. That is the
only way to check the parts that exist solely at the process boundary: the exit code, and which
stream each byte landed on. No function you can call returns "this text went to stderr", so a
unit test cannot observe the distinction — and that distinction is the contract other programs
bind to. A diagnostic leaking onto stdout would corrupt `--json` for every downstream consumer.

Two consequences worth knowing if you extend those tests:

- **They run the process off the cooperative thread pool.** Running a subprocess is blocking
  from start to finish, and swift-testing runs tests in parallel on Swift's cooperative
  threads. Blocking those deadlocks the whole run once enough tests are in flight. `CLI.run`
  hands the work to a Dispatch queue and suspends instead.
- **They find the binary from `#filePath`, not from `Bundle`.** Under `swift test`,
  swift-testing runs inside the toolchain's `swiftpm-testing-helper`, so `Bundle.main` points
  into Xcode and `Bundle.allBundles` holds no `.xctest` bundle. The bundle-relative lookup in
  SwiftPM's own templates is written for XCTest and silently finds nothing here — which skips
  the entire suite while still reporting a green run.
