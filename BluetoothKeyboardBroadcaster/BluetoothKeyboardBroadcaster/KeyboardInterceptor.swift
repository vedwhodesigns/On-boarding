import Cocoa
import CoreGraphics

protocol KeyboardInterceptorDelegate: AnyObject {
    func keyEvent(hidKeycode: UInt8, modifiers: UInt8, isKeyDown: Bool)
    func modifiersChanged(modifiers: UInt8)
}

final class KeyboardInterceptor {

    weak var delegate: KeyboardInterceptorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isActive = false

    // Start intercepting – requires Accessibility permission
    func start() -> Bool {
        guard !isActive else { return true }
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            return false
        }

        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,   // passthrough – Mac keyboard still works normally
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        return true
    }

    func stop() {
        guard isActive, let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
    }

    private func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    // Handles raw CGEvents from the tap callback
    fileprivate func handleEvent(type: CGEventType, event: CGEvent) {
        let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.rawValue
        let modifiers = HIDDescriptors.modifierByte(fromFlags: flags)

        switch type {
        case .keyDown:
            let hid = HIDDescriptors.hidKeycode(forMacKeycode: keycode)
            delegate?.keyEvent(hidKeycode: hid, modifiers: modifiers, isKeyDown: true)

        case .keyUp:
            let hid = HIDDescriptors.hidKeycode(forMacKeycode: keycode)
            delegate?.keyEvent(hidKeycode: hid, modifiers: modifiers, isKeyDown: false)

        case .flagsChanged:
            // Modifier-only change; send current modifier state with no keys
            delegate?.modifiersChanged(modifiers: modifiers)

        default:
            break
        }
    }
}

// C-compatible callback for CGEvent tap
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
    let interceptor = Unmanaged<KeyboardInterceptor>.fromOpaque(refcon).takeUnretainedValue()
    interceptor.handleEvent(type: type, event: event)
    return Unmanaged.passRetained(event) // always pass through so Mac still works
}
