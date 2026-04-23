import Foundation

// Standard USB HID keyboard report descriptor
// Reports: modifier byte, reserved byte, 6 keycodes (boot protocol compatible)
enum HIDDescriptors {

    static let keyboard: [UInt8] = [
        0x05, 0x01,  // Usage Page (Generic Desktop)
        0x09, 0x06,  // Usage (Keyboard)
        0xA1, 0x01,  // Collection (Application)

        // Modifier keys (byte 0)
        0x05, 0x07,  // Usage Page (Key Codes)
        0x19, 0xE0,  // Usage Minimum (224) - Left Control
        0x29, 0xE7,  // Usage Maximum (231) - Right GUI
        0x15, 0x00,  // Logical Minimum (0)
        0x25, 0x01,  // Logical Maximum (1)
        0x75, 0x01,  // Report Size (1)
        0x95, 0x08,  // Report Count (8)
        0x81, 0x02,  // Input (Data, Variable, Absolute)

        // Reserved byte (byte 1)
        0x95, 0x01,  // Report Count (1)
        0x75, 0x08,  // Report Size (8)
        0x81, 0x03,  // Input (Constant)

        // LED output report (byte 0 of output)
        0x95, 0x05,  // Report Count (5)
        0x75, 0x01,  // Report Size (1)
        0x05, 0x08,  // Usage Page (LEDs)
        0x19, 0x01,  // Usage Minimum (1) - Num Lock
        0x29, 0x05,  // Usage Maximum (5) - Kana
        0x91, 0x02,  // Output (Data, Variable, Absolute)
        0x95, 0x01,  // Report Count (1)
        0x75, 0x03,  // Report Size (3)
        0x91, 0x03,  // Output (Constant)

        // Keycodes (bytes 2-7): 6-key rollover
        0x95, 0x06,  // Report Count (6)
        0x75, 0x08,  // Report Size (8)
        0x15, 0x00,  // Logical Minimum (0)
        0x25, 0xFF,  // Logical Maximum (255)
        0x05, 0x07,  // Usage Page (Key Codes)
        0x19, 0x00,  // Usage Minimum (0)
        0x29, 0xFF,  // Usage Maximum (255)
        0x81, 0x00,  // Input (Data, Array)

        0xC0         // End Collection
    ]

    // macOS virtual key code -> USB HID keycode mapping
    static func hidKeycode(forMacKeycode mac: UInt16) -> UInt8 {
        return macToHID[mac] ?? 0x00
    }

    // Comprehensive macOS keycode to USB HID keycode table
    private static let macToHID: [UInt16: UInt8] = [
        // Letters
        0x00: 0x04, // A
        0x0B: 0x05, // B
        0x08: 0x06, // C
        0x02: 0x07, // D
        0x0E: 0x08, // E
        0x03: 0x09, // F
        0x05: 0x0A, // G
        0x04: 0x0B, // H
        0x22: 0x0C, // I
        0x26: 0x0D, // J
        0x28: 0x0E, // K
        0x25: 0x0F, // L
        0x2E: 0x10, // M
        0x2D: 0x11, // N
        0x1F: 0x12, // O
        0x23: 0x13, // P
        0x0C: 0x14, // Q
        0x0F: 0x15, // R
        0x01: 0x16, // S
        0x11: 0x17, // T
        0x20: 0x18, // U
        0x09: 0x19, // V
        0x0D: 0x1A, // W
        0x07: 0x1B, // X
        0x10: 0x1C, // Y
        0x06: 0x1D, // Z

        // Numbers
        0x1D: 0x27, // 0
        0x12: 0x1E, // 1
        0x13: 0x1F, // 2
        0x14: 0x20, // 3
        0x15: 0x21, // 4
        0x17: 0x22, // 5
        0x16: 0x23, // 6
        0x1A: 0x24, // 7
        0x1C: 0x25, // 8
        0x19: 0x26, // 9

        // Function keys
        0x7A: 0x3A, // F1
        0x78: 0x3B, // F2
        0x63: 0x3C, // F3
        0x76: 0x3D, // F4
        0x60: 0x3E, // F5
        0x61: 0x3F, // F6
        0x62: 0x40, // F7
        0x64: 0x41, // F8
        0x65: 0x42, // F9
        0x6D: 0x43, // F10
        0x67: 0x44, // F11
        0x6F: 0x45, // F12

        // Special keys
        0x24: 0x28, // Return/Enter
        0x30: 0x2B, // Tab
        0x31: 0x2C, // Space
        0x33: 0x2A, // Backspace/Delete
        0x35: 0x29, // Escape
        0x39: 0x39, // Caps Lock

        // Punctuation
        0x1B: 0x2D, // Minus (-)
        0x18: 0x2E, // Equal (=)
        0x21: 0x2F, // Left Bracket ([)
        0x1E: 0x30, // Right Bracket (])
        0x2A: 0x31, // Backslash (\)
        0x29: 0x33, // Semicolon (;)
        0x27: 0x34, // Quote (')
        0x32: 0x35, // Grave (`)
        0x2B: 0x36, // Comma (,)
        0x2F: 0x37, // Period (.)
        0x2C: 0x38, // Slash (/)

        // Arrow keys
        0x7B: 0x50, // Left
        0x7C: 0x4F, // Right
        0x7D: 0x51, // Down
        0x7E: 0x52, // Up

        // Navigation
        0x73: 0x4A, // Home
        0x77: 0x4D, // End
        0x74: 0x4B, // Page Up
        0x79: 0x4E, // Page Down
        0x75: 0x4C, // Forward Delete

        // Numpad
        0x52: 0x62, // Numpad 0
        0x53: 0x59, // Numpad 1
        0x54: 0x5A, // Numpad 2
        0x55: 0x5B, // Numpad 3
        0x56: 0x5C, // Numpad 4
        0x57: 0x5D, // Numpad 5
        0x58: 0x5E, // Numpad 6
        0x59: 0x5F, // Numpad 7
        0x5B: 0x60, // Numpad 8
        0x5C: 0x61, // Numpad 9
        0x45: 0x57, // Numpad +
        0x4E: 0x56, // Numpad -
        0x43: 0x55, // Numpad *
        0x4B: 0x54, // Numpad /
        0x41: 0x63, // Numpad .
        0x4C: 0x58, // Numpad Enter
        0x47: 0x53, // Numpad Num Lock / Clear
    ]

    // Extract modifier byte from NSEvent modifier flags
    static func modifierByte(fromFlags flags: UInt64) -> UInt8 {
        var mod: UInt8 = 0
        let f = flags
        // Using raw CGEventFlags bit positions
        if f & 0x000001 != 0 { mod |= 0x02 } // Left Shift
        if f & 0x000004 != 0 { mod |= 0x01 } // Left Control
        if f & 0x000020 != 0 { mod |= 0x04 } // Left Alt/Option
        if f & 0x000008 != 0 { mod |= 0x08 } // Left GUI/Command
        if f & 0x000002 != 0 { mod |= 0x20 } // Right Shift
        if f & 0x002000 != 0 { mod |= 0x10 } // Right Control
        if f & 0x000040 != 0 { mod |= 0x40 } // Right Alt/Option
        if f & 0x000010 != 0 { mod |= 0x80 } // Right GUI/Command
        return mod
    }
}
