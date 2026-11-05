import Foundation
@preconcurrency import ApplicationServices

nonisolated enum GreenMaximizeRefresh {
    // Handles are created on the serial worker and used only on main after publication.
    struct Result: @unchecked Sendable {
        let window: AXUIElement
        let button: AXUIElement
        let rect: CGRect
        let date: TimeInterval
    }

    static func readAll(pid: pid_t) -> [Result] {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let windows = value(application, kAXWindowsAttribute) as? [AXUIElement]
        else { return [] }
        return windows.compactMap { read(window: $0) }
    }

    private static func read(window: AXUIElement) -> Result? {
        let date = ProcessInfo.processInfo.systemUptime
        AXUIElementSetMessagingTimeout(window, 0.1)
        var settable = DarwinBoolean(false)
        guard value(window, kAXRoleAttribute) as? String == kAXWindowRole,
            value(window, kAXMinimizedAttribute) as? Bool != true,
            value(window, "AXFullScreen") as? Bool != true,
            AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success,
            settable.boolValue,
            let button = element(window, kAXZoomButtonAttribute) ?? element(window, "AXFullScreenButton")
        else { return nil }
        AXUIElementSetMessagingTimeout(button, 0.1)
        guard value(button, kAXEnabledAttribute) as? Bool != false,
            let rect = frame(button) else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(rect.midX), Float(rect.midY), &hit) == .success,
            let hit, let hitWindow = element(hit, kAXWindowAttribute), CFEqual(window, hitWindow)
        else { return nil }
        return Result(window: window, button: button, rect: rect, date: date)
    }

    static func verifies(_ result: Result, point: CGPoint) -> Bool {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.01)
        var hit: AXUIElement?
        return AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success
            && hit.map { CFEqual($0, result.button) } == true
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
        else { return nil }
        return result
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let result = value(parent, attribute), CFGetTypeID(result) == AXUIElementGetTypeID()
        else { return nil }
        return (result as! AXUIElement)
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = value(element, kAXPositionAttribute),
            CFGetTypeID(position) == AXValueGetTypeID(),
            let size = value(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
            AXValueGetValue(size as! AXValue, .cgSize, &extent) else { return nil }
        return CGRect(origin: point, size: extent)
    }
}
