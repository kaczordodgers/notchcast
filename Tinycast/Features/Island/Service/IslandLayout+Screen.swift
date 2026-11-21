import AppKit

extension IslandLayout {
    /// The island's layout on a real screen: its notch, and its menu bar for the Island position.
    @MainActor init(_ screen: NSScreen, position: IslandPosition) {
        self.init(screen: screen.frame, notch: Self.notch(on: screen), canvas: NotchTheme.Size.islandHost,
                  position: position, menuBar: screen.frame.maxY - screen.visibleFrame.maxY,
                  pill: NotchTheme.Size.islandRest.height)
    }

    @MainActor static func notch(on screen: NSScreen) -> CGSize {
        #if DEBUG
        if let simulatedNotch = IslandController.simulatedNotch { return simulatedNotch }
        #endif
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return .zero }
        return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
    }
}

extension NSScreen {
    var islandDisplayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Stable across replugs and restarts, where the display id is not.
    var islandDisplayUUID: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(islandDisplayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
