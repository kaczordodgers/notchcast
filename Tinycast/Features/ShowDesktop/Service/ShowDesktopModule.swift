import AppKit
import Foundation

@MainActor
final class ShowDesktopModule: NotchcastModule {
    private typealias DockNotification = @convention(c) (CFString, Int32) -> Int32
    private static let keyCode: Int64 = 160
    private let tap: EventTapSubscription
    private var generation = UUID()
    private var library: UnsafeMutableRawPointer?
    private var send: DockNotification?

    init(hub: EventTapHub) { tap = EventTapSubscription(hub: hub) }

    func start() {
        guard !tap.isActive,
              let handle = dlopen(
                "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        else { return }
        guard let symbol = dlsym(handle, "CoreDockSendNotification") else {
            dlclose(handle)
            return
        }
        library = handle
        send = unsafeBitCast(symbol, to: DockNotification.self)
        let generation = UUID()
        self.generation = generation
        tap.startKeyPress(Self.keyCode) { [weak self] event in
            let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
            guard event.flags.isDisjoint(with: modifiers) else { return false }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation else { return }
                _ = self.send?("com.apple.showdesktop.awake" as CFString, 0)
            }
            return true
        }
    }

    func stop() {
        generation = UUID()
        tap.stop()
        send = nil
        if let library { dlclose(library) }
        library = nil
    }
}
