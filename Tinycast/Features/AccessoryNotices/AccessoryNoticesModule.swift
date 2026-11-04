import CoreBluetooth
import Foundation

@MainActor
final class AccessoryNoticesModule: NSObject, NotchcastModule, CBCentralManagerDelegate {
    private let source: any AccessoryBluetoothSource
    private let optedIn: () -> Bool
    private var engine = AccessoryNoticeEngine()
    private var running = false
    private var timer: Task<Void, Never>?
    private var permission: CBCentralManager?

    init(source: any AccessoryBluetoothSource = AccessoryBluetoothMonitor(), optedIn: @escaping () -> Bool) {
        self.source = source
        self.optedIn = optedIn
    }

    func requestAccess() {
        guard CBManager.authorization == .notDetermined else { return }
        permission = CBCentralManager(delegate: self, queue: .main,
                                      options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self, CBManager.authorization != .notDetermined else { return }
            self.permission = nil
            if self.running { self.stop(); self.start() }
        }
    }

    func start() {
        guard !running else { return }
        running = true
        guard optedIn(), CBManager.authorization == .allowedAlways else { return }
        engine.seed(source.start { [weak self] address, name, connected in
            guard let self, self.running, self.engine.connection(address, connected: connected) else { return }
            let status = String(localized: "Connected")
            IslandActivityCenter.shared.showMessage("\(name): \(status)", tone: .neutral, dwell: 4)
        })
        timer = Task { [weak self] in
            while !Task.isCancelled {
                let readings = await Self.readBatteries()
                guard !Task.isCancelled, let self, self.running else { return }
                for reading in self.engine.batteries(readings) {
                    let status = String(localized: "Low battery: \(Int(reading.percent))%")
                    IslandActivityCenter.shared.showMessage("\(reading.name): \(status)", tone: .danger, dwell: 4)
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
    }

    @concurrent private static func readBatteries() async -> [BatteryPeripheralReading] {
        BatteryPeripheralService().read()
    }

    func stop() {
        running = false
        timer?.cancel()
        timer = nil
        permission = nil
        source.stop()
        engine = AccessoryNoticeEngine()
    }
}
