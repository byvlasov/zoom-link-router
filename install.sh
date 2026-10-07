#!/bin/bash
# macOS system Bash 3.2; no Homebrew, Xcode or sudo required.
set -euo pipefail

ZLR_ARCHIVE_URL='https://github.com/byvlasov/zoom-link-router/releases/download/v1.1/ZoomLinkRouter-1.1-handoff.zip'
ZLR_ARCHIVE_SHA256='882ef501fc6fb6fa64157fd5c8335e668414ffac3845acc75057e926a9973084'
ZLR_ARCHIVE_ROOT='ZoomLinkRouter-1.1-handoff'
ZLR_APP_NAME='Zoom Link Router.app'

zlr_fail() { printf 'Ошибка: %s\n' "$*" >&2; exit 1; }
zlr_cleanup() {
    [[ -z "${zlr_temp:-}" ]] || rm -rf "$zlr_temp"
    [[ -z "${zlr_stage:-}" ]] || rm -rf "$zlr_stage"
    [[ -z "${zlr_lock:-}" ]] || rmdir "$zlr_lock" 2>/dev/null || true
}

zlr_main() {
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    export PATH
    local app_dir='' launch=1 trust=0 version target unpacked actual
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-open) launch=0; shift ;;
            --trust) trust=1; shift ;;
            --app-dir)
                [[ $# -ge 2 && "$2" == /* ]] || zlr_fail '--app-dir требует абсолютный путь.'
                app_dir="$2"; shift 2 ;;
            --help)
                printf '%s\n' 'Usage: bash install.sh [--trust] [--no-open] [--app-dir /absolute/directory]' \
                    '--trust: remove quarantine only from the verified app; bypass its quarantine-based Gatekeeper check.'
                return 0 ;;
            *) zlr_fail "Неизвестный аргумент: $1" ;;
        esac
    done
    [[ "$(uname -s)" == Darwin ]] || zlr_fail 'Установщик предназначен только для macOS.'
    [[ "$EUID" -ne 0 ]] || zlr_fail 'Запустите без sudo от своего пользователя.'
    version="$(sw_vers -productVersion)"
    [[ "${version%%.*}" -ge 12 ]] || zlr_fail 'Нужна macOS 12 или новее.'

    if [[ -z "$app_dir" ]]; then
        # Keep an existing installation in place and avoid a duplicate in ~/Applications.
        if [[ -e "/Applications/$ZLR_APP_NAME" || -L "/Applications/$ZLR_APP_NAME" ]]; then
            app_dir=/Applications
        elif [[ -e "$HOME/Applications/$ZLR_APP_NAME" || -L "$HOME/Applications/$ZLR_APP_NAME" ]]; then
            app_dir="$HOME/Applications"
        elif [[ -w /Applications ]]; then
            app_dir=/Applications
        else
            app_dir="$HOME/Applications"
        fi
    fi
    mkdir -p "$app_dir"
    [[ -d "$app_dir" && -w "$app_dir" ]] || zlr_fail "Нет доступа на запись: $app_dir. Обратитесь к администратору."
    target="$app_dir/$ZLR_APP_NAME"
    [[ ! -L "$target" ]] || zlr_fail "По пути приложения находится символическая ссылка: $target"

    zlr_temp=''; zlr_stage=''; zlr_lock=''
    trap zlr_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir "$app_dir/.ZoomLinkRouter-install.lock" 2>/dev/null ||
        zlr_fail "Другой установщик уже работает или остался каталог $app_dir/.ZoomLinkRouter-install.lock."
    zlr_lock="$app_dir/.ZoomLinkRouter-install.lock"
    zlr_temp="$(mktemp -d "${TMPDIR:-/tmp}/zoom-link-router.XXXXXX")"
    printf '%s\n' 'Скачиваю Zoom Link Router 1.1 с GitHub…'
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 180 --retry 2 \
        "$ZLR_ARCHIVE_URL" --output "$zlr_temp/release.zip"
    actual="$(shasum -a 256 "$zlr_temp/release.zip")"
    [[ "${actual%% *}" == "$ZLR_ARCHIVE_SHA256" ]] || zlr_fail 'Контрольная сумма архива не совпала. Установка отменена.'
    # Extract only after verifying the exact pinned release archive.
    ditto -x -k "$zlr_temp/release.zip" "$zlr_temp/unpacked"
    unpacked="$zlr_temp/unpacked/$ZLR_ARCHIVE_ROOT/$ZLR_APP_NAME"
    [[ -d "$unpacked" && ! -L "$unpacked" ]] || zlr_fail 'В архиве отсутствует приложение.'
    codesign --verify --deep --strict --all-architectures "$unpacked"

    if [[ -e "$target" ]]; then
        if diff -qr "$unpacked" "$target" >/dev/null; then
            printf '%s\n' 'Эта версия уже установлена; повторное копирование не требуется.'
        else
            zlr_fail "Уже существует другая сборка: $target. Она не изменена. Для замены сначала переместите её в Корзину и повторите установку."
        fi
    else
        zlr_stage="$(mktemp -d "$app_dir/.ZoomLinkRouter-stage.XXXXXX")"
        ditto "$unpacked" "$zlr_stage/$ZLR_APP_NAME"
        codesign --verify --deep --strict --all-architectures "$zlr_stage/$ZLR_APP_NAME"
        # Mark this downloaded app for the normal first-launch Gatekeeper check.
        # Removal below requires the explicit --trust option.
        xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");ZoomLinkRouterInstaller;$(uuidgen)" \
            "$zlr_stage/$ZLR_APP_NAME"
        [[ ! -e "$target" && ! -L "$target" ]] || zlr_fail 'Приложение появилось во время установки. Повторите после проверки папки.'
        mv -n "$zlr_stage/$ZLR_APP_NAME" "$app_dir/"
        [[ ! -e "$zlr_stage/$ZLR_APP_NAME" ]] || zlr_fail 'Не удалось переместить приложение.'
        printf 'Установлено: %s\n' "$target"
    fi
    if [[ "$trust" -eq 1 ]]; then
        # The target is either the verified release or an identical existing copy.
        # -s operates on symlinks themselves, never on their external targets.
        xattr -drs com.apple.quarantine "$target"
        printf '%s\n' 'По вашему выбору снята метка карантина macOS только с Zoom Link Router.'
    fi
    printf '%s\n' \
        'После открытия приложения:' \
        '• Если написано «Включено», всё уже настроено — нажмите «Закрыть».' \
        '• Если есть кнопка «Включить», нажмите её и подтвердите Use “Zoom Link Router” в запросе macOS.' \
        'Zoom должен быть установлен отдельно. Остальные веб-ссылки будут открываться в Safari.'
    if [[ "$trust" -eq 0 ]]; then
        printf '%s\n' 'Если macOS не может проверить разработчика: Системные настройки → Конфиденциальность и безопасность → Всё равно открыть.'
    fi
    if [[ "$launch" -eq 1 ]]; then
        if ! open "$target"; then
            printf '%s\n' 'Приложение установлено, но macOS не разрешила запуск. Откройте его из «Программ» по инструкции выше.' >&2
        fi
    fi
}

# Also works when the entire downloaded script is passed to bash -c.
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    zlr_main "$@"
fi
