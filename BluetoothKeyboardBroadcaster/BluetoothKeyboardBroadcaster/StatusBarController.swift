import Cocoa

final class StatusBarController: NSObject {

    let bluetoothManager = BluetoothHIDManager()
    let keyboardInterceptor = KeyboardInterceptor()

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // Menu items
    private var toggleItem: NSMenuItem!
    private var statusItem2: NSMenuItem!
    private var pairedDevicesMenu: NSMenu!
    private var pairedDevicesItem: NSMenuItem!

    private var isBroadcasting = false

    override init() {
        super.init()
        setupStatusBar()
        bluetoothManager.delegate = self
        keyboardInterceptor.delegate = self
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else { return }
        button.image = statusBarImage(active: false)
        button.image?.isTemplate = true
        button.toolTip = "Bluetooth Keyboard Broadcaster"

        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        menu = NSMenu()

        // App title (non-clickable header)
        let title = NSMenuItem(title: "BT Keyboard Broadcaster", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        menu.addItem(.separator())

        // Current status line
        statusItem2 = NSMenuItem(title: "Status: Idle", action: nil, keyEquivalent: "")
        statusItem2.isEnabled = false
        menu.addItem(statusItem2)

        menu.addItem(.separator())

        // Toggle broadcasting
        toggleItem = NSMenuItem(
            title: "Start Broadcasting",
            action: #selector(toggleBroadcasting),
            keyEquivalent: "b"
        )
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Paired devices submenu
        pairedDevicesItem = NSMenuItem(title: "Paired Devices", action: nil, keyEquivalent: "")
        pairedDevicesMenu = NSMenu()
        let noneItem = NSMenuItem(title: "No devices paired yet", action: nil, keyEquivalent: "")
        noneItem.isEnabled = false
        pairedDevicesMenu.addItem(noneItem)
        pairedDevicesItem.submenu = pairedDevicesMenu
        menu.addItem(pairedDevicesItem)

        menu.addItem(.separator())

        // Bluetooth permissions note
        let permNote = NSMenuItem(title: "Requires Accessibility permission", action: nil, keyEquivalent: "")
        permNote.isEnabled = false
        menu.addItem(permNote)

        let openPrivacy = NSMenuItem(
            title: "Open Privacy & Security...",
            action: #selector(openPrivacyPrefs),
            keyEquivalent: ""
        )
        openPrivacy.target = self
        menu.addItem(openPrivacy)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    @objc private func toggleBroadcasting() {
        if isBroadcasting {
            stopBroadcasting()
        } else {
            startBroadcasting()
        }
    }

    private func startBroadcasting() {
        let started = keyboardInterceptor.start()
        if !started {
            showPermissionAlert()
            return
        }
        bluetoothManager.startBroadcasting()
        isBroadcasting = true
        toggleItem.title = "Stop Broadcasting"
        updateStatusBarIcon(active: true)
    }

    private func stopBroadcasting() {
        keyboardInterceptor.stop()
        bluetoothManager.stopBroadcasting()
        isBroadcasting = false
        toggleItem.title = "Start Broadcasting"
        updateStatusBarIcon(active: false)
        updateStatusLabel("Idle")
    }

    private func updateStatusLabel(_ text: String) {
        DispatchQueue.main.async {
            self.statusItem2.title = "Status: \(text)"
        }
    }

    private func updateStatusBarIcon(active: Bool) {
        DispatchQueue.main.async {
            self.statusItem.button?.image = self.statusBarImage(active: active)
        }
    }

    private func statusBarImage(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let color: NSColor = active ? .systemBlue : .labelColor
        color.setStroke()
        color.setFill()

        // Draw a simple keyboard outline icon
        let rect = NSRect(x: 1, y: 4, width: 16, height: 10)
        let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
        path.lineWidth = 1.5
        path.stroke()

        // Draw three small key rectangles
        let keyColor: NSColor = active ? NSColor.systemBlue.withAlphaComponent(0.6) : NSColor.labelColor.withAlphaComponent(0.5)
        keyColor.setFill()
        for i in 0..<3 {
            let keyRect = NSRect(x: 3 + i * 4, y: 6, width: 3, height: 2.5)
            NSBezierPath(roundedRect: keyRect, xRadius: 0.5, yRadius: 0.5).fill()
        }
        // Space bar
        let spaceRect = NSRect(x: 3, y: 9.5, width: 10, height: 2)
        NSBezierPath(roundedRect: spaceRect, xRadius: 0.5, yRadius: 0.5).fill()

        // BT dot indicator when active
        if active {
            NSColor.systemGreen.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: 14, y: 12, width: 3, height: 3))
            dot.fill()
        }

        image.unlockFocus()
        image.isTemplate = !active
        return image
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Bluetooth Keyboard Broadcaster needs Accessibility access to intercept keyboard events.\n\nGo to System Settings → Privacy & Security → Accessibility and enable this app."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            openPrivacyPrefs()
        }
    }

    @objc private func openPrivacyPrefs() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func removeDevice(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? PairedDevice else { return }
        bluetoothManager.removePairedDevice(device)
    }

    private func rebuildPairedDevicesMenu(_ devices: [PairedDevice]) {
        pairedDevicesMenu.removeAllItems()
        if devices.isEmpty {
            let none = NSMenuItem(title: "No devices paired yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            pairedDevicesMenu.addItem(none)
        } else {
            for device in devices {
                let item = NSMenuItem(title: device.name, action: #selector(removeDevice(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = device
                item.toolTip = "Click to remove this device"
                pairedDevicesMenu.addItem(item)
            }
        }
    }
}

// MARK: - BluetoothHIDManagerDelegate
extension StatusBarController: BluetoothHIDManagerDelegate {

    func stateDidChange(_ state: BroadcastState) {
        switch state {
        case .idle:
            updateStatusLabel("Idle")
        case .advertising:
            updateStatusLabel("Advertising — waiting for connection")
        case .connected:
            updateStatusLabel("Connected")
        case .error(let msg):
            updateStatusLabel("Error: \(msg)")
            DispatchQueue.main.async {
                if self.isBroadcasting {
                    self.stopBroadcasting()
                }
                let alert = NSAlert()
                alert.messageText = "Bluetooth Error"
                alert.informativeText = msg
                alert.runModal()
            }
        }
    }

    func deviceConnected(_ name: String) {
        updateStatusLabel("Connected to \(name)")
    }

    func deviceDisconnected(_ name: String) {
        updateStatusLabel("Disconnected from \(name) — re-advertising")
    }

    func pairedDevicesUpdated(_ devices: [PairedDevice]) {
        DispatchQueue.main.async {
            self.rebuildPairedDevicesMenu(devices)
        }
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
