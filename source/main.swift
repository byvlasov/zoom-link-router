import AppKit

final class RouterDelegate: NSObject, NSApplicationDelegate {
    private var pending = 0
    private var receivedURL = false
    private var exitWork: DispatchWorkItem?

    private func isDefault(for scheme: String) -> Bool {
        guard let url = URL(string: "\(scheme)://example.org/"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: url) else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard !receivedURL else { return }
            pending += 1 // Keep the process alive while the setup dialog is open.
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Zoom Link Router"
            let enabled = isDefault(for: "http") && isDefault(for: "https")
            if enabled {
                alert.informativeText = "Включено. Ссылки обычных встреч Zoom → Zoom. Остальные ссылки → Safari.\n\nДля отключения снова выберите Safari браузером по умолчанию в Системных настройках."
                alert.addButton(withTitle: "Закрыть")
                alert.runModal()
                completed()
            } else {
                alert.informativeText = "Ссылки обычных встреч Zoom → Zoom. Остальные ссылки → Safari.\n\nНажмите «Включить» и подтвердите выбор Zoom Link Router в системном окне macOS. Искать приложение в списке браузеров не нужно.\n\nСсылки внутри Safari этим способом не перехватываются."
                alert.addButton(withTitle: "Включить")
                alert.addButton(withTitle: "Позже")
                if alert.runModal() == .alertFirstButtonReturn {
                    setDefault(schemes: ["http", "https"])
                } else {
                    completed()
                }
            }
        }
    }

    private func setDefault(schemes: [String]) {
        guard let scheme = schemes.first else {
            let enabled = isDefault(for: "http") && isDefault(for: "https")
            let alert = NSAlert()
            alert.messageText = enabled ? "Готово — Zoom Link Router включён" : "Выбор браузера не завершён"
            alert.informativeText = enabled
                ? "Теперь обычные приглашения Zoom из почты, календаря и мессенджеров будут открываться в Zoom. Остальные ссылки — в Safari."
                : "Откройте приложение ещё раз и подтвердите выбор в системном окне macOS."
            alert.runModal()
            completed()
            return
        }
        if isDefault(for: scheme) {
            setDefault(schemes: Array(schemes.dropFirst()))
            return
        }
        // Public macOS API; macOS presents its own confirmation when needed.
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL,
                                                 toOpenURLsWithScheme: scheme) { [self] error in
            DispatchQueue.main.async { [self] in
                if error != nil {
                    let alert = NSAlert()
                    alert.messageText = "Выбор браузера не завершён"
                    alert.informativeText = "macOS не подтвердила изменение. Можно повторить настройку, открыв приложение ещё раз."
                    alert.runModal()
                    completed()
                } else {
                    setDefault(schemes: Array(schemes.dropFirst()))
                }
            }
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        receivedURL = true
        exitWork?.cancel()
        for filename in filenames {
            pending += 1
            openSafari(URL(fileURLWithPath: filename))
        }
        sender.reply(toOpenOrPrint: .success)
        finishWhenIdle()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        exitWork?.cancel()
        for original in urls {
            if original.isFileURL {
                pending += 1
                openSafari(original)
                continue
            }
            // This app registers only http(s); ignore unexpected URL schemes.
            guard ["http", "https"].contains(original.scheme?.lowercased() ?? "") else { continue }
            pending += 1
            switch route(original) {
            case .zoom(let target):
                if let zoom = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "us.zoom.xos") {
                    open(target, in: zoom) { [self] success in
                        if success { completed() } else { openSafari(original) }
                    }
                } else {
                    openSafari(original)
                }
            case .safari:
                openSafari(original)
            }
        }
        finishWhenIdle()
    }

    private func openSafari(_ url: URL) {
        guard let safari = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") else {
            showFailure()
            completed()
            return
        }
        // Explicit Safari destination avoids a loop through the default browser.
        open(url, in: safari) { [self] success in
            if !success { showFailure() }
            completed()
        }
    }

    private func open(_ url: URL, in app: URL, completion: @escaping (Bool) -> Void) {
        NSWorkspace.shared.open([url], withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    private func showFailure() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Не удалось открыть ссылку"
        alert.informativeText = "Запустите Safari и вставьте исходную ссылку вручную."
        alert.runModal()
    }

    private func completed() {
        pending -= 1
        finishWhenIdle()
    }

    private func finishWhenIdle() {
        guard pending == 0 else { return }
        exitWork?.cancel()
        let work = DispatchWorkItem { NSApp.terminate(nil) }
        exitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

let application = NSApplication.shared
let delegate = RouterDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
