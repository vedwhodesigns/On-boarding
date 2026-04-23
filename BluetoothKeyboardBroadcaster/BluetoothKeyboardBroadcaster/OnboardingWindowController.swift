import Cocoa

// Shows once on first launch, walks the user through 4 steps.
final class OnboardingWindowController: NSWindowController {

    static let hasSeenKey = "hasSeenOnboarding"

    // Static reference keeps the window controller alive until dismissed
    private static var _instance: OnboardingWindowController?

    static func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: hasSeenKey) else { return }
        let wc = OnboardingWindowController()
        _instance = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Data

    private let steps: [(emoji: String, title: String, body: String)] = [
        (
            emoji: "⌨️",
            title: "Welcome to BT Keyboard Broadcaster",
            body: "This app turns your MacBook into a Bluetooth keyboard and mouse for any nearby device — Windows PC, iPad, Android, or anything with Bluetooth.\n\nIt lives in your menu bar and stays completely out of your way."
        ),
        (
            emoji: "🔐",
            title: "Grant Accessibility Permission",
            body: "To capture your keystrokes, the app needs Accessibility access.\n\n1. Click the button below\n2. Find Accessibility in the list\n3. Toggle ON 'BluetoothKeyboardBroadcaster'\n4. Come back here and click Next →"
        ),
        (
            emoji: "📡",
            title: "Start Broadcasting",
            body: "Click the  ⌨  icon in your Mac's menu bar (top-right corner of your screen).\n\nPress the big  ▶ Start Broadcasting  button.\n\nYour Mac will now appear as 'MacBook Keyboard' on nearby devices."
        ),
        (
            emoji: "✅",
            title: "Pair from Your Other Device",
            body: "On Windows:  Settings → Bluetooth → Add device → 'MacBook Keyboard'\n\nOn iPad/iPhone:  Settings → Bluetooth → 'MacBook Keyboard'\n\nOn Android:  Settings → Connected devices → Pair new device\n\nIf a PIN appears on that screen, type it on your MacBook and press Return."
        ),
    ]

    private var currentStep = 0

    // MARK: - Subviews
    private let emojiField  = makeField("", size: 48)
    private let titleField  = makeField("", size: 17, bold: true)
    private let bodyField   = makeField("", size: 13)
    private var dotViews: [NSView] = []
    private let privacyBtn  = NSButton()
    private let nextBtn     = NSButton()

    // MARK: - Init

    convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
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

    // MARK: - Layout

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        let W = cv.bounds.width    // 500
        let H = cv.bounds.height   // 420

        // Emoji
        emojiField.frame = NSRect(x: 0, y: H - 90, width: W, height: 70)
        emojiField.alignment = .center
        cv.addSubview(emojiField)

        // Title
        titleField.frame = NSRect(x: 32, y: H - 130, width: W - 64, height: 34)
        titleField.alignment = .center
        titleField.lineBreakMode = .byWordWrapping
        titleField.maximumNumberOfLines = 2
        cv.addSubview(titleField)

        // Body
        bodyField.frame = NSRect(x: 40, y: H - 310, width: W - 80, height: 168)
        bodyField.lineBreakMode = .byWordWrapping
        bodyField.maximumNumberOfLines = 10
        bodyField.textColor = .labelColor
        cv.addSubview(bodyField)

        // Progress dots (manually positioned)
        let dotSize: CGFloat = 8
        let dotSpacing: CGFloat = 12
        let totalDotsW = CGFloat(steps.count) * dotSize + CGFloat(steps.count - 1) * dotSpacing
        var dotX = (W - totalDotsW) / 2

        for i in 0..<steps.count {
            let dot = NSView(frame: NSRect(x: dotX, y: H - 328, width: dotSize, height: dotSize))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = (i == 0
                ? NSColor.controlAccentColor
                : NSColor.tertiaryLabelColor).cgColor
            cv.addSubview(dot)
            dotViews.append(dot)
            dotX += dotSize + dotSpacing
        }

        // Privacy & Security button (visible only on step 1)
        privacyBtn.frame = NSRect(x: (W - 260) / 2, y: H - 370, width: 260, height: 28)
        privacyBtn.bezelStyle = .rounded
        privacyBtn.title = "Open Privacy & Security →"
        privacyBtn.target = self
        privacyBtn.action = #selector(openPrivacy)
        privacyBtn.isHidden = true
        cv.addSubview(privacyBtn)

        // Next / Done button
        nextBtn.frame = NSRect(x: (W - 160) / 2, y: 20, width: 160, height: 36)
        nextBtn.bezelStyle = .rounded
        nextBtn.title = "Next →"
        nextBtn.font = .boldSystemFont(ofSize: 14)
        nextBtn.keyEquivalent = "\r"
        nextBtn.target = self
        nextBtn.action = #selector(nextTapped)
        cv.addSubview(nextBtn)
    }

    // MARK: - Step management

    private func showStep(_ step: Int) {
        currentStep = step
        let s = steps[step]

        emojiField.stringValue = s.emoji
        titleField.stringValue = s.title
        bodyField.stringValue  = s.body
        privacyBtn.isHidden    = (step != 1)
        nextBtn.title          = (step == steps.count - 1) ? "Get Started  ✓" : "Next →"

        for (i, dot) in dotViews.enumerated() {
            dot.layer?.backgroundColor = (i == step
                ? NSColor.controlAccentColor
                : NSColor.tertiaryLabelColor).cgColor
        }
    }

    // MARK: - Actions

    @objc private func nextTapped() {
        if currentStep < steps.count - 1 {
            showStep(currentStep + 1)
        } else {
            UserDefaults.standard.set(true, forKey: Self.hasSeenKey)
            window?.close()
            Self._instance = nil    // release after dismiss
        }
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
    }
}

// MARK: - Helpers

private func makeField(_ text: String, size: CGFloat, bold: Bool = false) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    f.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
    return f
}
