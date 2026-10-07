#!/bin/zsh
set -euo pipefail
task_root="${0:A:h}"
task_app="$task_root/Zoom Link Router.app"
if [[ "${1:-}" == "--universal" ]]; then
  task_archs=(arm64 x86_64)
elif [[ $# == 0 ]]; then
  task_archs=("$(uname -m)")
else
  print -u2 -- "Usage: build.command [--universal]"
  exit 2
fi
task_cache="$(mktemp -d "${TMPDIR:-/tmp/}zoom-router-build.XXXXXX")"
trap 'rm -rf "$task_cache"' EXIT
mkdir -p "$task_app/Contents/MacOS"
cp "$task_root/source/Info.plist" "$task_app/Contents/Info.plist"
task_slices=()
for task_arch in "${task_archs[@]}"; do
  task_slice="$task_cache/ZoomLinkRouter-$task_arch"
  xcrun swiftc -swift-version 5 -O -module-cache-path "$task_cache/modules-$task_arch" \
    "$task_root/source/Router.swift" "$task_root/source/main.swift" \
    -o "$task_slice" -framework AppKit -target "$task_arch-apple-macosx12.0"
  task_slices+=("$task_slice")
done
xcrun lipo -create "${task_slices[@]}" -output "$task_app/Contents/MacOS/ZoomLinkRouter"
codesign --force --sign - "$task_app"
codesign --verify --strict "$task_app"
print -r -- "Готово: $task_app"
