# Bluetooth Keyboard Broadcaster

A lightweight macOS menu-bar app that turns your MacBook into a Bluetooth HID keyboard. Any device with Bluetooth — Windows PC, iPad, iPhone, Android, Linux — can discover and connect to your Mac as if it were a standard wireless keyboard.

## How It Works

```
Physical keyboard → CGEvent tap (passthrough) → HID report → BLE peripheral → Connected device
```

- **CGEvent tap** captures keystrokes from your physical keyboard without blocking them (your Mac keyboard still works normally).
- **CoreBluetooth peripheral** advertises as a standard HID over GATT (HOGP) keyboard using the `0x1812` HID Service with a full USB HID report descriptor.
- **HID reports** are 8 bytes: `[modifiers, reserved, key1…key6]` — compatible with every OS.

## Features

- Menu bar icon shows idle / advertising / connected state
- Green indicator dot when a device is actively connected
- `⌘⇧B` shortcut to toggle broadcasting
- Paired devices submenu — click any device to remove it
- Auto-reconnect: if the connected device disconnects the app resumes advertising immediately
- Error alerts for Bluetooth permission issues
- Zero impact on Mac keyboard when broadcasting is off

## Requirements

- macOS 12 Ventura or later
- Mac with Bluetooth LE hardware (all Macs since ~2012)
- Xcode 15+ to build

## Building

```bash
# Open in Xcode
open BluetoothKeyboardBroadcaster.xcodeproj

# Or build from command line (requires Xcode Command Line Tools)
xcodebuild -project BluetoothKeyboardBroadcaster.xcodeproj \
           -scheme BluetoothKeyboardBroadcaster \
           -configuration Release \
           build
```

The `.app` lands in `build/Release/BluetoothKeyboardBroadcaster.app`.

## First Launch — Permissions

Two permissions are needed:

### 1. Accessibility (required for key capture)

macOS 14+:
> System Settings → Privacy & Security → Accessibility → enable **Bluetooth Keyboard Broadcaster**

The app will prompt you automatically on first "Start Broadcasting" click if not yet granted.

### 2. Bluetooth (auto-prompted by macOS)

macOS will show a Bluetooth consent dialog the first time the peripheral tries to start. Grant it.

## Connecting a Device

1. Launch the app — keyboard icon appears in the menu bar.
2. Click **Start Broadcasting** (or press ⌘⇧B).  
   The status changes to *Advertising — waiting for connection*.
3. On your other device:
   - **Windows**: Settings → Bluetooth → Add device → Bluetooth → select **MacBook Keyboard**
   - **iPad/iPhone**: Settings → Bluetooth → select **MacBook Keyboard** (may show as *Keyboard*)
   - **Android**: Settings → Connected devices → Pair new device → select **MacBook Keyboard**
   - **Linux**: `bluetoothctl` → `scan on` → `pair <MAC>` → `connect <MAC>`
4. Accept any pairing confirmation on both sides.
5. The menu bar status changes to *Connected*.

Type on your MacBook — keystrokes appear on the connected device in real time.

## Technical Details

### BLE Services

| Service | UUID | Purpose |
|---------|------|---------|
| HID | `0x1812` | Keyboard reports, HID descriptor |
| Device Information | `0x180A` | Manufacturer, model, PnP ID |
| Battery | `0x180F` | Reports 100% (static) |

### HID Report Format

```
Byte 0: Modifier keys bitmask
  bit 0 = Left Ctrl   bit 4 = Right Ctrl
  bit 1 = Left Shift  bit 5 = Right Shift
  bit 2 = Left Alt    bit 6 = Right Alt
  bit 3 = Left GUI    bit 7 = Right GUI
Byte 1: Reserved (0x00)
Bytes 2–7: USB HID keycodes (up to 6-key rollover)
```

### Key Mapping

macOS virtual key codes are translated to USB HID page 0x07 keycodes via a lookup table in `HIDDescriptors.swift`. The table covers all standard keys including letters, numbers, punctuation, function keys, arrow keys, numpad, and navigation keys.

## Architecture

```
AppDelegate
└── StatusBarController          (menu bar UI + coordination)
    ├── BluetoothHIDManager      (CoreBluetooth peripheral)
    │   └── CBPeripheralManager  (BLE stack)
    └── KeyboardInterceptor      (CGEvent tap)
```

| File | Responsibility |
|------|---------------|
| `AppDelegate.swift` | App entry point, hides from Dock |
| `StatusBarController.swift` | Menu bar icon, menu, state display, delegates |
| `BluetoothHIDManager.swift` | BLE peripheral, GATT services, HID report sending |
| `HIDDescriptors.swift` | HID report descriptor bytes, key code translation table |
| `KeyboardInterceptor.swift` | CGEvent tap, passthrough key capture |

## Limitations & Notes

- **Sandbox off**: The app cannot be sandboxed because `CGEvent.tapCreate` with `.cgSessionEventTap` requires a non-sandboxed process. This also means it cannot be distributed on the Mac App Store as-is.
- **Encryption**: BLE HID notifications use `notifyEncryptionRequired` — pairing creates an encrypted link automatically on capable hosts. Some very old hosts may need `notify` instead; change `keyboardInputChar` properties if needed.
- **6-key rollover**: Standard HID boot protocol supports 6 simultaneous keys + 8 modifiers. N-key rollover would require a custom vendor report.
- **Mouse**: This app only broadcasts keyboard. A companion `BluetoothMouseBroadcaster` could use HID report ID 2 with relative XY + button data.
