import Foundation
import IOBluetooth

@MainActor
final class AccessoryConnectionMonitor: NSObject {
    private var connectToken: IOBluetoothUserNotification?
    private var disconnectTokens: [String: IOBluetoothUserNotification] = [:]
    private var engine = AccessoryEngine()
    private var onEvent: ((AccessoryEvent) -> Void)?

    func start(_ onEvent: @escaping (AccessoryEvent) -> Void) {
        stop()
        let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
            .filter { $0.isConnected() }
        engine = AccessoryEngine(alreadyConnected: devices.map(Self.describe))
        self.onEvent = onEvent
        for device in devices { watchDisconnect(device) }
        connectToken = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(didConnect(_:device:)))
    }

    func stop() {
        onEvent = nil
        connectToken?.unregister()
        connectToken = nil
        for token in disconnectTokens.values { token.unregister() }
        disconnectTokens.removeAll()
        engine = AccessoryEngine()
    }

    isolated deinit {
        connectToken?.unregister()
        for token in disconnectTokens.values { token.unregister() }
    }

    func updateBatteries(_ readings: [BatteryPeripheralReading]) {
        guard onEvent != nil else { return }
        let events = engine.batteries(readings)
        for event in events { onEvent?(event) }
    }

    private static func describe(_ device: IOBluetoothDevice) -> AccessoryDevice {
        AccessoryDevice(address: device.addressString ?? "", name: device.name ?? "",
                        majorClass: UInt32(device.deviceClassMajor), minorClass: UInt32(device.deviceClassMinor))
    }

    private func watchDisconnect(_ device: IOBluetoothDevice) {
        let key = Self.describe(device).key
        guard disconnectTokens[key] == nil else { return }
        disconnectTokens[key] = device.register(
            forDisconnectNotification: self, selector: #selector(didDisconnect(_:device:)))
    }

    @objc private func didConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard onEvent != nil else { return }
        watchDisconnect(device)
        if let event = engine.connect(Self.describe(device), at: ProcessInfo.processInfo.systemUptime) {
            onEvent?(event)
        }
    }

    @objc private func didDisconnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard onEvent != nil else { return }
        let description = Self.describe(device)
        engine.disconnect(description)
        disconnectTokens.removeValue(forKey: description.key)?.unregister()
    }
}
