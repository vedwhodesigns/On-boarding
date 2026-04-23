import Cocoa

final class StatusBarController: NSObject {

    let bluetoothManager = BluetoothHIDManager()
    let keyboardInterceptor = KeyboardInterceptor()
    let mouseInterceptor = MouseInterceptor()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Dynamic menu items
    private var toggleItem: NSMenuItem!
    private var statusLineItem: NSMenuItem!
    private var mouseToggleItem: NSMenuItem!
    private var pairedMenu: NSMenu!
    private var connectedCountItem: NSMenuItem!

    private(set) var isBroadcasting = false
    private var mouseEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: Prefs.keyboardOnly) }
    }

    override init() {
        super.init()
        bluetoothManager.delegate = self
        keyboardInterceptor.delegate = self
        mouseInterceptor.delegate = self

        setupStatusBar()
        wirePreferences()
    }

    // MARK: - Status bar setup

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = makeIcon(active: false)
        button.image?.isTemplate = true
        button.toolTip = "Bluetooth Keyboard Broadcaster"
        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        menu = NSMenu()

        // ── Header ──────────────────────────────────────────────────────────
        let header = NSMenuItem(title: "BT Keyboard Broadcaster", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // ── Status line ────────────────────────────────────────────────────
        statusLineItem = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusLineItem.isEnabled = false
        menu.addItem(statusLineItem)

        connectedCountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        connectedCountItem.isEnabled = false
        connectedCountItem.isHidden = true
        menu.addItem(connectedCountItem)
        menu.addItem(.separator())

        // ── Toggle ─────────────────────────────────────────────────────────
        toggleItem = NSMenuItem(
            title: "Start Broadcasting",
            action: #selector(toggleBroadcasting),
            keyEquivalent: "b"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = self
        menu.addItem(toggleItem)

        // ── Mouse toggle ───────────────────────────────────────────────────
        mouseToggleItem = NSMenuItem(
            title: mouseEnabled ? "Disable Mouse Broadcasting" : "Enable Mouse Broadcasting",
            action: #selector(toggleMouse),
            keyEquivalent: ""
        )
        mouseToggleItem.target = self
        menu.addItem(mouseToggleItem)
        menu.addItem(.separator())

        // ── Paired devices submenu ─────────────────────────────────────────
        let pairedItem = NSMenuItem(title: "Paired Devices", action: nil, keyEquivalent: "")
        pairedMenu = NSMenu()
        refreshPairedMenu([])
        pairedItem.submenu = pairedMenu
        menu.addItem(pairedItem)
        menu.addItem(.separator())

        // ── Preferences ────────────────────────────────────────────────────
        let prefsItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)
        menu.addItem(.separator())

        // ── Permissions ────────────────────────────────────────────────────
        let privacyItem = NSMenuItem(
            title: "Open Privacy & Security...",
            action: #selector(openPrivacy),
            keyEquivalent: ""
        )
        privacyItem.target = self
        menu.addItem(privacyItem)
        menu.addItem(.separator())

        // ── Quit ───────────────────────────────────────────────────────────
        let quitItem = NSMenuItem(
            title: "Quit Bluetooth Keyboard Broadcaster",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func toggleBroadcasting() {
        isBroadcasting ? stopBroadcasting() : startBroadcasting()
    }

    private func startBroadcasting() {
        // Refresh settings from prefs before starting
        bluetoothManager.deviceName = UserDefaults.standard.string(forKey: Prefs.deviceName) ?? "MacBook Keyboard"
        bluetoothManager.mode = UserDefaults.standard.bool(forKey: Prefs.keyboardOnly) ? .keyboardOnly : .keyboardAndMouse

        guard keyboardInterceptor.start() else {
            showAccessibilityAlert()
            return
        }
        if mouseEnabled { _ = mouseInterceptor.start() }

        bluetoothManager.startBroadcasting()
        isBroadcasting = true
        toggleItem.title = "Stop Broadcasting"
        setIcon(active: true)
        updateMouseToggleTitle()
    }

    private func stopBroadcasting() {
        keyboardInterceptor.stop()
        mouseInterceptor.stop()
        bluetoothManager.stopBroadcasting()
        isBroadcasting = false
        toggleItem.title = "Start Broadcasting"
        setIcon(active: false)
        setStatus("Idle")
        connectedCountItem.isHidden = true
    }

    @objc private func toggleMouse() {
        let nowEnabled = mouseEnabled
        UserDefaults.standard.set(nowEnabled, forKey: Prefs.keyboardOnly) // flip: keyboardOnly = !mouseEnabled
        if isBroadcasting {
            if nowEnabled {
                // was enabled, now disabling
                mouseInterceptor.stop()
            } else {
                _ = mouseInterceptor.start()
            }
        }
        updateMouseToggleTitle()
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showPreferences()
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }

    @objc private func removeDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? PairedDevice else { return }
        bluetoothManager.removePairedDevice(device)
    }

    // MARK: - Preferences wiring

    private func wirePreferences() {
        PreferencesWindowController.shared.onSettingsChanged = { [weak self] in
            guard let self else { return }
            self.updateMouseToggleTitle()
            if self.isBroadcasting {
                // Re-apply immediately: stop and restart with new settings
                self.stopBroadcasting()
                self.startBroadcasting()
            }
        }
    }

    // MARK: - UI helpers

    private func setStatus(_ text: String) {
        DispatchQueue.main.async { self.statusLineItem.title = "Status: \(text)" }
    }

    private func setIcon(active: Bool) {
        DispatchQueue.main.async {
            self.statusItem.button?.image = self.makeIcon(active: active)
            self.statusItem.button?.image?.isTemplate = !active
        }
    }

    private func updateMouseToggleTitle() {
        DispatchQueue.main.async {
            self.mouseToggleItem.title = self.mouseEnabled
                ? "Disable Mouse Broadcasting"
                : "Enable Mouse Broadcasting"
        }
    }

    private func refreshPairedMenu(_ devices: [PairedDevice]) {
        pairedMenu.removeAllItems()
        if devices.isEmpty {
            let none = NSMenuItem(title: "No devices paired yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            pairedMenu.addItem(none)
        } else {
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(removeDevice(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device
                item.toolTip = "Click to remove \(device.name)"
                pairedMenu.addItem(item)
            }
            pairedMenu.addItem(.separator())
            let clear = NSMenuItem(title: "Remove All", action: #selector(removeAllDevices), keyEquivalent: "")
            clear.target = self
            pairedMenu.addItem(clear)
        }
    }

    @objc private func removeAllDevices() {
        for device in bluetoothManager.pairedDevices {
            bluetoothManager.removePairedDevice(device)
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Bluetooth Keyboard Broadcaster needs Accessibility access to capture keystrokes and mouse events.\n\nGo to: System Settings → Privacy & Security → Accessibility\n\nThen enable Bluetooth Keyboard Broadcaster and try again."
        alert.addButton(withTitle: "Open Privacy & Security")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { openPrivacy() }
    }

    // MARK: - Icon drawing

    private func makeIcon(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img  = NSImage(size: size)
        img.lockFocus()

        let stroke: NSColor = active ? .systemBlue : .labelColor
        stroke.setStroke()

        // Keyboard outline
        let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 16, height: 10),
                                xRadius: 2, yRadius: 2)
        body.lineWidth = 1.5
        body.stroke()

        // Key caps
        let keyFill: NSColor = active
            ? NSColor.systemBlue.withAlphaComponent(0.55)
            : NSColor.labelColor.withAlphaComponent(0.45)
        keyFill.setFill()
        for i in 0..<3 {
            NSBezierPath(roundedRect: NSRect(x: 3 + CGFloat(i) * 4, y: 6.5, width: 3, height: 2.5),
                         xRadius: 0.4, yRadius: 0.4).fill()
        }
        // Space bar
        NSBezierPath(roundedRect: NSRect(x: 3, y: 10, width: 10, height: 2),
                     xRadius: 0.4, yRadius: 0.4).fill()

        // Green dot when active
        if active {
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: NSRect(x: 14, y: 12, width: 3.5, height: 3.5)).fill()
        }

        img.unlockFocus()
        img.isTemplate = !active
        return img
    }
}

// MARK: - BluetoothHIDManagerDelegate

extension StatusBarController: BluetoothHIDManagerDelegate {

    func stateDidChange(_ state: BroadcastState) {
        switch state {
        case .idle:
            setStatus("Idle")
        case .advertising:
            setStatus("Advertising — discoverable as \"\(bluetoothManager.deviceName)\"")
        case .connected:
            setStatus("Connected")
        case .error(let msg):
            setStatus("Error")
            DispatchQueue.main.async {
                if self.isBroadcasting { self.stopBroadcasting() }
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Bluetooth Error"
                alert.informativeText = msg
                alert.runModal()
            }
        }
    }

    func deviceConnected(_ name: String) {
        setStatus("Connected to \(name)")
        DispatchQueue.main.async {
            self.connectedCountItem.title = "  \(name) — active"
            self.connectedCountItem.isHidden = false
        }
    }

    func deviceDisconnected(_ name: String) {
        setStatus("Advertising — \(name) disconnected")
        DispatchQueue.main.async { self.connectedCountItem.isHidden = true }
    }

    func pairedDevicesUpdated(_ devices: [PairedDevice]) {
        DispatchQueue.main.async { self.refreshPairedMenu(devices) }
    }
}

// MARK: - KeyboardInterceptorDelegate

extension StatusBarController: KeyboardInterceptorDelegate {
    func keyEvent(hidKeycode: UInt8, modifiers: UInt8, isKeyDown: Bool) {
        bluetoothManager.sendKeyEvent(hidKeycode: hidKeycode, modifiers: modifiers, isKeyDown: isKeyDown)
    }
    func modifiersChanged(modifiers: UInt8) {
        bluetoothManager.sendModifierOnly(modifiers: modifiers)
    }
}

// MARK: - MouseInterceptorDelegate

extension StatusBarController: MouseInterceptorDelegate {
    func mouseReport(buttons: UInt8, deltaX: Int8, deltaY: Int8, wheel: Int8) {
        bluetoothManager.sendMouseReport(buttons: buttons, deltaX: deltaX, deltaY: deltaY, wheel: wheel)
    }
}
