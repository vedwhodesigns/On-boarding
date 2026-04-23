import Cocoa

// Animated status dot shown inside the popover.
// Idle = grey, Advertising = pulsing blue ring, Connected = solid green.
final class StatusIndicatorView: NSView {

    enum State { case idle, advertising, connected }

    var indicatorState: State = .idle {
        didSet { applyState() }
    }

    private var pulseTimer: Timer?
    private var pulseScale: CGFloat = 1.0
    private var pulseAlpha: CGFloat = 0.0

    override init(frame: NSRect) {
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyState() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseScale = 1.0
        pulseAlpha = 0.0

        if indicatorState == .advertising {
            pulseAlpha = 0.85
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.pulseScale += 0.055
                self.pulseAlpha = max(0, self.pulseAlpha - 0.038)
                if self.pulseAlpha <= 0 { self.pulseScale = 1.0; self.pulseAlpha = 0.85 }
                self.needsDisplay = true
            }
            RunLoop.main.add(pulseTimer!, forMode: .common)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let cx = bounds.midX
        let cy = bounds.midY
        let r: CGFloat = min(bounds.width, bounds.height) / 2 - 6

        // Pulse ring
        if indicatorState == .advertising && pulseAlpha > 0 {
            NSColor.systemBlue.withAlphaComponent(pulseAlpha).setStroke()
            let pr = r * pulseScale
            let ring = NSBezierPath(ovalIn: NSRect(x: cx - pr, y: cy - pr, width: pr * 2, height: pr * 2))
            ring.lineWidth = 2.5
            ring.stroke()
        }

        // Main dot
        let color: NSColor
        switch indicatorState {
        case .idle:        color = NSColor.tertiaryLabelColor
        case .advertising: color = NSColor.systemBlue
        case .connected:   color = NSColor.systemGreen
        }
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)).fill()

        // Small inner highlight for connected
        if indicatorState == .connected {
            NSColor.white.withAlphaComponent(0.25).setFill()
            let hr = r * 0.4
            NSBezierPath(ovalIn: NSRect(x: cx - hr, y: cy, width: hr * 2, height: hr)).fill()
        }
    }
}
