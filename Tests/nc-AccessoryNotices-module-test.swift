// notchcast-sources: Tinycast/Features/AccessoryNotices/AccessoryNoticesModule.swift
// notchcast-sources: Tinycast/Features/AccessoryNotices/Model/*.swift Tinycast/Features/AccessoryNotices/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/BatteryPeripheralReading.swift Tinycast/Features/SystemMonitor/Model/AccessoryBatteryRows.swift
import CoreBluetooth
import Foundation
import ObjectiveC

@MainActor protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}
enum DialogTone { case danger }
@MainActor enum IslandHUDRouter {
    static func post(_ message: String, tone: DialogTone? = nil, id: String, symbol: String, dwell: Double) {}
}
struct BatteryPeripheralService {
    func read() -> [BatteryPeripheralReading] { [] }
}
@MainActor final class Source: AccessoryBluetoothSource {
    var starts = 0
    var stops = 0
    func start(_ receive: @escaping (String, String, Bool) -> Void) -> [String] {
        starts += 1
        return []
    }
    func stop() { stops += 1 }
}
@main struct ModuleTests {
    @MainActor static func main() {
        let method = class_getClassMethod(CBManager.self, NSSelectorFromString("authorization"))!
        let original = method_getImplementation(method)
        defer { method_setImplementation(method, original) }
        let denied: @convention(block) (AnyObject) -> Int = { _ in CBManagerAuthorization.denied.rawValue }
        method_setImplementation(method, imp_implementationWithBlock(denied))
        let source = Source()
        let module = AccessoryNoticesModule(source: source)
        module.start()
        module.start()
        precondition(source.starts == 0)
        let allowed: @convention(block) (AnyObject) -> Int = { _ in CBManagerAuthorization.allowedAlways.rawValue }
        method_setImplementation(method, imp_implementationWithBlock(allowed))
        module.start()
        precondition(source.starts == 1, "Denied start must permit retry after authorization")
        module.start()
        precondition(source.starts == 1)
        module.stop()
        module.start()
        precondition(source.starts == 2 && source.stops == 1)
        module.stop()
        print("PASS: module hook start; denied auth, authorized retry, duplicate start, stop/restart")
    }
}
