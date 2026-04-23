import Cocoa
import ServiceManagement

// UserDefaults keys
enum Prefs {
    static let deviceName    = "deviceName"
    static let keyboardOnly  = "keyboardOnly"
    static let launchAtLogin = "launchAtLogin"
}

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    static let shared = PreferencesWindowController()

    private var deviceNameField: NSTextField!
    private var keyboardOnlyCheck: NSButton!
    private var launchAtLoginCheck: NSButton!
    private var versionLabel: NSTextField!

    // Called by StatusBarController when the user changes mode at runtime
    var onSettingsChanged: (() -> Void)?

    // MARK: - Init

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Bluetooth Keyboard Broadcaster — Preferences"
        window.isReleasedWhenClosed = false
        window.level = .floating
        self.init(window: window)
        window.delegate = self
        buildUI()
        loadPrefs()
    }

    // MARK: - Show

    func showPreferences() {
        loadPrefs()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let padding: CGFloat = 24
        var y: CGFloat = 240

        // ── Section: Device ────────────────────────────────────────────────
        addLabel("Device Settings", frame: NSRect(x: padding, y: y, width: 200, height: 20),
                 bold: true, to: content)
        y -= 30

        addLabel("Advertised name:", frame: NSRect(x: padding, y: y, width: 140, height: 22), to: content)
        deviceNameField = NSTextField(frame: NSRect(x: 172, y: y, width: 220, height: 22))
        deviceNameField.placeholderString = "MacBook Keyboard"
        content.addSubview(deviceNameField)
        y -= 36

        // ── Section: Input ─────────────────────────────────────────────────
        addLabel("Input Mode", frame: NSRect(x: padding, y: y, width: 200, height: 20),
                 bold: true, to: content)
        y -= 28

        keyboardOnlyCheck = NSButton(checkboxWithTitle: "Keyboard only (disable mouse broadcasting)",
                                     target: self, action: nil)
        keyboardOnlyCheck.frame = NSRect(x: padding, y: y, width: 380, height: 20)
        content.addSubview(keyboardOnlyCheck)
        y -= 10

        let note = addLabel(
            "Keyboard + Mouse mode forwards trackpad movement, clicks, and scroll to the connected device.",
            frame: NSRect(x: padding + 20, y: y - 26, width: 360, height: 36),
            to: content
        )
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        y -= 52

        // ── Section: Startup ───────────────────────────────────────────────
        addLabel("Startup", frame: NSRect(x: padding, y: y, width: 200, height: 20),
                 bold: true, to: content)
        y -= 28

        launchAtLoginCheck = NSButton(checkboxWithTitle: "Launch at login",
                                      target: self, action: nil)
        launchAtLoginCheck.frame = NSRect(x: padding, y: y, width: 260, height: 20)
        content.addSubview(launchAtLoginCheck)
        y -= 36

        // ── Buttons ────────────────────────────────────────────────────────
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.frame = NSRect(x: content.bounds.width - 2 * 90 - padding - 8, y: 16, width: 80, height: 28)
        cancelBtn.keyEquivalent = "\u{1B}"
        content.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.frame = NSRect(x: content.bounds.width - 90 - padding, y: 16, width: 80, height: 28)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        content.addSubview(saveBtn)

        // ── Version ────────────────────────────────────────────────────────
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        versionLabel = addLabel(
            "Bluetooth Keyboard Broadcaster v\(version)",
            frame: NSRect(x: padding, y: 18, width: 260, height: 18),
            to: content
        )
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.font = .systemFont(ofSize: 11)
    }

    @discardableResult
    private func addLabel(_ text: String, frame: NSRect, bold: Bool = false,
                           to view: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        label.lineBreakMode = .byWordWrapping
        view.addSubview(label)
        return label
    }

    // MARK: - Load / Save

    private func loadPrefs() {
        let defaults = UserDefaults.standard
        deviceNameField.stringValue = defaults.string(forKey: Prefs.deviceName) ?? "MacBook Keyboard"
        keyboardOnlyCheck.state   = defaults.bool(forKey: Prefs.keyboardOnly)  ? .on : .off
        launchAtLoginCheck.state  = defaults.bool(forKey: Prefs.launchAtLogin) ? .on : .off
    }

    @objc private func save() {
        let defaults = UserDefaults.standard
        let name = deviceNameField.stringValue.trimmingCharacters(in: .whitespaces)
        defaults.set(name.isEmpty ? "MacBook Keyboard" : name, forKey: Prefs.deviceName)
        defaults.set(keyboardOnlyCheck.state == .on,  forKey: Prefs.keyboardOnly)
        defaults.set(launchAtLoginCheck.state == .on, forKey: Prefs.launchAtLogin)

        applyLaunchAtLogin(launchAtLoginCheck.state == .on)
        onSettingsChanged?()
        window?.close()
    }

    @objc private func cancel() {
        window?.close()
    }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                showLaunchAtLoginFallback(enable: enable)
            }
        } else {
            showLaunchAtLoginFallback(enable: enable)
        }
    }

    private func showLaunchAtLoginFallback(enable: Bool) {
        if enable {
            let alert = NSAlert()
            alert.messageText = "Manual Login Item Required"
            alert.informativeText = "On macOS 12, add this app manually:\nSystem Preferences → Users & Groups → Login Items → click + and select Bluetooth Keyboard Broadcaster."
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.users")!
                )
            }
        }
    }
}
