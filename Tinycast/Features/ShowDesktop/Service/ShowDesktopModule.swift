import AppKit
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
    private var send: DockNotification?
    private var activation: NotificationToken?

    init(hub: EventTapHub) { self.hub = hub }

    func start() {
        hub.refreshPermission()
        guard registration == nil,
              let handle = dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        else { return }
        guard let symbol = dlsym(handle, "CoreDockSendNotification") else {
            dlclose(handle)
            return
        }
        library = handle
        send = unsafeBitCast(symbol, to: DockNotification.self)
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
                    _ = self.send?("com.apple.showdesktop.awake" as CFString, 0)
                }
                return .swallow
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        activation = NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hub.refreshPermission() }
        }, center: center)
    }

    func stop() {
        generation = UUID()
        if let registration { hub.remove(registration) }
        registration = nil
        activation = nil
        send = nil
        if let library { dlclose(library) }
        library = nil
    }
}
