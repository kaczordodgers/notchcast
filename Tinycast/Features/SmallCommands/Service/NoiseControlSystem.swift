import AppKit
import ApplicationServices

enum NoiseControlSystem {
    private struct Button {
        let element: AXUIElement
        let value: NoiseControlEngine.Button
    }

    enum Failure: Error { case unavailable }

    @concurrent
    static func perform(
        _ action: NoiseControlService.Action, processID: Int32, deadline: Duration
    ) async throws -> [NoiseControlEngine.Button] {
        guard AXIsProcessTrusted() else { throw NoiseControlService.Failure.needsAccessibility }
        guard action == .close || !Task.isCancelled else { throw CancellationError() }
        guard uptime < deadline else { throw Failure.unavailable }
        let root = AXUIElementCreateApplication(processID)
        switch action {
        case .open, .close:
            guard let barValue = attribute(root, "AXExtrasMenuBar"),
                CFGetTypeID(barValue) == AXUIElementGetTypeID() else { throw Failure.unavailable }
            let bar = unsafeDowncast(barValue, to: AXUIElement.self)
            guard let sound = children(bar).first(where: {
                attribute($0, kAXIdentifierAttribute) as? String == "com.apple.menuextra.sound"
            }) else { throw Failure.unavailable }
            guard uptime < deadline else { throw Failure.unavailable }
            if action == .open { try Task.checkCancellation() }
            guard AXUIElementPerformAction(sound, kAXPressAction as CFString) == .success else {
                throw Failure.unavailable
            }
            return []
        case .snapshot:
            return try buttons(root, deadline: deadline).map(\.value)
        case .press(let mode):
            let found = try buttons(root, deadline: deadline)
            try Task.checkCancellation()
            guard uptime < deadline, let button = found.first(where: { $0.value.mode == mode }),
                AXUIElementPerformAction(button.element, kAXPressAction as CFString) == .success else {
                throw Failure.unavailable
            }
            return []
        }
    }

    private static var uptime: Duration { .seconds(ProcessInfo.processInfo.systemUptime) }

    private static func buttons(_ root: AXUIElement, deadline: Duration) throws -> [Button] {
        var found: [Button] = []
        var remaining = children(root, attribute: kAXWindowsAttribute).map { ($0, 0) }
        var visited = 0
        while let (element, depth) = remaining.popLast(), visited < 512 {
            try Task.checkCancellation()
            guard uptime < deadline else { throw Failure.unavailable }
            visited += 1
            let names = [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute].compactMap {
                attribute(element, $0) as? String
            }
            if let mode = NoiseControlEngine.Mode.allCases.first(where: { names.contains($0.rawValue) }) {
                let value = (attribute(element, kAXValueAttribute) as? NSNumber)?.boolValue
                    ?? (attribute(element, kAXSelectedAttribute) as? NSNumber)?.boolValue
                found.append(Button(element: element, value: .init(mode: mode, selected: value)))
            }
            if depth < 8 { remaining += children(element).map { ($0, depth + 1) } }
        }
        return found
    }

    private static func children(_ element: AXUIElement, attribute name: String = kAXChildrenAttribute) -> [AXUIElement] {
        (attribute(element, name) as? [AXUIElement]) ?? []
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
