import CoreBluetooth
import Foundation
import IOBluetooth

@MainActor
protocol AccessoryBluetoothSource: AnyObject {
    func start(_ receive: @escaping (String, String, Bool) -> Void) -> [String]
    func stop()
}

@MainActor
final class AccessoryBluetoothMonitor: NSObject, AccessoryBluetoothSource {
    private var token: IOBluetoothUserNotification?
    private var disconnects: [String: IOBluetoothUserNotification] = [:]
    private var receive: ((String, String, Bool) -> Void)?

    func start(_ receive: @escaping (String, String, Bool) -> Void) -> [String] {
        stop()
        guard CBManager.authorization == .allowedAlways else { return [] }
        self.receive = receive
        let devices = (IOBluetoothDevice.pairedDevices() ?? []).compactMap { $0 as? IOBluetoothDevice }
            .filter { $0.isConnected() }
        for device in devices { watch(device) }
        token = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        return devices.compactMap(\.addressString)
    }

    private func watch(_ device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        disconnects.removeValue(forKey: address)?.unregister()
        disconnects[address] = device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
    }

    func stop() {
        receive = nil
        token?.unregister()
        token = nil
        for token in disconnects.values { token.unregister() }
        disconnects = [:]
    }

    @objc nonisolated private func connected(_ token: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        let name = device.name ?? address
        let identity = UInt(bitPattern: Unmanaged.passUnretained(token).toOpaque())
        Task { @MainActor [weak self] in
            guard let self, let token = self.token,
                  UInt(bitPattern: Unmanaged.passUnretained(token).toOpaque()) == identity else { return }
            guard let device = IOBluetoothDevice(addressString: address) else { return }
            self.watch(device)
            // A disconnect before the watcher existed was never delivered, so it must not announce.
            guard self.disconnects[address] != nil, device.isConnected() else {
                self.disconnects.removeValue(forKey: address)?.unregister()
                return
            }
            self.receive?(address, name, true)
        }
    }

    @objc nonisolated private func disconnected(_ token: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? ""
        let name = device.name ?? address
        let identity = UInt(bitPattern: Unmanaged.passUnretained(token).toOpaque())
        Task { @MainActor [weak self] in
            guard let self, let token = self.disconnects[address],
                  UInt(bitPattern: Unmanaged.passUnretained(token).toOpaque()) == identity else { return }
            self.disconnects.removeValue(forKey: address)?.unregister()
            self.receive?(address, name, false)
        }
    }
}
