import CoreBluetooth
import Foundation

@MainActor
final class CoreBluetoothTreadmillCentral: NSObject, TreadmillBluetoothCentral,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    static let service = CBUUID(string: "FFF0")
    static let notify = CBUUID(string: "FFF1")
    static let write = CBUUID(string: "FFF2")
    var onEvent: ((TreadmillBluetoothEvent) -> Void)?
    private var manager: CBCentralManager?
    private var pad: CBPeripheral?
    private var writer: CBCharacteristic?
    private var active = false

    func start() {
        active = true
        if let manager { centralManagerDidUpdateState(manager) } else {
            manager = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
    }

    func scan() {
        guard manager?.state == .poweredOn else { return }
        active = true
        manager?.scanForPeripherals(withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
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
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard active, pad == nil, name == "URTM050" else { return }
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
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.service })
        else { onEvent?(.failed); return }
        peripheral.discoverCharacteristics([Self.notify, Self.write], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: (any Error)?) {
        guard active, peripheral === pad, service.uuid == Self.service else { return }
        guard error == nil,
              let notify = service.characteristics?.first(where: { $0.uuid == Self.notify }),
              let write = service.characteristics?.first(where: { $0.uuid == Self.write }),
              notify.properties.contains(.notify),
              !write.properties.intersection([.write, .writeWithoutResponse]).isEmpty
        else { onEvent?(.failed); return }
        writer = write
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard active, peripheral === pad, characteristic.uuid == Self.notify else { return }
        onEvent?(error == nil && characteristic.isNotifying ? .ready : .failed)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard active, peripheral === pad, characteristic.uuid == Self.notify, error == nil,
              let data = characteristic.value else { return }
        onEvent?(.bytes(data))
    }
}
