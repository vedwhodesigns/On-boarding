import Cocoa

// Shows once on first launch, walks the user through 4 steps.
final class OnboardingWindowController: NSWindowController {

    static let hasSeenKey = "hasSeenOnboarding"

    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasSeenKey) else { return }
        let wc = OnboardingWindowController()
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var currentStep = 0
    private let steps: [(title: String, body: String, image: String)] = [
        (
            title: "Welcome to BT Keyboard Broadcaster",
            body: "This app turns your MacBook into a Bluetooth keyboard and mouse for any nearby device — Windows PC, iPad, Android, or anything else with Bluetooth.\n\nIt lives in your menu bar and stays out of your way.",
            image: "🖥️"
        ),
        (
            title: "Step 1 — Grant Accessibility",
            body: "To capture your keystrokes, the app needs Accessibility permission.\n\n1. Click 'Open Privacy & Security' below\n2. Go to Accessibility in the list\n3. Toggle ON 'BluetoothKeyboardBroadcaster'\n4. Come back here and click Next",
            image: "🔐"
        ),
        (
            title: "Step 2 — Start Broadcasting",
            body: "Click the keyboard icon  ⌨  in your Mac's menu bar (top-right of screen).\n\nThen press the big  ▶ Start Broadcasting  button.\n\nYour Mac will appear as 'MacBook Keyboard' on nearby devices.",
            image: "📡"
        ),
        (
            title: "Step 3 — Pair from your other device",
            body: "On your Windows PC / iPad / Android:\n\n1. Open Bluetooth Settings\n2. Click 'Add device' or 'Pair new device'\n3. Select 'MacBook Keyboard' from the list\n4. If a PIN appears on that screen, type it on your MacBook and press Return\n\nThat's it — you're connected!",
            image: "✅"
        ),
    ]

    private let emojiLabel   = NSTextField(labelWithString: "")
    private let titleLabel   = NSTextField(labelWithString: "")
    private let bodyLabel    = NSTextField(labelWithString: "")
    private let progressDots = NSStackView()
    private let nextBtn      = NSButton()
    private let privacyBtn   = NSButton()

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Getting Started"
        win.isReleasedWhenClosed = false
        win.center()
        self.init(window: win)
        buildUI()
        showStep(0)
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let W = content.bounds.width
        var y: CGFloat = content.bounds.height

        // Emoji / illustration
        y -= 20
        emojiLabel.frame = NSRect(x: 0, y: y - 70, width: W, height: 70)
        emojiLabel.alignment = .center
        emojiLabel.font = .systemFont(ofSize: 52)
        content.addSubview(emojiLabel)
        y -= 80

        // Title
        y -= 8
        titleLabel.frame = NSRect(x: 32, y: y - 28, width: W - 64, height: 28)
        titleLabel.alignment = .center
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        content.addSubview(titleLabel)
        y -= 38

        // Body text
        y -= 10
        bodyLabel.frame = NSRect(x: 40, y: y - 140, width: W - 80, height: 140)
        bodyLabel.alignment = .left
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .labelColor
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.maximumNumberOfLines = 10
        content.addSubview(bodyLabel)
        y -= 148

        // Progress dots
        progressDots.frame = NSRect(x: 0, y: y - 20, width: W, height: 14)
        progressDots.orientation = .horizontal
        progressDots.distribution = .equalCentering
        progressDots.spacing = 8
        for i in 0..<steps.count {
            let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = (i == 0 ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).cgColor
            dot.identifier = NSUserInterfaceItemIdentifier(rawValue: "\(i)")
            progressDots.addArrangedSubview(dot)
        }
        content.addSubview(progressDots)
        y -= 30

        // Privacy button (shown only on step 1)
        privacyBtn.frame = NSRect(x: 40, y: y - 32, width: W - 80, height: 28)
        privacyBtn.bezelStyle = .rounded
        privacyBtn.title = "Open Privacy & Security →"
        privacyBtn.target = self
        privacyBtn.action = #selector(openPrivacy)
        privacyBtn.isHidden = true
        content.addSubview(privacyBtn)
        y -= 40

        // Next / Done button
        nextBtn.frame = NSRect(x: (W - 160) / 2, y: 20, width: 160, height: 36)
        nextBtn.bezelStyle = .rounded
        nextBtn.title = "Next →"
        nextBtn.font = .boldSystemFont(ofSize: 14)
        nextBtn.keyEquivalent = "\r"
        nextBtn.target = self
        nextBtn.action = #selector(nextTapped)
        content.addSubview(nextBtn)
    }

    private func showStep(_ step: Int) {
        currentStep = step
        let s = steps[step]
        emojiLabel.stringValue = s.image
        titleLabel.stringValue = s.title
        bodyLabel.stringValue  = s.body

        // Privacy button only on step 1
        privacyBtn.isHidden = (step != 1)

        // Update dots
        for (i, view) in progressDots.arrangedSubviews.enumerated() {
            view.layer?.backgroundColor = (i == step
                ? NSColor.controlAccentColor
                : NSColor.tertiaryLabelColor).cgColor
        }

        nextBtn.title = (step == steps.count - 1) ? "Get Started ✓" : "Next →"
    }

    @objc private func nextTapped() {
        if currentStep < steps.count - 1 {
            showStep(currentStep + 1)
        } else {
            UserDefaults.standard.set(true, forKey: Self.hasSeenKey)
            window?.close()
        }
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}
