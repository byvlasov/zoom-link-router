#!/bin/zsh
set -euo pipefail
task_root="${0:A:h:h}"
cd "$task_root"
mkdir -p dist
task_files=(
  README.md AI_REVIEW.md SECURITY.md BUILDING.md CHANGELOG.md LICENSE .gitignore
  source/Router.swift source/main.swift source/Info.plist source/Tests/main.swift
  build.command test.command install.sh scripts/test-installer.sh
  scripts/review-bundle.command .github/workflows/checks.yml
)
{
  print -r -- 'ZOOM LINK ROUTER — REVIEW BUNDLE'
  print -r -- 'Generated from the files listed below. Source lines are numbered.'
  print -r -- 'This is review material, not proof of binary provenance or safety.'
  for task_file in "${task_files[@]}"; do
    print
    print -r -- "===== FILE: $task_file ====="
    /usr/bin/nl -ba "$task_file"
  done
} > dist/REVIEW_BUNDLE.txt
print -r -- 'Generated dist/REVIEW_BUNDLE.txt'
