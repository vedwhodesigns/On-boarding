import Cocoa

final class PopoverViewController: NSViewController {

    // MARK: - Callbacks set by StatusBarController
    var onToggle: (() -> Void)?
    var onPreferences: (() -> Void)?

    // MARK: - Subviews
    private let indicator   = StatusIndicatorView(frame: .zero)
    private let stateLabel  = label("", size: 18, bold: true)
    private let subLabel    = label("", size: 13)
    private let actionBtn   = NSButton()

    // Instructions (shown while advertising)
    private let instructionStack = NSView()
    private let step1 = stepLabel("1  Open Bluetooth Settings on your other device")
    private let step2 = stepLabel("2  Choose 'Add device' → 'Bluetooth'")
    private let step3 = stepLabel("3  Select  \"MacBook Keyboard\"  from the list")
    private let step4 = stepLabel("4  If asked, type the PIN shown on that device here, then press Return")

    // Connected info (shown when connected)
    private let connectedBox  = NSView()
    private let kbdStatus    = checkLabel("Keyboard active")
    private let mouseStatus  = checkLabel("Mouse & trackpad active")
    private let tipLabel     = label("Press ⌘⇧B to stop broadcasting", size: 11)

    // MARK: - View loading

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 370))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildLayout()
        applyIdleState(deviceName: "MacBook Keyboard")
    }

    // MARK: - Public update method

    func update(state: BroadcastState, deviceName: String, connectedDeviceName: String?, mouseEnabled: Bool) {
        switch state {
        case .idle:
            indicator.indicatorState = .idle
            stateLabel.stringValue   = "Ready to Broadcast"
            subLabel.stringValue     = "Your keyboard and trackpad will\ncontrol the connected device"
            actionBtn.title          = "▶  Start Broadcasting"
            actionBtn.contentTintColor = .controlAccentColor
            showSection(.none)

        case .advertising:
            indicator.indicatorState = .advertising
            stateLabel.stringValue   = "Discoverable"
            subLabel.stringValue     = "Visible as \"\(deviceName)\"\nWaiting for a device to connect…"
            actionBtn.title          = "■  Stop Broadcasting"
            actionBtn.contentTintColor = .secondaryLabelColor
            showSection(.instructions)

        case .connected:
            indicator.indicatorState = .connected
            stateLabel.stringValue   = "Connected"
            subLabel.stringValue     = connectedDeviceName ?? "Device active"
            actionBtn.title          = "■  Stop Broadcasting"
            actionBtn.contentTintColor = .secondaryLabelColor
            mouseStatus.isHidden     = !mouseEnabled
            showSection(.connected)

        case .error(let msg):
            indicator.indicatorState = .idle
            stateLabel.stringValue   = "Error"
            subLabel.stringValue     = msg
            actionBtn.title          = "▶  Try Again"
            actionBtn.contentTintColor = .systemRed
            showSection(.none)
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        let W: CGFloat = view.bounds.width
        var y: CGFloat = view.bounds.height

        // ── Status circle ──────────────────────────────────────────────────
        let circleSize: CGFloat = 72
        y -= 20 + circleSize
        indicator.frame = NSRect(x: (W - circleSize) / 2, y: y, width: circleSize, height: circleSize)
        view.addSubview(indicator)

        // ── State title ────────────────────────────────────────────────────
        y -= 28
        stateLabel.alignment = .center
        stateLabel.frame = NSRect(x: 16, y: y, width: W - 32, height: 22)
        view.addSubview(stateLabel)

        // ── Subtitle ───────────────────────────────────────────────────────
        y -= 38
        subLabel.alignment = .center
        subLabel.textColor = .secondaryLabelColor
        subLabel.lineBreakMode = .byWordWrapping
        subLabel.maximumNumberOfLines = 3
        subLabel.frame = NSRect(x: 16, y: y, width: W - 32, height: 34)
        view.addSubview(subLabel)

        // ── Action button ──────────────────────────────────────────────────
        y -= 46
        actionBtn.frame = NSRect(x: 36, y: y, width: W - 72, height: 36)
        actionBtn.bezelStyle = .rounded
        actionBtn.font = .boldSystemFont(ofSize: 13)
        actionBtn.target = self
        actionBtn.action = #selector(toggleTapped)
        view.addSubview(actionBtn)

        // ── Top separator ──────────────────────────────────────────────────
        y -= 16
        addSeparator(at: y)
        y -= 1

        // ── Instructions section ───────────────────────────────────────────
        let instrHeight: CGFloat = 112
        y -= instrHeight
        instructionStack.frame = NSRect(x: 20, y: y, width: W - 40, height: instrHeight)
        instructionStack.isHidden = true

        let instrHeader = label("How to connect from any device:", size: 11)
        instrHeader.textColor = .tertiaryLabelColor
        instrHeader.frame = NSRect(x: 0, y: instrHeight - 16, width: instructionStack.bounds.width, height: 14)
        instructionStack.addSubview(instrHeader)

        let steps = [step1, step2, step3, step4]
        for (i, s) in steps.enumerated() {
            s.frame = NSRect(x: 0, y: instrHeight - 34 - CGFloat(i) * 22, width: instructionStack.bounds.width, height: 20)
            s.lineBreakMode = .byWordWrapping
            s.maximumNumberOfLines = 2
            instructionStack.addSubview(s)
        }
        view.addSubview(instructionStack)

        // ── Connected section ──────────────────────────────────────────────
        connectedBox.frame = NSRect(x: 20, y: y, width: W - 40, height: instrHeight)
        connectedBox.isHidden = true

        kbdStatus.frame   = NSRect(x: 0, y: instrHeight - 28, width: connectedBox.bounds.width, height: 20)
        mouseStatus.frame = NSRect(x: 0, y: instrHeight - 52, width: connectedBox.bounds.width, height: 20)
        tipLabel.frame    = NSRect(x: 0, y: 0, width: connectedBox.bounds.width, height: 16)
        tipLabel.textColor = .tertiaryLabelColor
        tipLabel.alignment = .center

        connectedBox.addSubview(kbdStatus)
        connectedBox.addSubview(mouseStatus)
        connectedBox.addSubview(tipLabel)
        view.addSubview(connectedBox)

        // ── Bottom separator ───────────────────────────────────────────────
        y -= 12
        addSeparator(at: y)
        y -= 1

        // ── Bottom bar ─────────────────────────────────────────────────────
        y -= 34
        let prefsBtn = bottomBtn("⚙  Preferences", action: #selector(prefsTapped))
        prefsBtn.frame = NSRect(x: 16, y: y + 4, width: 130, height: 26)
        view.addSubview(prefsBtn)

        let quitBtn = bottomBtn("Quit", action: #selector(quitTapped))
        quitBtn.frame = NSRect(x: W - 70, y: y + 4, width: 54, height: 26)
        view.addSubview(quitBtn)
    }

    private func addSeparator(at y: CGFloat) {
        let sep = NSBox()
        sep.boxType = .separator
        sep.frame = NSRect(x: 16, y: y, width: view.bounds.width - 32, height: 1)
        view.addSubview(sep)
    }

    // MARK: - Section switching

    private enum Section { case none, instructions, connected }

    private func showSection(_ section: Section) {
        instructionStack.isHidden = section != .instructions
        connectedBox.isHidden     = section != .connected
    }

    // MARK: - State helpers

    private func applyIdleState(deviceName: String) {
        update(state: .idle, deviceName: deviceName, connectedDeviceName: nil, mouseEnabled: true)
    }

    // MARK: - Actions

    @objc private func toggleTapped()  { onToggle?() }
    @objc private func prefsTapped()   { onPreferences?() }
    @objc private func quitTapped()    { NSApp.terminate(nil) }
}

// MARK: - View factory helpers (file-private)

private func label(_ text: String, size: CGFloat, bold: Bool = false) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    return f
}

private func stepLabel(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = .systemFont(ofSize: 12)
    f.textColor = .labelColor
    return f
}

private func checkLabel(_ text: String) -> NSTextField {
    let f = NSTextField(labelWithString: "✓  " + text)
    f.font = .systemFont(ofSize: 13)
    f.textColor = .systemGreen
    return f
}

private func bottomBtn(_ title: String, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: nil, action: action)
    b.bezelStyle = .inline
    b.font = .systemFont(ofSize: 12)
    return b
}
