import CoreBluetooth
import Foundation

@MainActor
final class CoreBluetoothTreadmillCentral: NSObject, TreadmillBluetoothCentral,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    static let service = CBUUID(string: "FFF0")
    static let discoveryServices = [CBUUID(string: "1826"), service]
    static let notify = CBUUID(string: "FFF1")
    static let write = CBUUID(string: "FFF2")
    var onEvent: ((TreadmillBluetoothEvent) -> Void)?
    private var manager: CBCentralManager?
    private var pad: CBPeripheral?
    private var writer: CBCharacteristic?
    private var active = false
    private var rejections = TreadmillPadRejections()
    private let defaults: UserDefaults
    private static let padIDKey = "treadmill.padID"

    init(defaults: UserDefaults = NotchcastIdentity.current.defaults) {
        self.defaults = defaults
    }

    func start() {
        active = true
        if let manager { centralManagerDidUpdateState(manager) } else {
            manager = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func scan() -> Bool {
        guard let manager, manager.state == .poweredOn else { return false }
        active = true
        if pad != nil { return false }
        if let id = defaults.string(forKey: Self.padIDKey).flatMap(UUID.init(uuidString:)),
           rejections.allows(id), let known = manager.retrievePeripherals(withIdentifiers: [id]).first {
            pad = known
            known.delegate = self
            connect()
            return false
        }
        manager.scanForPeripherals(withServices: Self.discoveryServices,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        return true
    }

    func connect() {
        guard active, let pad else { return }
        manager?.stopScan()
        manager?.connect(pad)
    }

    func stop() {
        active = false
        manager?.stopScan()
        let previous = pad
        pad = nil
        writer = nil
        rejections.stop()
        previous?.delegate = nil
        if let previous { manager?.cancelPeripheralConnection(previous) }
    }

    func write(_ data: Data) throws {
        guard active, let pad, let writer else { throw TreadmillFailure.notReady }
        let type: CBCharacteristicWriteType = writer.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        pad.writeValue(data, for: writer, type: type)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: onEvent?(.poweredOn)
        case .unauthorized: onEvent?(.unauthorized)
        case .unknown, .resetting: break
        default: onEvent?(.poweredOff)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard active, pad == nil, rejections.allows(peripheral.identifier) else { return }
        pad = peripheral
        peripheral.delegate = self
        onEvent?(.discovered)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard active, peripheral === pad else { return }
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: (any Error)?) {
        guard active, peripheral === pad else { return }
        onEvent?(.failed)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: (any Error)?) {
        guard active, peripheral === pad else { return }
        writer = nil
        onEvent?(.disconnected)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard active, peripheral === pad else { return }
        guard error == nil else { discoveryFailed(peripheral); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.service })
        else { reject(peripheral); return }
        peripheral.discoverCharacteristics([Self.notify, Self.write], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: (any Error)?) {
        guard active, peripheral === pad, service.uuid == Self.service else { return }
        guard error == nil else { discoveryFailed(peripheral); return }
        guard let notify = service.characteristics?.first(where: { $0.uuid == Self.notify }),
              let write = service.characteristics?.first(where: { $0.uuid == Self.write }),
              notify.properties.contains(.notify),
              !write.properties.intersection([.write, .writeWithoutResponse]).isEmpty
        else { reject(peripheral); return }
        writer = write
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard active, peripheral === pad, characteristic.uuid == Self.notify else { return }
        guard error == nil, characteristic.isNotifying else { reject(peripheral); return }
        rejections.ready()
        defaults.set(peripheral.identifier.uuidString, forKey: Self.padIDKey)
        onEvent?(.ready)
    }

    private func discoveryFailed(_ peripheral: CBPeripheral) {
        if rejections.discoveryFailed() { reject(peripheral) } else {
            manager?.cancelPeripheralConnection(peripheral)
        }
    }

    private func reject(_ peripheral: CBPeripheral) {
        rejections.reject(peripheral.identifier)
        pad = nil
        writer = nil
        peripheral.delegate = nil
        manager?.cancelPeripheralConnection(peripheral)
        onEvent?(.rejected)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard active, peripheral === pad, characteristic.uuid == Self.notify, error == nil,
              let data = characteristic.value else { return }
        onEvent?(.bytes(data))
    }
}
