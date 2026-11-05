import CoreBluetooth
import Foundation

@MainActor
final class AccessoryNoticesModule: NSObject, NotchcastModule, CBCentralManagerDelegate {
    private let source: any AccessoryBluetoothSource
    private var engine = AccessoryNoticeEngine()
    private var running = false
    private var timer: Task<Void, Never>?
    private var permission: CBCentralManager?

    init(source: any AccessoryBluetoothSource = AccessoryBluetoothMonitor()) {
        self.source = source
    }

    private func requestAccess() {
        guard CBManager.authorization != .allowedAlways else { return }
        permission = CBCentralManager(delegate: self, queue: .main,
                                      options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor [weak self] in
            guard let self, self.permission != nil,
                  CBManager.authorization == .allowedAlways else { return }
            self.permission = nil
            if self.running { self.stop(); self.start() }
        }
    }

    func start() {
        guard !running else { return }
        running = true
        requestAccess()
        guard CBManager.authorization == .allowedAlways else { return }
        engine.seed(source.start { [weak self] address, name, connected in
            guard let self, self.running, self.engine.connection(address, connected: connected) else { return }
            let message = String(localized: "\(name): Connected", table: "Notchcast")
            IslandActivityCenter.shared.showMessage(message, tone: .neutral, dwell: 4)
        })
        timer = Task { [weak self] in
            while !Task.isCancelled {
                let readings = await Self.readBatteries()
                guard !Task.isCancelled, let self, self.running else { return }
                for reading in self.engine.batteries(readings) {
                    let message = String(localized: "\(reading.name): Low battery: \(Int(reading.percent))%", table: "Notchcast")
                    IslandActivityCenter.shared.showMessage(message, tone: .danger, dwell: 4)
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
