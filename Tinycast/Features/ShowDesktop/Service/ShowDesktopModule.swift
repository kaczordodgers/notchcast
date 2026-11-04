import ApplicationServices
import Foundation
import Synchronization

@MainActor
final class ShowDesktopModule: NotchcastModule {
    private typealias DockNotification = @convention(c) (CFString, Int32) -> Int32
    private let hub: EventTapHub
    private var registration: UUID?
    private var generation = UUID()
    private var library: UnsafeMutableRawPointer?

    init(hub: EventTapHub) { self.hub = hub }

    func start() {
        guard registration == nil,
              let handle = dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        else { return }
        guard let symbol = dlsym(handle, "CoreDockSendNotification") else {
            dlclose(handle)
            return
        }
        library = handle
        let send = unsafeBitCast(symbol, to: DockNotification.self)
        let engine = Mutex(ShowDesktopEngine())
        let generation = UUID()
        self.generation = generation
        let mask = EventTapPolicy.mask(for: .keyDown) | EventTapPolicy.mask(for: .keyUp)
        registration = hub.registerSynchronous(mask: mask) { [weak self] type, event in
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            let decision = engine.withLock {
                $0.decide(isKeyDown: type == .keyDown,
                          keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                          hasModifiers: !event.flags.intersection(modifiers).isEmpty,
                          isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            }
            switch decision {
            case .pass: return .pass
            case .swallow: return .swallow
            case .toggle:
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == generation else { return }
                    _ = send("com.apple.showdesktop.awake" as CFString, 0)
                }
                return .swallow
            }
        }
    }

    func stop() {
        generation = UUID()
        if let registration { hub.remove(registration) }
        registration = nil
        if let library { dlclose(library) }
        library = nil
    }
}
