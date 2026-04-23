import Cocoa
import CoreGraphics

protocol MouseInterceptorDelegate: AnyObject {
    func mouseReport(buttons: UInt8, deltaX: Int8, deltaY: Int8, wheel: Int8)
}

// Captures mouse / trackpad events and emits HID mouse reports at up to 100 Hz.
// Events are passthrough – the Mac pointer continues to work normally.
final class MouseInterceptor {

    weak var delegate: MouseInterceptorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive = false

    // Accumulated deltas between flush ticks
    private var pendingDX: Int = 0
    private var pendingDY: Int = 0
    private var pendingWheel: Int = 0
    private var currentButtons: UInt8 = 0

    // 100 Hz flush timer
    private var flushTimer: Timer?
    private let flushInterval: TimeInterval = 1.0 / 100.0

    // MARK: - Lifecycle

    func start() -> Bool {
        guard !isActive else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)          |
            (1 << CGEventType.leftMouseDragged.rawValue)    |
            (1 << CGEventType.rightMouseDragged.rawValue)   |
            (1 << CGEventType.otherMouseDragged.rawValue)   |
            (1 << CGEventType.leftMouseDown.rawValue)       |
            (1 << CGEventType.leftMouseUp.rawValue)         |
            (1 << CGEventType.rightMouseDown.rawValue)      |
            (1 << CGEventType.rightMouseUp.rawValue)        |
            (1 << CGEventType.otherMouseDown.rawValue)      |
            (1 << CGEventType.otherMouseUp.rawValue)        |
            (1 << CGEventType.scrollWheel.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: mouseTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        flushTimer = Timer.scheduledTimer(
            withTimeInterval: flushInterval,
            repeats: true
        ) { [weak self] _ in self?.flushIfNeeded() }
        RunLoop.main.add(flushTimer!, forMode: .common)

        isActive = true
        return true
    }

    func stop() {
        guard isActive else { return }
        flushTimer?.invalidate()
        flushTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        pendingDX = 0; pendingDY = 0; pendingWheel = 0
        currentButtons = 0
        isActive = false
    }

    // MARK: - Event handling (called from C callback on main queue)

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            pendingDX += Int(event.getIntegerValueField(.mouseEventDeltaX))
            pendingDY += Int(event.getIntegerValueField(.mouseEventDeltaY))

        case .leftMouseDown:
            currentButtons |= 0x01
            flushImmediate()
        case .leftMouseUp:
            currentButtons &= ~0x01
            flushImmediate()

        case .rightMouseDown:
            currentButtons |= 0x02
            flushImmediate()
        case .rightMouseUp:
            currentButtons &= ~0x02
            flushImmediate()

        case .otherMouseDown:
            let btn = event.getIntegerValueField(.mouseEventButtonNumber)
            if btn == 2 { currentButtons |= 0x04; flushImmediate() }
        case .otherMouseUp:
            let btn = event.getIntegerValueField(.mouseEventButtonNumber)
            if btn == 2 { currentButtons &= ~0x04; flushImmediate() }

        case .scrollWheel:
            // axis1 = vertical scroll (positive = up)
            pendingWheel += Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))

        default:
            break
        }
    }

    // MARK: - Flushing

    private func flushIfNeeded() {
        guard pendingDX != 0 || pendingDY != 0 || pendingWheel != 0 else { return }
        flushImmediate()
    }

    private func flushImmediate() {
        // BLE mouse report is signed 8-bit per axis; clamp accumulated deltas
        // and carry over the remainder so fast movements aren't silently lost.
        let (x, remX) = clamp128(pendingDX)
        let (y, remY) = clamp128(pendingDY)
        let (w, remW) = clamp128(pendingWheel)
        pendingDX = remX
        pendingDY = remY
        pendingWheel = remW

        delegate?.mouseReport(
            buttons: currentButtons,
            deltaX:  x,
            deltaY:  y,
            wheel:   w
        )
    }

    // Clamps to –127…127 and returns (clamped, remainder)
    private func clamp128(_ v: Int) -> (Int8, Int) {
        let clamped = max(-127, min(127, v))
        return (Int8(clamped), v - clamped)
    }
}

// C-compatible tap callback
private func mouseTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon = refcon {
        let interceptor = Unmanaged<MouseInterceptor>.fromOpaque(refcon).takeUnretainedValue()
        interceptor.handleEvent(type: type, event: event)
    }
    return Unmanaged.passRetained(event) // always pass through
}
