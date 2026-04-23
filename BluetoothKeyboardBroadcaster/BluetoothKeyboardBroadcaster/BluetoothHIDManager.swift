import Foundation
import CoreBluetooth
import IOKit.ps

// MARK: - GATT UUIDs

private enum BTUUID {
    // Services
    static let hid         = CBUUID(string: "1812")
    static let deviceInfo  = CBUUID(string: "180A")
    static let battery     = CBUUID(string: "180F")

    // HID characteristics
    static let reportMap       = CBUUID(string: "2A4B")
    static let hidInfo         = CBUUID(string: "2A4A")
    static let controlPoint    = CBUUID(string: "2A4C")
    static let report          = CBUUID(string: "2A4D")
    static let protocolMode    = CBUUID(string: "2A4E")
    static let bootKbdInput    = CBUUID(string: "2A22")
    static let bootMouseInput  = CBUUID(string: "2A33")

    // Device info characteristics
    static let manufacturer    = CBUUID(string: "2A29")
    static let modelNumber     = CBUUID(string: "2A24")
    static let serialNumber    = CBUUID(string: "2A25")
    static let pnpID           = CBUUID(string: "2A50")

    // Battery
    static let batteryLevel    = CBUUID(string: "2A19")

    // Descriptors
    static let reportReference = CBUUID(string: "2908")
}

// MARK: - Public types

enum BroadcastState: Equatable {
    case idle
    case advertising
    case connected
    case error(String)
}

enum BroadcastMode {
    case keyboardAndMouse   // composite descriptor, report IDs
    case keyboardOnly       // simple descriptor, no report IDs
}

struct PairedDevice: Identifiable {
    let id: UUID
    var name: String
    var lastSeen: Date
}

protocol BluetoothHIDManagerDelegate: AnyObject {
    func stateDidChange(_ state: BroadcastState)
    func deviceConnected(_ name: String)
    func deviceDisconnected(_ name: String)
    func pairedDevicesUpdated(_ devices: [PairedDevice])
}

// MARK: - BluetoothHIDManager

final class BluetoothHIDManager: NSObject {

    weak var delegate: BluetoothHIDManagerDelegate?

    // Settable before startBroadcasting
    var deviceName: String = UserDefaults.standard.string(forKey: "deviceName") ?? "MacBook Keyboard"
    var mode: BroadcastMode = UserDefaults.standard.bool(forKey: "keyboardOnly") ? .keyboardOnly : .keyboardAndMouse

    private var peripheralManager: CBPeripheralManager!

    // Characteristics (created fresh each startBroadcasting call)
    private var kbdInputChar:    CBMutableCharacteristic!
    private var mouseInputChar:  CBMutableCharacteristic!
    private var batteryChar:     CBMutableCharacteristic!

    private(set) var state: BroadcastState = .idle {
        didSet { DispatchQueue.main.async { self.delegate?.stateDidChange(self.state) } }
    }

    private(set) var pairedDevices: [PairedDevice] = []
    private var connectedCentrals: [CBCentral] = []

    // 8-byte keyboard report cache (sent value, not including report ID)
    private var kbdReport  = Data(repeating: 0, count: 8)
    // 4-byte mouse report cache (buttons, x, y, wheel)
    private var mouseReport = Data(repeating: 0, count: 4)

    private var pressedKeys: [UInt8] = []
    private var servicesAdded = 0

    private var batteryTimer: Timer?

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(
            delegate: self,
            queue: DispatchQueue(label: "com.bkb.ble", qos: .userInteractive),
            options: [CBPeripheralManagerOptionShowPowerAlertKey: true]
        )
    }

    // MARK: - Control

    func startBroadcasting() {
        guard peripheralManager.state == .poweredOn else {
            state = .error("Bluetooth is not powered on. Enable it in System Settings.")
            return
        }
        guard !peripheralManager.isAdvertising else { return }
        servicesAdded = 0
        peripheralManager.removeAllServices()
        buildAndAddServices()
    }

    func stopBroadcasting() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        if peripheralManager.isAdvertising { peripheralManager.stopAdvertising() }
        connectedCentrals.removeAll()
        pressedKeys.removeAll()
        state = .idle
    }

    func removePairedDevice(_ device: PairedDevice) {
        pairedDevices.removeAll { $0.id == device.id }
        DispatchQueue.main.async { self.delegate?.pairedDevicesUpdated(self.pairedDevices) }
    }

    // MARK: - Keyboard report sending

    func sendKeyEvent(hidKeycode: UInt8, modifiers: UInt8, isKeyDown: Bool) {
        if isKeyDown {
            if hidKeycode != 0x00, !pressedKeys.contains(hidKeycode), pressedKeys.count < 6 {
                pressedKeys.append(hidKeycode)
            }
        } else {
            pressedKeys.removeAll { $0 == hidKeycode }
        }
        flushKeyboardReport(modifiers: modifiers)
    }

    func sendModifierOnly(modifiers: UInt8) {
        flushKeyboardReport(modifiers: modifiers)
    }

    private func flushKeyboardReport(modifiers: UInt8) {
        var report = Data(repeating: 0, count: 8)
        report[0] = modifiers
        for (i, key) in pressedKeys.prefix(6).enumerated() { report[i + 2] = key }
        kbdReport = report
        pushCharacteristic(kbdInputChar, value: report)
    }

    // MARK: - Mouse report sending

    func sendMouseReport(buttons: UInt8, deltaX: Int8, deltaY: Int8, wheel: Int8) {
        var report = Data(count: 4)
        report[0] = buttons
        report[1] = UInt8(bitPattern: deltaX)
        report[2] = UInt8(bitPattern: deltaY)
        report[3] = UInt8(bitPattern: wheel)
        mouseReport = report
        if let char = mouseInputChar {
            pushCharacteristic(char, value: report)
        }
    }

    // MARK: - GATT service construction

    private func buildAndAddServices() {
        let descriptor = mode == .keyboardAndMouse ? HIDDescriptors.composite : HIDDescriptors.keyboardOnly
        addHIDService(reportDescriptor: descriptor)
        addDeviceInfoService()
        addBatteryService()
    }

    private func addHIDService(reportDescriptor: [UInt8]) {
        let service = CBMutableService(type: BTUUID.hid, primary: true)

        let reportMapChar = CBMutableCharacteristic(
            type: BTUUID.reportMap,
            properties: .read,
            value: Data(reportDescriptor),
            permissions: .readable
        )

        // HID Info: bcdHID = 0x0111 (1.11), country = 0x21 (US), flags = 0x02
        let hidInfoChar = CBMutableCharacteristic(
            type: BTUUID.hidInfo,
            properties: .read,
            value: Data([0x11, 0x01, 0x21, 0x02]),
            permissions: .readable
        )

        let controlChar = CBMutableCharacteristic(
            type: BTUUID.controlPoint,
            properties: .writeWithoutResponse,
            value: nil,
            permissions: .writeable
        )

        // Protocol Mode: 1 = Report Protocol
        let protocolChar = CBMutableCharacteristic(
            type: BTUUID.protocolMode,
            properties: [.read, .writeWithoutResponse],
            value: Data([0x01]),
            permissions: [.readable, .writeable]
        )

        // Keyboard Input Report characteristic
        kbdInputChar = CBMutableCharacteristic(
            type: BTUUID.report,
            properties: [.read, .notify],
            value: nil,
            permissions: .readable
        )

        if mode == .keyboardAndMouse {
            // Attach Report Reference descriptor: Report ID=1, Input
            kbdInputChar.descriptors = [
                CBMutableDescriptor(type: BTUUID.reportReference, value: Data([0x01, 0x01]))
            ]
        }

        // Boot Keyboard Input (fallback for boot-protocol hosts)
        let bootKbdChar = CBMutableCharacteristic(
            type: BTUUID.bootKbdInput,
            properties: [.read, .notify],
            value: nil,
            permissions: .readable
        )

        var chars: [CBMutableCharacteristic] = [
            reportMapChar, hidInfoChar, controlChar, protocolChar,
            kbdInputChar, bootKbdChar
        ]

        if mode == .keyboardAndMouse {
            // Mouse Input Report characteristic
            mouseInputChar = CBMutableCharacteristic(
                type: BTUUID.report,
                properties: [.read, .notify],
                value: nil,
                permissions: .readable
            )
            // Report Reference: Report ID=2, Input
            mouseInputChar.descriptors = [
                CBMutableDescriptor(type: BTUUID.reportReference, value: Data([0x02, 0x01]))
            ]
            // Boot Mouse Input (fallback)
            let bootMouseChar = CBMutableCharacteristic(
                type: BTUUID.bootMouseInput,
                properties: [.read, .notify],
                value: nil,
                permissions: .readable
            )
            chars += [mouseInputChar, bootMouseChar]
        }

        service.characteristics = chars
        peripheralManager.add(service)
    }

    private func addDeviceInfoService() {
        let service = CBMutableService(type: BTUUID.deviceInfo, primary: true)
        // PnP ID: Bluetooth SIG source (0x01), Apple Vendor ID (0x05AC),
        // product 0x0267 (Magic Keyboard), version 0x0001
        service.characteristics = [
            makeStaticChar(BTUUID.manufacturer, "Apple Inc."),
            makeStaticChar(BTUUID.modelNumber,  "MacBook Keyboard Broadcaster"),
            makeStaticChar(BTUUID.serialNumber, "BKB-1-0"),
            CBMutableCharacteristic(
                type: BTUUID.pnpID,
                properties: .read,
                value: Data([0x01, 0xAC, 0x05, 0x67, 0x02, 0x01, 0x00]),
                permissions: .readable
            ),
        ]
        peripheralManager.add(service)
    }

    private func addBatteryService() {
        let service = CBMutableService(type: BTUUID.battery, primary: true)
        batteryChar = CBMutableCharacteristic(
            type: BTUUID.batteryLevel,
            properties: [.read, .notify],
            value: nil,
            permissions: .readable
        )
        service.characteristics = [batteryChar]
        peripheralManager.add(service)
    }

    private func makeStaticChar(_ uuid: CBUUID, _ string: String) -> CBMutableCharacteristic {
        CBMutableCharacteristic(
            type: uuid,
            properties: .read,
            value: string.data(using: .utf8),
            permissions: .readable
        )
    }

    // MARK: - Advertising

    private func startAdvertising() {
        peripheralManager.startAdvertising([
            CBAdvertisementDataLocalNameKey: deviceName,
            CBAdvertisementDataServiceUUIDsKey: [BTUUID.hid],
        ])
    }

    // MARK: - Helpers

    private func pushCharacteristic(_ char: CBMutableCharacteristic, value: Data) {
        guard !connectedCentrals.isEmpty else { return }
        _ = peripheralManager.updateValue(value, for: char, onSubscribedCentrals: nil)
    }

    // MARK: - Battery

    private func startBatteryUpdates() {
        updateBattery()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateBattery()
        }
        RunLoop.main.add(batteryTimer!, forMode: .common)
    }

    private func updateBattery() {
        let level = readBatteryLevel()
        if let char = batteryChar {
            pushCharacteristic(char, value: Data([level]))
        }
    }

    private func readBatteryLevel() -> UInt8 {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let cfList = IOPSCopyPowerSourcesList(snapshot) else { return 100 }
        let list = cfList.takeRetainedValue() as? [[String: Any]] ?? []
        for src in list {
            if let t = src[kIOPSTypeKey] as? String, t == kIOPSInternalBatteryType,
               let cap = src[kIOPSCurrentCapacityKey] as? Int {
                return UInt8(min(100, max(0, cap)))
            }
        }
        return 100
    }

    // MARK: - Device tracking

    private func upsertCentral(_ central: CBCentral) {
        let idStr = central.identifier.uuidString
        let shortID = String(idStr.prefix(8))
        let name = "Device \(shortID)"

        if let i = pairedDevices.firstIndex(where: { $0.id == central.identifier }) {
            pairedDevices[i].lastSeen = Date()
        } else {
            pairedDevices.append(PairedDevice(id: central.identifier, name: name, lastSeen: Date()))
        }
        DispatchQueue.main.async { self.delegate?.pairedDevicesUpdated(self.pairedDevices) }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothHIDManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            break  // caller decides when to start
        case .poweredOff:
            state = .error("Bluetooth is powered off.")
        case .unauthorized:
            state = .error("Bluetooth access not authorized. Check Privacy & Security → Bluetooth.")
        case .unsupported:
            state = .error("This Mac does not support Bluetooth LE peripheral mode.")
        case .resetting:
            state = .idle
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            state = .error("Failed to add BLE service: \(error.localizedDescription)")
            return
        }
        servicesAdded += 1
        let expected = (mode == .keyboardAndMouse) ? 3 : 3 // hid + devInfo + battery
        if servicesAdded >= expected {
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
        if connectedCentrals.first(where: { $0.identifier == central.identifier }) == nil {
            connectedCentrals.append(central)
        }
        upsertCentral(central)
        let name = "Device \(String(central.identifier.uuidString.prefix(8)))"
        state = .connected
        DispatchQueue.main.async { self.delegate?.deviceConnected(name) }
        startBatteryUpdates()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentrals.removeAll { $0.identifier == central.identifier }
        let name = "Device \(String(central.identifier.uuidString.prefix(8)))"
        DispatchQueue.main.async { self.delegate?.deviceDisconnected(name) }
        if connectedCentrals.isEmpty {
            state = .advertising
            batteryTimer?.invalidate()
            batteryTimer = nil
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Flush last cached reports now the transmit queue has room
        _ = peripheral.updateValue(kbdReport, for: kbdInputChar, onSubscribedCentrals: nil)
        if let mc = mouseInputChar {
            _ = peripheral.updateValue(mouseReport, for: mc, onSubscribedCentrals: nil)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveRead request: CBATTRequest) {
        switch request.characteristic.uuid {
        case BTUUID.report where request.characteristic === kbdInputChar:
            request.value = kbdReport.subdata(in: request.offset ..< kbdReport.count)
            peripheral.respond(to: request, withResult: .success)
        case BTUUID.report where request.characteristic === mouseInputChar:
            request.value = mouseReport.subdata(in: request.offset ..< mouseReport.count)
            peripheral.respond(to: request, withResult: .success)
        case BTUUID.batteryLevel:
            let level = readBatteryLevel()
            request.value = Data([level])
            peripheral.respond(to: request, withResult: .success)
        default:
            peripheral.respond(to: request, withResult: .success)
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            // LED output report – update Num Lock / Caps Lock indicators if needed
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
