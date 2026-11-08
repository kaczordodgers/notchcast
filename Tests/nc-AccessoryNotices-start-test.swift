// notchcast-sources: Tinycast/Features/AccessoryNotices/Service/AccessoryBluetoothSource.swift
import CoreBluetooth
import Foundation
import IOBluetooth
import ObjectiveC

nonisolated(unsafe) var linked: Set<String> = []
nonisolated(unsafe) var registered: Set<String> = []
nonisolated(unsafe) var flipped: Set<String> = []
nonisolated(unsafe) var deliveredUp: Set<String> = []
nonisolated(unsafe) var deliveredDown: Set<String> = []

private func replace(_ cls: AnyClass, _ name: String, _ block: Any) {
    method_setImplementation(class_getInstanceMethod(cls, NSSelectorFromString(name))!, imp_implementationWithBlock(block))
}

@main struct AccessoryStartTests {
    @MainActor static func main() {
        let up = IOBluetoothDevice(addressString: "aa-aa-aa-aa-aa-aa")!
        let down = IOBluetoothDevice(addressString: "bb-bb-bb-bb-bb-bb")!
        let a = up.addressString!, b = down.addressString!
        linked = [a]
        let authorization: @convention(block) (AnyObject) -> Int = { _ in CBManagerAuthorization.allowedAlways.rawValue }
        replace(object_getClass(CBManager.self)!, "authorization", authorization)
        let paired: @convention(block) (AnyObject) -> NSArray = { _ in [up, down] }
        replace(object_getClass(IOBluetoothDevice.self)!, "pairedDevices", paired)
        let connects: @convention(block) (AnyObject, AnyObject, Selector) -> AnyObject? = { _, _, _ in
            registered.insert("connect"); return nil
        }
        replace(object_getClass(IOBluetoothDevice.self)!, "registerForConnectNotifications:selector:", connects)
        let disconnects: @convention(block) (IOBluetoothDevice, AnyObject, Selector) -> AnyObject? = { device, _, _ in
            registered.insert(device.addressString); return nil
        }
        replace(IOBluetoothDevice.self, "registerForDisconnectNotification:selector:", disconnects)
        // Each device flips right after its first read, as if the link changed mid-start().
        let isConnected: @convention(block) (IOBluetoothDevice) -> Bool = { device in
            let address = device.addressString!
            let value = linked.contains(address)
            guard flipped.insert(address).inserted else { return value }
            if value {
                linked.remove(address)
                if registered.contains(address) { deliveredDown.insert(address) }
            } else {
                linked.insert(address)
                if registered.contains("connect") { deliveredUp.insert(address) }
            }
            return value
        }
        replace(IOBluetoothDevice.self, "isConnected", isConnected)

        let monitor = AccessoryBluetoothMonitor()
        let seed = monitor.start { _, _, _ in }
        let view = Set(seed).union(deliveredUp).subtracting(deliveredDown)
        print("seed \(seed) up \(deliveredUp) down \(deliveredDown) view \(view)")
        assert(view == [b], "start() missed a link change: view \(view), expected [\(b)]")
        monitor.stop()
        print("ok")
    }
}
