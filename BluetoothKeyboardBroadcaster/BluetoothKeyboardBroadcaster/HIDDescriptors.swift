import Foundation

enum HIDDescriptors {

    // MARK: - Composite descriptor: Report ID 1 = keyboard, Report ID 2 = mouse
    //
    // Per HOGP spec, when a device uses Report IDs the Report characteristic
    // value does NOT include the ID byte – that is carried by the Report
    // Reference descriptor (0x2908) on each characteristic.
    static let composite: [UInt8] = [

        // ── Keyboard (Report ID 1) ──────────────────────────────────────────
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x06,        // Usage (Keyboard)
        0xA1, 0x01,        // Collection (Application)
        0x85, 0x01,        //   Report ID 1

        // Modifier keys – 8 × 1-bit flags
        0x05, 0x07,        //   Usage Page (Key Codes)
        0x19, 0xE0,        //   Usage Minimum (Left Control)
        0x29, 0xE7,        //   Usage Maximum (Right GUI)
        0x15, 0x00,        //   Logical Minimum (0)
        0x25, 0x01,        //   Logical Maximum (1)
        0x75, 0x01,        //   Report Size (1 bit)
        0x95, 0x08,        //   Report Count (8)
        0x81, 0x02,        //   Input (Data, Variable, Absolute)

        // Reserved byte
        0x95, 0x01,        //   Report Count (1)
        0x75, 0x08,        //   Report Size (8 bits)
        0x81, 0x03,        //   Input (Constant)

        // LED output (5 indicators + 3-bit padding)
        0x95, 0x05,        //   Report Count (5)
        0x75, 0x01,        //   Report Size (1 bit)
        0x05, 0x08,        //   Usage Page (LEDs)
        0x19, 0x01,        //   Usage Minimum (Num Lock)
        0x29, 0x05,        //   Usage Maximum (Kana)
        0x91, 0x02,        //   Output (Data, Variable, Absolute)
        0x95, 0x01,        //   Report Count (1)
        0x75, 0x03,        //   Report Size (3 bits)
        0x91, 0x03,        //   Output (Constant – padding)

        // Keycodes – 6-key rollover
        0x95, 0x06,        //   Report Count (6)
        0x75, 0x08,        //   Report Size (8 bits)
        0x15, 0x00,        //   Logical Minimum (0)
        0x26, 0xFF, 0x00,  //   Logical Maximum (255) – 2-byte to keep unsigned
        0x05, 0x07,        //   Usage Page (Key Codes)
        0x19, 0x00,        //   Usage Minimum (0)
        0x2A, 0xFF, 0x00,  //   Usage Maximum (255) – 2-byte
        0x81, 0x00,        //   Input (Data, Array, Absolute)
        0xC0,              // End Collection (Keyboard)

        // ── Mouse (Report ID 2) ─────────────────────────────────────────────
        0x05, 0x01,        // Usage Page (Generic Desktop)
        0x09, 0x02,        // Usage (Mouse)
        0xA1, 0x01,        // Collection (Application)
        0x85, 0x02,        //   Report ID 2
        0x09, 0x01,        //   Usage (Pointer)
        0xA1, 0x00,        //   Collection (Physical)

        // Buttons – left (bit0), right (bit1), middle (bit2) + 5-bit padding
        0x05, 0x09,        //   Usage Page (Button)
        0x19, 0x01,        //   Usage Minimum (Button 1 – left)
        0x29, 0x03,        //   Usage Maximum (Button 3 – middle)
        0x15, 0x00,        //   Logical Minimum (0)
        0x25, 0x01,        //   Logical Maximum (1)
        0x75, 0x01,        //   Report Size (1 bit)
        0x95, 0x03,        //   Report Count (3)
        0x81, 0x02,        //   Input (Data, Variable, Absolute)
        0x75, 0x05,        //   Report Size (5 bits – padding)
        0x95, 0x01,        //   Report Count (1)
        0x81, 0x03,        //   Input (Constant)

        // X, Y relative movement  –127…127
        0x05, 0x01,        //   Usage Page (Generic Desktop)
        0x09, 0x30,        //   Usage (X)
        0x09, 0x31,        //   Usage (Y)
        0x15, 0x81,        //   Logical Minimum (-127)
        0x25, 0x7F,        //   Logical Maximum (127)
        0x75, 0x08,        //   Report Size (8 bits)
        0x95, 0x02,        //   Report Count (2)
        0x81, 0x06,        //   Input (Data, Variable, Relative)

        // Scroll wheel  –127…127
        0x09, 0x38,        //   Usage (Wheel)
        0x15, 0x81,        //   Logical Minimum (-127)
        0x25, 0x7F,        //   Logical Maximum (127)
        0x75, 0x08,        //   Report Size (8 bits)
        0x95, 0x01,        //   Report Count (1)
        0x81, 0x06,        //   Input (Data, Variable, Relative)

        0xC0,              //   End Collection (Physical)
        0xC0,              // End Collection (Mouse Application)
    ]

    // Keyboard-only descriptor (no report IDs) for maximum host compatibility
    static let keyboardOnly: [UInt8] = [
        0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
        0x05, 0x07,
        0x19, 0xE0, 0x29, 0xE7,
        0x15, 0x00, 0x25, 0x01,
        0x75, 0x01, 0x95, 0x08, 0x81, 0x02,
        0x95, 0x01, 0x75, 0x08, 0x81, 0x03,
        0x95, 0x05, 0x75, 0x01,
        0x05, 0x08, 0x19, 0x01, 0x29, 0x05,
        0x91, 0x02, 0x95, 0x01, 0x75, 0x03, 0x91, 0x03,
        0x95, 0x06, 0x75, 0x08,
        0x15, 0x00, 0x26, 0xFF, 0x00,
        0x05, 0x07, 0x19, 0x00, 0x2A, 0xFF, 0x00,
        0x81, 0x00,
        0xC0,
    ]

    // MARK: - Keycode translation

    static func hidKeycode(forMacKeycode mac: UInt16) -> UInt8 {
        return macToHID[mac] ?? 0x00
    }

    // macOS virtual keycode → USB HID Page 0x07 keycode
    static let macToHID: [UInt16: UInt8] = [
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

        // Number row
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
        0x69: 0x68, // F13
        0x6B: 0x69, // F14
        0x71: 0x6A, // F15
        0x6A: 0x6B, // F16
        0x40: 0x6C, // F17
        0x4F: 0x6D, // F18
        0x50: 0x6E, // F19

        // Control keys
        0x24: 0x28, // Return / Enter
        0x30: 0x2B, // Tab
        0x31: 0x2C, // Space
        0x33: 0x2A, // Backspace / Delete
        0x35: 0x29, // Escape
        0x39: 0x39, // Caps Lock
        0x72: 0x49, // Insert (Help on Mac)
        0x75: 0x4C, // Forward Delete

        // Punctuation & symbols
        0x1B: 0x2D, // - (minus)
        0x18: 0x2E, // = (equal)
        0x21: 0x2F, // [ (left bracket)
        0x1E: 0x30, // ] (right bracket)
        0x2A: 0x31, // \ (backslash)
        0x29: 0x33, // ; (semicolon)
        0x27: 0x34, // ' (quote)
        0x32: 0x35, // ` (grave)
        0x2B: 0x36, // , (comma)
        0x2F: 0x37, // . (period)
        0x2C: 0x38, // / (slash)

        // Arrow keys
        0x7B: 0x50, // Left
        0x7C: 0x4F, // Right
        0x7D: 0x51, // Down
        0x7E: 0x52, // Up

        // Navigation cluster
        0x73: 0x4A, // Home
        0x77: 0x4D, // End
        0x74: 0x4B, // Page Up
        0x79: 0x4E, // Page Down

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
        0x51: 0x67, // Numpad =
    ]

    // MARK: - Modifier extraction

    /// Translate CGEvent modifier flags raw value into USB HID modifier byte.
    static func modifierByte(fromFlags flags: UInt64) -> UInt8 {
        var mod: UInt8 = 0
        if flags & (1 << 0) != 0 { mod |= 0x01 } // Left Control
        if flags & (1 << 1) != 0 { mod |= 0x20 } // Right Shift (CGEvent flag)
        if flags & (1 << 2) != 0 { mod |= 0x02 } // Left Shift
        if flags & (1 << 3) != 0 { mod |= 0x08 } // Left Command
        if flags & (1 << 5) != 0 { mod |= 0x04 } // Left Option/Alt
        if flags & (1 << 6) != 0 { mod |= 0x40 } // Right Option/Alt
        if flags & (1 << 13) != 0 { mod |= 0x10 } // Right Control
        if flags & (1 << 4) != 0 { mod |= 0x80 } // Right Command
        return mod
    }
}
