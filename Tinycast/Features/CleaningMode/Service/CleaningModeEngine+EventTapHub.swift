import ApplicationServices
import Foundation

extension CleaningModeEngine {
    convenience init(hub: EventTapHub) {
        self.init(
            now: { ProcessInfo.processInfo.systemUptime },
            register: { filter in
                let types: [UInt32] = [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
                                       CGEventType.flagsChanged.rawValue, 14]
                let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1) }
                return hub.registerSynchronous(mask: mask) { type, event in
                    let input: CleaningModePolicy.Event
                    switch type {
                    case .keyDown:
                        input = .keyDown(code: event.getIntegerValueField(.keyboardEventKeycode),
                                         isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
                    case .keyUp: input = .keyUp
                    case .flagsChanged: input = .modifier
                    default: input = type.rawValue == 14 ? .systemKey : .other
                    }
                    return filter(input) ? .swallow : .pass
                }
            },
            unregister: { hub.remove($0) },
            facts: { (hub.isRunning, AXIsProcessTrusted()) },
            schedule: { interval, repeats, action in
                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
                    MainActor.assumeIsolated { action() }
                }
                RunLoop.main.add(timer, forMode: .common)
                return { timer.invalidate() }
            }
        )
    }
}
