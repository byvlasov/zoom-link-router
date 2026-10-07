#!/bin/zsh
set -euo pipefail
task_root="${0:A:h}"
task_tmp="$(mktemp -d "${TMPDIR:-/tmp/}zoom-router-test.XXXXXX")"
trap 'rm -rf "$task_tmp"' EXIT
xcrun swiftc -swift-version 5 -module-cache-path "$task_tmp/cache" \
  "$task_root/source/Router.swift" "$task_root/source/Tests/main.swift" \
  -o "$task_tmp/test-router"
"$task_tmp/test-router"
