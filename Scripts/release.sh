#!/bin/bash
#
# Builds a release artifact bundle for distribution via mise and mint.
#
#     Scripts/release.sh 0.1.0
#
# Produces .release/dictionarykit.artifactbundle.zip containing universal binaries.
# When that zip is attached to a GitHub release, mise installs the prebuilt executables
# instead of compiling from source, which turns a ~40 second install into a ~2 second one.
# mint always builds from source and only needs the git tag.
#
# This script does not tag, push, or publish anything: it prints the commands to run.
# Releases are outward-facing and should stay a deliberate step.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: Scripts/release.sh <version>   (e.g. 0.1.0, without a leading 'v')" >&2
    exit 64
fi

VERSION_FILE="Sources/DictionaryKit/DictionaryKitVersion.swift"
DECLARED=$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' "$VERSION_FILE")

# A binary that reports a different version than its tag is the kind of thing nobody
# notices until they are trying to reproduce a bug report.
if [[ "$DECLARED" != "$VERSION" ]]; then
    echo "error: requested $VERSION but $VERSION_FILE declares $DECLARED" >&2
    echo "       update DictionaryKitVersion.current, or pass $DECLARED" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree is dirty; commit or stash first" >&2
    git status --short >&2
    exit 1
fi

echo "==> Running tests"
Scripts/test.sh

STAGE=".release"
BUNDLE="$STAGE/dictionarykit.artifactbundle"
PAYLOAD="dictionarykit-$VERSION-macos"
rm -rf "$STAGE"
mkdir -p "$BUNDLE/$PAYLOAD/bin"

echo "==> Building universal binaries"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=".build/apple/Products/Release"

for tool in dictionarykit dictionarykit-mcp-server; do
    cp "$BIN_DIR/$tool" "$BUNDLE/$PAYLOAD/bin/$tool"
    strip -rSTx "$BUNDLE/$PAYLOAD/bin/$tool"
    # Ad-hoc signing. Stripping invalidates the signature Swift applied, and macOS refuses
    # to run an arm64 binary whose signature does not match its contents.
    codesign --force --sign - "$BUNDLE/$PAYLOAD/bin/$tool"
    echo "    $tool: $(lipo -archs "$BUNDLE/$PAYLOAD/bin/$tool")"
done

# The artifact bundle manifest. One entry per executable; a universal binary satisfies both
# triples from a single variant, so mise finds a match on Intel and Apple silicon alike.
cat > "$BUNDLE/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "dictionarykit": {
      "version": "$VERSION",
      "type": "executable",
      "variants": [
        {
          "path": "$PAYLOAD/bin/dictionarykit",
          "supportedTriples": ["arm64-apple-macosx", "x86_64-apple-macosx"]
        }
      ]
    },
    "dictionarykit-mcp-server": {
      "version": "$VERSION",
      "type": "executable",
      "variants": [
        {
          "path": "$PAYLOAD/bin/dictionarykit-mcp-server",
          "supportedTriples": ["arm64-apple-macosx", "x86_64-apple-macosx"]
        }
      ]
    }
  }
}
JSON

echo "==> Packaging"
(cd "$STAGE" && zip -qry dictionarykit.artifactbundle.zip dictionarykit.artifactbundle)
ZIP="$STAGE/dictionarykit.artifactbundle.zip"

echo "==> Verifying the packaged binaries run"
"$BUNDLE/$PAYLOAD/bin/dictionarykit" --version
echo

echo "Built $ZIP ($(du -h "$ZIP" | cut -f1))"
echo
echo "To publish:"
echo "    git tag -a v$VERSION -m 'v$VERSION' && git push origin v$VERSION"
echo "    gh release create v$VERSION $ZIP --title 'v$VERSION' --notes-file CHANGELOG.md"
echo
echo "Then verify installation:"
echo "    mise use -g spm:forgot/DictionaryKit@v$VERSION"
echo "      (mise resolves the raw git tag, so the leading v is required. A release"
echo "       published minutes ago is hidden until minimum_release_age passes; prefix"
echo "       the command with MISE_MINIMUM_RELEASE_AGE=0 to check it immediately.)"
echo "    mint install forgot/DictionaryKit@v$VERSION dictionarykit"
