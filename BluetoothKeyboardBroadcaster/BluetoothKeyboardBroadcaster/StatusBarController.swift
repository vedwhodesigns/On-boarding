import Cocoa
import UserNotifications

final class StatusBarController: NSObject {

    // MARK: - Sub-systems
    let bluetoothManager    = BluetoothHIDManager()
    let keyboardInterceptor = KeyboardInterceptor()
    let mouseInterceptor    = MouseInterceptor()
    let notchIndicator      = NotchIndicatorController()

    // MARK: - UI
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverVC: PopoverViewController!

    // Icon animation
    private var iconTimer: Timer?
    private var iconPhase = false

    // State
    private(set) var isBroadcasting = false
    private var connectedDeviceName: String?
    private var currentState: BroadcastState = .idle

    private var mouseEnabled: Bool {
        !UserDefaults.standard.bool(forKey: Prefs.keyboardOnly)
    }
    private var deviceName: String {
        UserDefaults.standard.string(forKey: Prefs.deviceName) ?? "MacBook Keyboard"
    }

    // MARK: - Init

    override init() {
        super.init()
        bluetoothManager.delegate    = self
        keyboardInterceptor.delegate = self
        mouseInterceptor.delegate    = self

        setupStatusBar()
        setupPopover()
        wirePreferences()
        requestNotificationPermission()
    }

    // MARK: - Status bar icon

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        btn.image  = makeIcon(active: false, phase: false)
        btn.image?.isTemplate = true
        btn.toolTip = "Bluetooth Keyboard Broadcaster"
        btn.target  = self
        btn.action  = #selector(togglePopover(_:))
        btn.sendAction(on: .leftMouseUp)
    }

    // MARK: - Popover

    private func setupPopover() {
        popoverVC = PopoverViewController()
        popoverVC.onToggle      = { [weak self] in self?.toggleBroadcasting() }
        popoverVC.onPreferences = { [weak self] in
            self?.closePopover()
            PreferencesWindowController.shared.showPreferences()
        }

        popover = NSPopover()
        popover.contentViewController = popoverVC
        popover.behavior = .transient
        popover.animates = true
    }

    @objc private func togglePopover(_ sender: NSButton) {
        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func closePopover() {
        popover.close()
    }

    // MARK: - Broadcasting control

    func toggleBroadcasting() {
        isBroadcasting ? stopBroadcasting() : startBroadcasting()
    }

    private func startBroadcasting() {
        bluetoothManager.deviceName = deviceName
        bluetoothManager.mode = mouseEnabled ? .keyboardAndMouse : .keyboardOnly

        guard keyboardInterceptor.start() else {
            showAccessibilityAlert()
            return
        }
        if mouseEnabled { _ = mouseInterceptor.start() }

        bluetoothManager.startBroadcasting()
        isBroadcasting = true
        startIconAnimation()
        refreshPopover()

        notchIndicator.show(
            text: "📡  Broadcasting as \"\(deviceName)\"",
            color: .systemBlue,
            persistent: false
        )
    }

    private func stopBroadcasting() {
        keyboardInterceptor.stop()
        mouseInterceptor.stop()
        bluetoothManager.stopBroadcasting()
        isBroadcasting = false
        connectedDeviceName = nil
        stopIconAnimation()
        refreshPopover()
        notchIndicator.hide()
    }

    // MARK: - Icon animation (pulsing while advertising)

    private func startIconAnimation() {
        iconTimer?.invalidate()
        iconTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.iconPhase.toggle()
            let img = self.makeIcon(active: true, phase: self.iconPhase)
            img.isTemplate = false
            self.statusItem.button?.image = img
        }
        RunLoop.main.add(iconTimer!, forMode: .common)
    }

    private func stopIconAnimation() {
        iconTimer?.invalidate()
        iconTimer = nil
        let img = makeIcon(active: false, phase: false)
        img.isTemplate = true
        statusItem.button?.image = img
    }

    private func setConnectedIcon() {
        iconTimer?.invalidate()
        iconTimer = nil
        let img = makeIcon(active: true, phase: true)
        img.isTemplate = false
        statusItem.button?.image = img
    }

    // MARK: - Popover sync

    private func refreshPopover() {
        DispatchQueue.main.async {
            self.popoverVC.update(
                state: self.currentState,
                deviceName: self.deviceName,
                connectedDeviceName: self.connectedDeviceName,
                mouseEnabled: self.mouseEnabled
            )
        }
    }

    // MARK: - Preferences wiring

    private func wirePreferences() {
        PreferencesWindowController.shared.onSettingsChanged = { [weak self] in
            guard let self = self else { return }
            if self.isBroadcasting {
                self.stopBroadcasting()
                self.startBroadcasting()
            }
            self.refreshPopover()
        }
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Alert

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "BT Keyboard Broadcaster needs Accessibility access to capture keystrokes and mouse events.\n\nSystem Settings → Privacy & Security → Accessibility → toggle ON this app, then try again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    // MARK: - Icon drawing

    private func makeIcon(active: Bool, phase: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img  = NSImage(size: size)
        img.lockFocus()

        let baseAlpha: CGFloat = active ? (phase ? 1.0 : 0.5) : 1.0
        let stroke = active ? NSColor.systemBlue.withAlphaComponent(baseAlpha) : NSColor.labelColor
        stroke.setStroke()
        stroke.withAlphaComponent(active ? baseAlpha * 0.55 : 0.45).setFill()

        // Keyboard body
        let body = NSBezierPath(roundedRect: NSRect(x: 1, y: 4, width: 16, height: 10), xRadius: 2, yRadius: 2)
        body.lineWidth = 1.5
        body.stroke()

        // Key caps
        for i in 0..<3 {
            NSBezierPath(roundedRect: NSRect(x: 3 + CGFloat(i) * 4, y: 6.5, width: 3, height: 2.5), xRadius: 0.4, yRadius: 0.4).fill()
        }
        NSBezierPath(roundedRect: NSRect(x: 3, y: 10, width: 10, height: 2), xRadius: 0.4, yRadius: 0.4).fill()

        // Status dot: blue (advertising, pulsing) or green (connected)
        if active {
            let dotColor: NSColor = (currentState == .connected) ? .systemGreen : NSColor.systemBlue.withAlphaComponent(baseAlpha)
            dotColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 13.5, y: 12, width: 4, height: 4)).fill()
        }

        img.unlockFocus()
        return img
    }
}

// MARK: - BluetoothHIDManagerDelegate

extension StatusBarController: BluetoothHIDManagerDelegate {

    func stateDidChange(_ state: BroadcastState) {
        currentState = state

        switch state {
        case .idle:
            stopIconAnimation()

        case .advertising:
            startIconAnimation()

        case .connected:
            setConnectedIcon()

        case .error(let msg):
            stopBroadcasting()
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Bluetooth Error"
                alert.informativeText = msg
                alert.runModal()
            }
        }
        refreshPopover()
    }

    func deviceConnected(_ name: String) {
        connectedDeviceName = name
        currentState = .connected
        setConnectedIcon()
        refreshPopover()

        notchIndicator.show(text: "✓  Connected to \(name)", color: .systemGreen, persistent: false)
        sendNotification(title: "Keyboard Connected", body: "\(name) is now using your MacBook keyboard and mouse.")
    }

    func deviceDisconnected(_ name: String) {
        connectedDeviceName = nil
        currentState = .advertising
        startIconAnimation()
        refreshPopover()

        notchIndicator.show(text: "⚡  \(name) disconnected", color: .systemOrange, persistent: false)
        sendNotification(title: "Device Disconnected", body: "\(name) disconnected. Broadcasting again…")
    }

    func pairedDevicesUpdated(_ devices: [PairedDevice]) {}
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
