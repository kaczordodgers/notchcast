import Foundation
@preconcurrency import ApplicationServices

nonisolated enum GreenMaximizeRefresh {
    // Handles are created on the serial worker and used only on main after publication.
    struct Result: @unchecked Sendable {
        let window: AXUIElement
        let observer: AXObserver?
        let rect: CGRect
        let date: TimeInterval
    }

    static func read(pid: pid_t, callback: AXObserverCallback, context: UInt) -> Result? {
        let date = ProcessInfo.processInfo.systemUptime
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let window = element(application, kAXFocusedWindowAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.1)
        guard value(window, kAXRoleAttribute) as? String == kAXWindowRole,
            value(window, kAXMinimizedAttribute) as? Bool != true,
            frame(window) != nil,
            value(window, "AXFullScreen") as? Bool != true
        else { return nil }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success,
            settable.boolValue,
            let button = element(window, kAXZoomButtonAttribute) ?? element(window, "AXFullScreenButton")
        else { return nil }
        AXUIElementSetMessagingTimeout(button, 0.1)
        guard value(button, kAXEnabledAttribute) as? Bool != false,
            let rect = frame(button) else { return nil }
        var observer: AXObserver?
        if AXObserverCreate(pid, callback, &observer) == .success, let observer {
            let pointer = UnsafeMutableRawPointer(bitPattern: context)
            AXObserverAddNotification(observer, application,
                kAXFocusedWindowChangedNotification as CFString, pointer)
            for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(observer, window, name as CFString, pointer)
            }
        }
        return Result(window: window, observer: observer, rect: rect, date: date)
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
