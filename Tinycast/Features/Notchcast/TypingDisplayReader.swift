import AppKit
import CoreGraphics

@MainActor
final class TypingDisplayReader {
    private weak var editorWindow: NSWindow?
    private var pid: pid_t?

    func capture(_ target: InjectionTarget?) {
        editorWindow = target?.ownEditor?.window
        pid = target?.externalApp?.processIdentifier
    }

    func display() -> UInt32? {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return nil }
        if let screen = editorWindow?.screen { return screen.islandDisplayID }
        let displays = screens.map {
            TypingDisplay.Display(id: $0.islandDisplayID, bounds: CGDisplayBounds($0.islandDisplayID))
        }
        let pointer = NSEvent.mouseLocation
        let underPointer = screens.first { NSMouseInRect(pointer, $0.frame, false) }
        return TypingDisplay.choose(displays: displays, windows: pid.map(Self.windows) ?? [],
                                    pointer: underPointer?.islandDisplayID)
    }

    private static func windows(for pid: pid_t) -> [CGRect] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let rect = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rect),
                  bounds.width >= 80, bounds.height >= 60 else { return nil }
            return bounds
        }
    }
}
