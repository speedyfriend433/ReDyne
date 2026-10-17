#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
history_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/redyne-history.XXXXXX")
trap 'rm -rf "$history_test_dir"' EXIT HUP INT TERM
swiftc -swift-version 6 -strict-concurrency=complete \
    -module-cache-path "${TMPDIR:-/tmp}/redyne-history-swift-cache" \
    ReDyne/Services/NavigationHistoryManager.swift Tests/Native/NavigationHistoryTests.swift \
    -o "$history_test_dir/history-tests"
"$history_test_dir/history-tests"
