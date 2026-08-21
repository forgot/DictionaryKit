---
name: Swift conventions
description: Swift conventions — concurrency, cancellation, and language use — plus the constraints specific to wrapping a private C framework
applyTo: "**/*.swift"
---

# Swift conventions

Everything through "General conventions" is portable and can be lifted into another Swift
project as-is. The last section is specific to this package and should be replaced, not
carried over.

## Which Swift version

Don't restate a version number here. The authoritative answers are:

- **Language mode and minimum toolchain**: the `swift-tools-version` line in `Package.swift`
- **Minimum OS**: the `platforms:` list in `Package.swift`
- **What's installed**: `swift --version`

Write for the language mode the package declares. If you need to know whether a feature exists,
check the toolchain rather than assuming — and if a newer language mode would help, propose
changing `Package.swift` rather than quietly writing code that needs it.

Statements of the form "X is the current version" go stale on a schedule nobody tracks, and a
stale instruction is worse than an absent one because it is followed with confidence. Point at
the source of truth instead of copying it.

## Concurrency

Prefer structured concurrency — `async`/`await`, `actor`, `Task`, `TaskGroup`, `async let` —
over `DispatchQueue`, `DispatchGroup`, `OperationQueue`, and manual thread management. Types
crossing an isolation boundary must be `Sendable`; use `actor` to encapsulate mutable state
rather than a class with a lock or a serial queue.

This is a preference about Swift code, not a blanket ban on primitives. C-level tools such as
`pthread_once` remain the right choice where they belong.

### Cancellation is cooperative

Swift cancellation sets a flag. Nothing is interrupted, and work that never checks the flag
runs to completion no matter how promptly its task was cancelled.

- Check with `try Task.checkCancellation()` or `Task.isCancelled` at loop boundaries and
  between expensive steps.
- Bridge non-async work that has its own cancel mechanism with `withTaskCancellationHandler`.
  The `onCancel` closure can run on any thread, concurrently with the operation.
- **`async` in a signature is not a claim of cancellability.** Synchronous C calls or tight
  compute wrapped in an `async` function have no cancellation points at all. Don't document
  cancellation a function doesn't implement — either add the checks or say nothing.

### Streams

Use `AsyncSequence` for a sequence of values arriving over time, and `AsyncStream` /
`AsyncThrowingStream` to bridge callback, delegate, or notification APIs into one.

- Prefer `AsyncStream.makeStream(of:)`, which returns the stream and its continuation as a
  pair, to the closure-based initializer whenever the producer outlives the call.
- Set `continuation.onTermination` to release resources when the consumer goes away.
- Finish a continuation exactly once.
- A stream has a single consumer. Fanning out to several needs a different design.

### Parallelism

- `async let` for a fixed, small number of concurrent children.
- `withTaskGroup` / `withThrowingTaskGroup` when the number is dynamic.
- Prefer both to unstructured `Task { }`, which escapes the surrounding scope and does not
  inherit cancellation.
- Reach for `Task.detached` only when work genuinely must outlive its parent, and say why in
  a comment — it drops isolation and task-local values as well as cancellation.

Note that serializing work through one actor removes the parallelism a task group would
otherwise buy you. Group the calls, not the actor hops.

## General conventions

`let` over `var`. `struct` and `enum` over `class` unless reference semantics are needed.
`guard` for early returns. No force unwrapping, `try!`, or `as!` outside provably safe cases.
No `@objc` or `NSObject` without an Objective-C interop reason.

**Errors.** Use `throws`, and prefer a typed error enum to sentinel values or `NSError`.
Conform error types to `CustomStringConvertible` *and* `LocalizedError`: without the latter,
`error.localizedDescription` on a bare `Error` existential silently falls back to Foundation's
"The operation couldn't be completed", which is how good error messages disappear before they
reach a user. Return `description` from `errorDescription`.

**Strings are not arrays of characters.** `String.index(_:offsetBy:)` counts grapheme clusters.
Any offset that came from a UTF-16 or UTF-8 API must be applied through the matching view, and
`limitedBy:` turns an out-of-range offset into `nil` instead of a trap.

**Unicode equality is not byte equality.** Text that renders identically can differ in
normalization form, and NFC does not reconcile everything — Unicode's composition exclusions
leave some precomposed and decomposed forms permanently distinct. Where an external API matches
by exact string, don't retype values by hand; copy them from the source, and consider a
normalized fallback for lookups.

**Testability is a package-layout decision.** Swift can't reliably `@testable import` an
executable target, so whatever you leave in one cannot be unit tested. Reduce executables to
the `@main` handoff and put everything else — argument parsing, transport wiring, formatting —
in a library target.

**Some behaviour only exists at the process boundary.** Exit codes and the stdout/stderr split
are properties of a process, not of a function: no call returns "this text went to stderr". If
a program's callers branch on those, a unit test cannot cover them and a black-box test that
spawns the real binary is the only option. Two things reliably go wrong when writing one:

- Running a subprocess is blocking end to end, and swift-testing runs tests in parallel on
  Swift's cooperative thread pool. Blocking those threads deadlocks the run once enough tests
  are in flight. Hand the work to a Dispatch queue and suspend the caller.
- Locating the built binary through `Bundle` is XCTest-era advice, including in SwiftPM's own
  templates. Under `swift test`, swift-testing runs inside the toolchain's
  `swiftpm-testing-helper`, so `Bundle.main` points into the toolchain and `Bundle.allBundles`
  contains no `.xctest` bundle. Derive the path from `#filePath` instead.

**A skipped test reports green.** Traits like `.enabled(if:)` are how a suite quietly covers
nothing — a wrong condition disables everything and the run still passes. After adding gated
tests, check the run executed them rather than trusting the summary line.

**Single-source your version string.** SwiftPM manifests carry no version field and build
plugins can't read git, so a package version is maintained by hand. Declare it in one constant
and read it everywhere else.

## Project-specific: wrapping a private C framework

The rules below apply to DictionaryKit only. They exist because each one has already caused a
bug here.

**The C shim's ownership annotations are load-bearing.** `CF_RETURNS_RETAINED` and
`CF_RETURNS_NOT_RETAINED` in `DictionaryServicesShim.h` tell the Swift importer the ownership
convention of each Core Foundation call so ARC balances the retains. A wrong annotation is a
leak or a double-free that no compiler will flag. The `dkds_copy_*` / `dkds_get_*` prefixes
encode the same fact — `copy` means +1, `get` means +0 — so keep prefix and annotation in
agreement, and don't "correct" either to match a comment.

A consequence worth knowing: because those annotations put the header in a CF-audited region,
`DCSDictionaryRef` imports as `AnyObject`, not `UnsafeRawPointer`. Cached dictionary references
are ARC-managed objects, not raw pointers.

**Dictionary names must match byte for byte.** DictionaryServices looks names up by exact
string, and the real names contain trailing spaces, typographic apostrophes, and precomposed
Indic forms. Five constants were silently broken this way. Copy names out of
`dictionarykit --list` and run the tests; `DictionaryNameTests` fails on a near miss.

**Ranges from DictionaryServices are UTF-16.** `DCSGetTermRangeInString` returns a `CFRange` in
UTF-16 code units; applying it with `String.index(_:offsetBy:)` traps on emoji.

**The version lives in `DictionaryKitVersion.current`** and nowhere else.

## Tooling

```sh
swift format --in-place --recursive Sources Tests   # settings in .swift-format
swift format lint --recursive Sources Tests
Scripts/test.sh                                     # build + test
```

Tests that need dictionary content skip themselves when none is installed, so a run with skips
is normal rather than a failure.
