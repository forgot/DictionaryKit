#!/bin/bash
#
# Builds and tests the package.
#
# Tests that need dictionary content skip themselves when none is installed, so this is
# safe to run on a machine with the DictionaryServices framework but no dictionaries.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building (release)"
swift build -c release

echo "==> Testing"
swift test

echo "==> OK"
