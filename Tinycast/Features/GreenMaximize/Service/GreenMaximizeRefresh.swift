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

    static func read(pid: pid_t, observed: AXUIElement?, callback: AXObserverCallback, context: UInt,
                     target: AXUIElement? = nil) -> Result? {
        let date = ProcessInfo.processInfo.systemUptime
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        guard let window = target ?? element(application, kAXFocusedWindowAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.1)
        guard value(window, kAXRoleAttribute) as? String == kAXWindowRole,
            value(window, kAXMinimizedAttribute) as? Bool != true,
            frame(window) != nil,
            value(window, "AXFullScreen") as? Bool != true
        else { return nil }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable) == .success,
            settable.boolValue
        else { return nil }
        let rect = buttonRect { attribute in
            guard let button = element(window, attribute) else { return nil }
            AXUIElementSetMessagingTimeout(button, 0.1)
            guard value(button, kAXEnabledAttribute) as? Bool != false else { return nil }
            return frame(button)
        }
        guard let rect else { return nil }
        let observer = newObserver(for: window, observed: target ?? observed) { () -> AXObserver? in
            var observer: AXObserver?
            guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return nil }
            let pointer = UnsafeMutableRawPointer(bitPattern: context)
            AXObserverAddNotification(observer, application,
                kAXFocusedWindowChangedNotification as CFString, pointer)
            for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(observer, window, name as CFString, pointer)
            }
            return observer
        }
        return Result(window: window, observer: observer, rect: rect, date: date)
    }

    static func underPointer(_ point: CGPoint) -> (pid_t, Result)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success
        else { return nil }
        for _ in 0..<32 {
            guard let current = hit else { return nil }
            AXUIElementSetMessagingTimeout(current, 0.1)
            if value(current, kAXRoleAttribute) as? String == kAXWindowRole {
                var pid: pid_t = 0
                guard AXUIElementGetPid(current, &pid) == .success,
                    let result = read(pid: pid, observed: nil, callback: { _, _, _, _ in },
                        context: 0, target: current) else { return nil }
                return (pid, result)
            }
            hit = element(current, kAXWindowAttribute) ?? element(current, kAXParentAttribute)
        }
        return nil
    }

    // The periodic read keeps the snapshot fresh; only a newly focused window needs AX registrations.
    static func newObserver(
        for window: AXUIElement, observed: AXUIElement?, make: () -> AXObserver?
    ) -> AXObserver? {
        if let observed, CFEqual(observed, window) { return nil }
        return make()
    }

    static func buttonRect(read: (String) -> CGRect?) -> CGRect? {
        for attribute in [kAXZoomButtonAttribute, "AXFullScreenButton"] {
            if let rect = read(attribute), !rect.isEmpty, !rect.isInfinite,
                rect.origin.x.isFinite, rect.origin.y.isFinite {
                return rect
            }
        }
        return nil
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
