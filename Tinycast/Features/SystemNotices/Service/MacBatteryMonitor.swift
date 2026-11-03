import Foundation
import IOKit.ps

@MainActor
final class MacBatteryMonitor {
    private var source: CFRunLoopSource?
    private var receive: ((SystemNoticeEngine.Battery?) -> Void)?

    func start(_ receive: @escaping (SystemNoticeEngine.Battery?) -> Void) {
        stop()
        self.receive = receive
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<MacBatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak monitor] in monitor?.sample() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        sample()
    }

    func stop() {
        if let source { CFRunLoopSourceInvalidate(source) }
        source = nil
        receive = nil
    }

    private func sample() {
        guard receive != nil else { return }
        receive?(Self.read())
    }

    static func read() -> SystemNoticeEngine.Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let item = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  item[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  item[kIOPSIsPresentKey] as? Bool != false,
                  let current = item[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = item[kIOPSMaxCapacityKey] as? Int, maximum > 0, (0...maximum).contains(current),
                  let state = item[kIOPSPowerSourceStateKey] as? String,
                  state == kIOPSACPowerValue || state == kIOPSBatteryPowerValue else { continue }
            let percent = Int((Double(current) / Double(maximum) * 100).rounded())
            guard (0...100).contains(percent) else { return nil }
            return .init(percent: percent, onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }

    isolated deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
    }
}
