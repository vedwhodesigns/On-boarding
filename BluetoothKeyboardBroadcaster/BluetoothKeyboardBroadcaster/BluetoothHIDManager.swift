import Foundation
import CoreBluetooth

// GATT service/characteristic UUIDs for HID over GATT (HOGP)
private enum HIDUUIDs {
    static let hidService         = CBUUID(string: "1812")
    static let deviceInfo         = CBUUID(string: "180A")
    static let batteryService     = CBUUID(string: "180F")

    // HID characteristics
    static let reportMap          = CBUUID(string: "2A4B")
    static let hidInfo            = CBUUID(string: "2A4A")
    static let controlPoint       = CBUUID(string: "2A4C")
    static let report             = CBUUID(string: "2A4D")
    static let protocolMode       = CBUUID(string: "2A4E")
    static let bootKeyboardInput  = CBUUID(string: "2A22")

    // Device Information characteristics
    static let manufacturerName   = CBUUID(string: "2A29")
    static let modelNumber        = CBUUID(string: "2A24")
    static let serialNumber       = CBUUID(string: "2A25")
    static let pnpID              = CBUUID(string: "2A50")

    // Battery
    static let batteryLevel       = CBUUID(string: "2A19")

    // Descriptors
    static let reportReference    = CBUUID(string: "2908")
    static let clientCharConfig   = CBUUID(string: "2902")
    static let externalReport     = CBUUID(string: "2907")
}

enum BroadcastState {
    case idle
    case advertising
    case connected
    case error(String)
}

protocol BluetoothHIDManagerDelegate: AnyObject {
    func stateDidChange(_ state: BroadcastState)
    func deviceConnected(_ name: String)
    func deviceDisconnected(_ name: String)
    func pairedDevicesUpdated(_ devices: [PairedDevice])
}

struct PairedDevice: Identifiable {
    let id: UUID
    let name: String
    var lastSeen: Date
}

final class BluetoothHIDManager: NSObject {

    weak var delegate: BluetoothHIDManagerDelegate?

    private var peripheralManager: CBPeripheralManager!
    private var keyboardInputChar: CBMutableCharacteristic!
    private var bootInputChar: CBMutableCharacteristic!
    private var batteryChar: CBMutableCharacteristic!

    private(set) var state: BroadcastState = .idle {
        didSet { delegate?.stateDidChange(state) }
    }

    private(set) var pairedDevices: [PairedDevice] = []
    private var connectedCentrals: [CBCentral] = []

    // 8-byte HID keyboard report buffer
    private var currentReport = Data(repeating: 0, count: 8)
    // Track pressed keys for rollover (up to 6)
    private var pressedKeys: [UInt8] = []

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: DispatchQueue(label: "com.bkb.peripheral"),
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
        )
    }

    func startBroadcasting() {
        guard peripheralManager.state == .poweredOn else {
            state = .error("Bluetooth is not powered on")
            return
        }
        if peripheralManager.isAdvertising {
            return
        }
        setupServices()
    }

    func stopBroadcasting() {
        if peripheralManager.isAdvertising {
            peripheralManager.stopAdvertising()
        }
        state = .idle
    }

    func removePairedDevice(_ device: PairedDevice) {
        pairedDevices.removeAll { $0.id == device.id }
        delegate?.pairedDevicesUpdated(pairedDevices)
    }

    // Called by keyboard interceptor with each key event
    func sendKeyEvent(hidKeycode: UInt8, modifiers: UInt8, isKeyDown: Bool) {
        if isKeyDown {
            if !pressedKeys.contains(hidKeycode) && pressedKeys.count < 6 {
                pressedKeys.append(hidKeycode)
            }
        } else {
            pressedKeys.removeAll { $0 == hidKeycode }
        }
        sendReport(modifiers: modifiers)
    }

    func sendModifierOnly(modifiers: UInt8) {
        sendReport(modifiers: modifiers)
    }

    private func sendReport(modifiers: UInt8) {
        var report = Data(repeating: 0, count: 8)
        report[0] = modifiers
        report[1] = 0x00 // reserved
        for (i, key) in pressedKeys.prefix(6).enumerated() {
            report[i + 2] = key
        }
        currentReport = report

        guard !connectedCentrals.isEmpty else { return }

        let success = peripheralManager.updateValue(
            report,
            for: keyboardInputChar,
            onSubscribedCentrals: nil
        )
        if !success {
            // Queue will be drained in peripheralManagerIsReadyToUpdateSubscribers
        }
    }

    private func setupServices() {
        peripheralManager.removeAllServices()

        // --- HID Service ---
        let hidService = CBMutableService(type: HIDUUIDs.hidService, primary: true)

        // Report Map (HID descriptor)
        let reportMapChar = CBMutableCharacteristic(
            type: HIDUUIDs.reportMap,
            properties: .read,
            value: Data(HIDDescriptors.keyboard),
            permissions: .readable
        )

        // HID Information: bcdHID=1.11, bCountryCode=0, flags=0x02 (normally connectable)
        let hidInfoChar = CBMutableCharacteristic(
            type: HIDUUIDs.hidInfo,
            properties: .read,
            value: Data([0x11, 0x01, 0x00, 0x02]),
            permissions: .readable
        )

        // Control Point (write without response)
        let controlChar = CBMutableCharacteristic(
            type: HIDUUIDs.controlPoint,
            properties: .writeWithoutResponse,
            value: nil,
            permissions: .writeable
        )

        // Protocol Mode (read/write without response): 1 = Report Protocol
        let protocolModeChar = CBMutableCharacteristic(
            type: HIDUUIDs.protocolMode,
            properties: [.read, .writeWithoutResponse],
            value: Data([0x01]),
            permissions: [.readable, .writeable]
        )

        // Input Report (keyboard) – notify + read, with Report Reference descriptor
        keyboardInputChar = CBMutableCharacteristic(
            type: HIDUUIDs.report,
            properties: [.read, .notify, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readable, .readEncryptionRequired]
        )

        // Boot Keyboard Input (fallback for boot-protocol hosts)
        bootInputChar = CBMutableCharacteristic(
            type: HIDUUIDs.bootKeyboardInput,
            properties: [.read, .notify],
            value: nil,
            permissions: .readable
        )

        hidService.characteristics = [
            reportMapChar,
            hidInfoChar,
            controlChar,
            protocolModeChar,
            keyboardInputChar,
            bootInputChar
        ]

        // --- Device Information Service ---
        let devInfoService = CBMutableService(type: HIDUUIDs.deviceInfo, primary: true)

        let mfgChar = CBMutableCharacteristic(
            type: HIDUUIDs.manufacturerName,
            properties: .read,
            value: "Apple Inc.".data(using: .utf8),
            permissions: .readable
        )
        let modelChar = CBMutableCharacteristic(
            type: HIDUUIDs.modelNumber,
            properties: .read,
            value: "MacBook Keyboard".data(using: .utf8),
            permissions: .readable
        )
        let serialChar = CBMutableCharacteristic(
            type: HIDUUIDs.serialNumber,
            properties: .read,
            value: "BKB-001".data(using: .utf8),
            permissions: .readable
        )
        // PnP ID: Bluetooth SIG (0x01), Vendor ID 0x05AC (Apple), Product 0x0267, Version 0x0001
        let pnpChar = CBMutableCharacteristic(
            type: HIDUUIDs.pnpID,
            properties: .read,
            value: Data([0x01, 0xAC, 0x05, 0x67, 0x02, 0x01, 0x00]),
            permissions: .readable
        )
        devInfoService.characteristics = [mfgChar, modelChar, serialChar, pnpChar]

        // --- Battery Service ---
        let batteryService = CBMutableService(type: HIDUUIDs.batteryService, primary: true)
        batteryChar = CBMutableCharacteristic(
            type: HIDUUIDs.batteryLevel,
            properties: [.read, .notify],
            value: Data([100]),
            permissions: .readable
        )
        batteryService.characteristics = [batteryChar]

        peripheralManager.add(hidService)
        peripheralManager.add(devInfoService)
        peripheralManager.add(batteryService)
    }

    private func startAdvertising() {
        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: "MacBook Keyboard",
            CBAdvertisementDataServiceUUIDsKey: [HIDUUIDs.hidService]
        ]
        peripheralManager.startAdvertising(advertisementData)
        state = .advertising
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BluetoothHIDManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if case .advertising = state { } else if case .connected = state { } else {
                // Ready but not yet told to start
            }
        case .poweredOff:
            state = .error("Bluetooth powered off")
        case .unauthorized:
            state = .error("Bluetooth access not authorized")
        case .unsupported:
            state = .error("Bluetooth LE not supported")
        case .resetting:
            state = .error("Bluetooth resetting")
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            state = .error("Service add failed: \(error.localizedDescription)")
            return
        }
        // Start advertising once all three services are added
        if peripheral.services?.count == 3 {
            startAdvertising()
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            state = .error("Advertising failed: \(error.localizedDescription)")
        } else {
            state = .advertising
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == HIDUUIDs.report {
            if !connectedCentrals.contains(where: { $0.identifier == central.identifier }) {
                connectedCentrals.append(central)
            }
            let name = "Device \(central.identifier.uuidString.prefix(8))"
            upsertPairedDevice(id: central.identifier, name: name)
            state = .connected
            delegate?.deviceConnected(name)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        if characteristic.uuid == HIDUUIDs.report {
            connectedCentrals.removeAll { $0.identifier == central.identifier }
            let name = "Device \(central.identifier.uuidString.prefix(8))"
            delegate?.deviceDisconnected(name)
            if connectedCentrals.isEmpty {
                state = .advertising
            }
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Resend the last report now that the transmit queue has room
        _ = peripheral.updateValue(currentReport, for: keyboardInputChar, onSubscribedCentrals: nil)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveRead request: CBATTRequest) {
        if request.characteristic.uuid == HIDUUIDs.report {
            request.value = currentReport.subdata(in: request.offset..<currentReport.count)
            peripheral.respond(to: request, withResult: .success)
        } else if request.characteristic.uuid == HIDUUIDs.batteryLevel {
            request.value = Data([100])
            peripheral.respond(to: request, withResult: .success)
        } else {
            // For static characteristics CoreBluetooth responds automatically
            peripheral.respond(to: request, withResult: .success)
        }
    }

    private func upsertPairedDevice(id: UUID, name: String) {
        if let idx = pairedDevices.firstIndex(where: { $0.id == id }) {
            pairedDevices[idx].lastSeen = Date()
        } else {
            pairedDevices.append(PairedDevice(id: id, name: name, lastSeen: Date()))
        }
        delegate?.pairedDevicesUpdated(pairedDevices)
    }
}
