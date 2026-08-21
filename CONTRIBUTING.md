# Contributing

## Getting set up

```sh
git clone https://github.com/forgot/DictionaryKit.git
cd DictionaryKit
Scripts/test.sh
```

You need macOS 15+ and Swift 6.0+. Tests that need dictionary content skip themselves when
none is installed, so a clean run on a bare machine is expected rather than a warning sign.

## Things worth knowing before you change anything

**The C shim's annotations are load-bearing.** `CF_RETURNS_RETAINED` and
`CF_RETURNS_NOT_RETAINED` in `DictionaryServicesShim.h` tell the Swift importer the ownership
convention of each Core Foundation call. Getting one wrong produces a leak or a double-free
that no compiler will warn you about. The `dkds_copy_*` / `dkds_get_*` prefixes encode the same
fact — keep the prefix and the annotation in agreement.

**Dictionary names must match byte for byte.** DictionaryServices looks names up by exact
string, and the real names contain trailing spaces, typographic apostrophes, and precomposed
Indic characters that look identical to the forms you would naturally type. If you add a
constant to `DictionaryNames.swift`, do not retype the name — copy it out of
`dictionarykit --list`, and run the tests, which fail on a near miss.

**Ranges from DictionaryServices are in UTF-16 code units.** Applying one with
`String.index(_:offsetBy:)` counts Characters and traps on emoji. Go through `String.utf16`.

**Behaviour belongs in a library, never in an executable target.** Swift cannot
`@testable import` an executable, so anything in `Sources/dictionarykit-cli` or
`Sources/dictionarykit-mcp-server` is untestable by construction. Both are a handful of lines
that hand off to `DictionaryKitCLI` and `DictionaryKitMCP` respectively; keep them that way.

## Tests

`Scripts/test.sh` runs everything. Four targets, in two styles:

| Target                          | Style     | Covers                                          |
| ------------------------------- | --------- | ----------------------------------------------- |
| `DictionaryKitTests`            | unit      | the actor, aliases, and the name constants       |
| `DictionaryKitMCPTests`         | unit      | tools, resources, and session state              |
| `DictionaryKitCLITests`         | unit      | argument validation and output rendering         |
| `DictionaryKitCLIEndToEndTests` | black box | exit codes and the stdout/stderr split           |

The CLI is covered twice on purpose. `Renderer` is pure — values in, a `CommandOutput` out — so
the unit tests cover every output mode without needing a dictionary installed. But exit codes
and stream routing only exist at the process boundary; there is no function that returns "this
went to stderr". The end-to-end target spawns the real binary to pin those, because that is the
surface other programs bind to. See [ARCHITECTURE.md](ARCHITECTURE.md#how-the-cli-is-tested)
for the two traps involved.

If you add a test that shells out, do not block: hand the work to `CLI.run`, which keeps it off
the cooperative thread pool. Blocking a cooperative thread deadlocks the entire parallel run.

Prefer a test that fails on a machine with no dictionaries over a test that skips there — but
where dictionary content is genuinely required, gate it with
`.enabled(if: CLI.hasDictionaries, …)` so the suite still passes on a bare machine. A skipped
suite reports green, so check the run actually executed what you think it did.

## Style

Run `swift format --in-place --recursive Sources Tests` before submitting; settings are in
`.swift-format`.

## Pull requests

Explain what changed and why. If you are fixing a bug, please add a test that fails without
the fix. Most of what goes wrong in this project is invisible rather than loud — a dictionary
name that differs by one codepoint, a diagnostic on the wrong stream, a flag that is silently
ignored — and none of it announces itself without an assertion.

## Releasing

Releases are built locally on a Mac; there is no CI. The README has the short version — this
is the full runbook, including how to prove the prebuilt path works.

### 1. Prepare

Bump `DictionaryKitVersion.current`, add the `CHANGELOG.md` entry, and commit. The version
lives in exactly one place and `Scripts/release.sh` refuses to build if the argument disagrees
with it.

### 2. Build the bundle

```sh
Scripts/release.sh 0.2.0
```

In order, the script:

1. checks the version argument against `DictionaryKitVersion.current`
2. checks the working tree is clean
3. runs `Scripts/test.sh`
4. builds universal binaries — `swift build -c release --arch arm64 --arch x86_64`
5. strips them, then ad-hoc signs with `codesign --force --sign -`. Stripping invalidates the
   signature Swift applied, and macOS refuses to run an arm64 binary whose signature doesn't
   match its contents, so the re-sign is not optional.
6. writes `info.json` and zips `.release/dictionarykit.artifactbundle.zip`
7. runs `dictionarykit --version` **out of the bundle**, so a bundle that can't execute fails
   here rather than on a user's machine

It stops there and prints the publish commands rather than running them.

### 3. Publish

```sh
git tag -a v0.2.0 -m 'v0.2.0' && git push origin v0.2.0
gh release create v0.2.0 .release/dictionarykit.artifactbundle.zip \
    --title 'v0.2.0' --notes-file CHANGELOG.md
```

The zip must be attached to the release. mise scans release assets for `*.artifactbundle.zip`
and uses the prebuilt executable when a variant matches the host's Swift target triple;
otherwise it silently builds from source. Silently is the problem — see below.

### 4. Verify the prebuilt path

Two things will bite you here; both look like the release is broken when it isn't.

**mise hides brand-new releases.** Its `minimum_release_age` setting keeps a freshly published
release out of `ls-remote` — sensible supply-chain caution, baffling in the ten minutes after
you tag. `mise ls-remote` will report "N newer releases hidden by minimum_release_age". Either
wait it out or override for the check:

```sh
MISE_MINIMUM_RELEASE_AGE=0 mise ls-remote spm:forgot/DictionaryKit   # expect: v0.1.0
```

**Version specifiers carry the `v`.** This backend resolves the raw git tag, so `@v0.1.0`
works and `@0.1.0` matches nothing — mise fetches `refs/tags/<version>` literally. `latest`
and an omitted version both resolve correctly.

Then force the prebuilt path, since a plain `mise use` silently falls back to compiling:

```sh
MISE_MINIMUM_RELEASE_AGE=0 mise install \
    "spm:forgot/DictionaryKit[filter_bins=dictionarykit,artifactbundle=true]@v0.1.0"
```

Inline options go **before** `@version`; putting them after makes mise read the whole string as
the version. Quote the argument — zsh treats `[…]` as a glob.

`artifactbundle = true` makes mise fail rather than fall back, so an install that finishes in a
few seconds proves the bundle matched. Output naming `checksum` and `extract` of the
`.artifactbundle.zip` is the confirmation; a source build would run `swift build` instead.

Then confirm the binaries themselves:

```sh
W=$(MISE_MINIMUM_RELEASE_AGE=0 mise where spm:forgot/DictionaryKit@v0.1.0)
ls "$W/bin"                      # expect only: dictionarykit
"$W/bin/dictionarykit" --version # matches the tag
file "$W/bin/dictionarykit"      # universal: x86_64 and arm64
mint install forgot/DictionaryKit@v0.1.0 dictionarykit   # source path still works
```

### Notes

- The bundle declares both executables, so mise links `dictionarykit` and
  `dictionarykit-mcp-server`. Consumers who want only one use
  `filter_bins = ["dictionarykit"]`, which narrows what is linked out of the bundle rather than
  falling back to a source build — that is the separate `artifactbundle = false`.

  `filter_bins` matches names **exactly**, verified against the 0.1.0 bundle:
  `filter_bins=dictionarykit` links only `dictionarykit`, even though it is a prefix of
  `dictionarykit-mcp-server`.
- Binaries are ad-hoc signed, not notarized. That is fine for `mise` and `mint`, which fetch
  over HTTP without setting the quarantine attribute. A user who downloads the zip in a
  browser will hit Gatekeeper — notarization is the fix if that ever matters.
- Nothing here needs a workflow. If one is added later it should call `Scripts/release.sh`
  rather than reimplement it in YAML.
