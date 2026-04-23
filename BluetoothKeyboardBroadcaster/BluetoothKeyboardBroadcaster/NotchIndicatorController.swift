import Cocoa

// Slides a Dynamic-Island-style pill in from the top of the screen
// (or from the notch on MacBook Pro/Air notch models) to show status changes.
// Falls back gracefully on non-notch Macs — pill appears at screen top-center.

final class NotchIndicatorController {

    private var window: NSWindow?
    private var pillView: NotchPillView?
    private var hideTimer: Timer?
    private var isShowing = false

    // MARK: - Public API

    func show(text: String, color: NSColor, persistent: Bool = false) {
        DispatchQueue.main.async {
            self.prepareWindow()
            self.pillView?.update(text: text, dotColor: color)
            self.animateIn()
            self.hideTimer?.invalidate()
            if !persistent {
                self.hideTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: false) { [weak self] _ in
                    self?.animateOut()
                }
            }
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.hideTimer?.invalidate()
            self.animateOut()
        }
    }

    // MARK: - Window creation

    private func prepareWindow() {
        if window != nil { return }
        guard let screen = NSScreen.main else { return }

        let pillW: CGFloat = 240
        let pillH: CGFloat = 34

        // Position just behind / below the notch center
        let sx = screen.frame.minX
        let sy = screen.frame.minY
        let sw = screen.frame.width
        let sh = screen.frame.height
        let menuH = NSStatusBar.system.thickness

        // Start position: hidden above the top of the screen (for slide-in)
        let x = sx + (sw - pillW) / 2
        let startY = sy + sh             // off-screen top
        let landY  = sy + sh - menuH - pillH - 4   // just below menu bar

        let win = NSWindow(
            contentRect: NSRect(x: x, y: startY, width: pillW, height: pillH),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 20)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.alphaValue = 0

        let pill = NotchPillView(frame: NSRect(x: 0, y: 0, width: pillW, height: pillH))
        win.contentView = pill
        pillView = pill

        // Store target Y for animation
        objc_setAssociatedObject(win, &landYKey, landY, .OBJC_ASSOCIATION_RETAIN)
        window = win
        win.orderFront(nil)
    }

    private func animateIn() {
        guard let win = window,
              let landY = objc_getAssociatedObject(win, &landYKey) as? CGFloat else { return }
        guard !isShowing else { return }
        isShowing = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            win.animator().alphaValue = 1.0
            var f = win.frame
            f.origin.y = landY
            win.animator().setFrame(f, display: true)
        }
    }

    private func animateOut() {
        guard let win = window, isShowing else { return }
        isShowing = false

        // Slide back up and fade
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            win.animator().alphaValue = 0.0
            var f = win.frame
            f.origin.y += 20
            win.animator().setFrame(f, display: true)
        }, completionHandler: {
            // Reset position for next show
            if let win = self.window, let landY = objc_getAssociatedObject(win, &landYKey) as? CGFloat {
                var f = win.frame
                f.origin.y = landY + f.height + 10   // park above landing zone
                win.setFrame(f, display: false)
            }
        })
    }
}

private var landYKey: UInt8 = 0

// MARK: - Pill view

final class NotchPillView: NSView {

    private let dotLayer = CALayer()
    private let textField = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        // Pill background
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.96).cgColor
        layer?.cornerRadius    = frame.height / 2
        layer?.shadowColor     = NSColor.black.cgColor
        layer?.shadowOpacity   = 0.4
        layer?.shadowRadius    = 8
        layer?.shadowOffset    = CGSize(width: 0, height: -2)

        // Status dot
        dotLayer.cornerRadius  = 5
        dotLayer.frame = CGRect(x: 14, y: (frame.height - 10) / 2, width: 10, height: 10)
        layer?.addSublayer(dotLayer)

        // Label
        textField.frame = NSRect(x: 32, y: (frame.height - 17) / 2, width: frame.width - 44, height: 17)
        textField.font = .systemFont(ofSize: 12.5, weight: .semibold)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBezeled = false
        addSubview(textField)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(text: String, dotColor: NSColor) {
        dotLayer.backgroundColor = dotColor.cgColor
        textField.stringValue = text
    }
}
