#!/bin/bash
# Exercise file installation in a temporary directory. Never launch the app.
set -euo pipefail
test_repo="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/zoom-installer-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
if [[ $# -eq 1 ]]; then
    test_fixture="$1"
else
    test_fixture="$test_root/release.zip"
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        'https://github.com/byvlasov/zoom-link-router/releases/download/v1.1/ZoomLinkRouter-1.1-handoff.zip' \
        --output "$test_fixture"
fi
export ZLR_TEST_FIXTURE="$test_fixture" ZLR_TEST_ROOT="$test_root"
test_count=0
test_pass() { test_count=$((test_count + 1)); printf 'PASS: %s\n' "$1"; }
test_fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

test_run() {
    /bin/bash -c '
        source "$1"
        shift
        curl() {
            case "${ZLR_TEST_DOWNLOAD:-ok}" in
                fail) return 22 ;;
                corrupt) printf "incomplete archive" > "${@: -1}" ;;
                *) cp "$ZLR_TEST_FIXTURE" "${@: -1}" ;;
            esac
        }
        open() { printf "%s\n" "$1" >> "$ZLR_TEST_ROOT/open.log"; }
        zlr_main "$@"
    ' test-installer "$test_repo/install.sh" "$@" > "$test_root/last.log" 2>&1
}

test_app_dir="$test_root/Applications with spaces"
test_app="$test_app_dir/Zoom Link Router.app"
test_run --app-dir "$test_app_dir" --no-open || { cat "$test_root/last.log"; test_fail install; }
[[ -x "$test_app/Contents/MacOS/ZoomLinkRouter" ]] || test_fail executable
codesign --verify --deep --strict --all-architectures "$test_app"
[[ "$(xattr -p com.apple.quarantine "$test_app")" == 0083\;* ]] || test_fail quarantine
[[ ! -e "$test_root/open.log" ]] || test_fail no-open
test_pass 'install into a path with spaces, signature, quarantine, --no-open'

test_before="$(stat -f '%i:%m' "$test_app/Contents/MacOS/ZoomLinkRouter")"
test_run --app-dir "$test_app_dir" --no-open || test_fail repeat
[[ "$(stat -f '%i:%m' "$test_app/Contents/MacOS/ZoomLinkRouter")" == "$test_before" ]] || test_fail rewritten
test_pass 'repeat leaves existing identical application unchanged'

test_run --app-dir "$test_app_dir" || test_fail launch-request
[[ "$(cat "$test_root/open.log")" == "$test_app" ]] || test_fail launch-path
test_pass 'requests launch of the installed path (open mocked)'

printf 'keep me' > "$test_app/custom-file"
if test_run --app-dir "$test_app_dir" --no-open; then test_fail replaced-different-app; fi
[[ "$(cat "$test_app/custom-file")" == 'keep me' ]] || test_fail lost-custom-file
test_pass 'different existing application is preserved'

for test_mode in fail corrupt; do
    export ZLR_TEST_DOWNLOAD="$test_mode"
    if test_run --app-dir "$test_root/$test_mode" --no-open; then test_fail "$test_mode accepted"; fi
    [[ ! -e "$test_root/$test_mode/Zoom Link Router.app" ]] || test_fail "$test_mode installed"
    [[ ! -e "$test_root/$test_mode/.ZoomLinkRouter-install.lock" ]] || test_fail "$test_mode lock cleanup"
    test_pass "$test_mode download rejected without installing"
done
unset ZLR_TEST_DOWNLOAD

mkdir "$test_root/symlink"
ln -s "$test_app" "$test_root/symlink/Zoom Link Router.app"
if test_run --app-dir "$test_root/symlink" --no-open; then test_fail symlink-accepted; fi
[[ -L "$test_root/symlink/Zoom Link Router.app" ]] || test_fail symlink-changed
test_pass 'application symlink rejected without changing its target'

mkdir -p "$test_root/locked/.ZoomLinkRouter-install.lock"
if test_run --app-dir "$test_root/locked" --no-open; then test_fail lock-ignored; fi
[[ -d "$test_root/locked/.ZoomLinkRouter-install.lock" ]] || test_fail removed-other-lock
test_pass 'another installer lock is respected and preserved'

[[ ! -e "$test_app_dir/.ZoomLinkRouter-install.lock" ]] || test_fail lock-left
[[ -z "$(find "$test_app_dir" -name '.ZoomLinkRouter-stage.*' -print)" ]] || test_fail staging-left
test_pass 'temporary staging and owned lock removed'
printf '%s installer checks passed; no app launched and no browser setting changed.\n' "$test_count"
