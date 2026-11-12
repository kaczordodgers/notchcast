import AppKit
import ApplicationServices

enum FinderCommandService {
    enum Focus: Sendable { case files, text, unavailable }

    static func originalKey(for action: FinderShortcutPolicy.Action) -> (CGKeyCode, CGEventFlags)? {
        switch action {
        case .cut: (7, .maskCommand)
        case .paste: (9, .maskCommand)
        case .rename: (15, [.maskCommand, .maskAlternate, .maskControl, .maskShift])
        case .forget: nil
        }
    }

    @concurrent
    static func focus(pid: Int32) async -> Focus {
        guard AXIsProcessTrusted() else { return .unavailable }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let focused = element(app, kAXFocusedUIElementAttribute),
            let role = string(focused, kAXRoleAttribute)
        else { return .unavailable }
        if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) { return .text }
        guard role != kAXMenuRole, role != kAXMenuItemRole,
            let window = element(app, kAXFocusedWindowAttribute), string(window, kAXRoleAttribute) == kAXWindowRole
        else { return .unavailable }
        let subrole = string(window, kAXSubroleAttribute)
        guard subrole != kAXDialogSubrole, subrole != kAXSystemDialogSubrole else { return .unavailable }
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children) == .success,
            let children = children as? [AXUIElement],
            children.contains(where: { string($0, kAXRoleAttribute) == kAXSheetRole }) { return .unavailable }
        return .files
    }

    @MainActor
    static func post(keyCode: CGKeyCode, flags: CGEventFlags, pid: Int32) {
        guard AXIsProcessTrusted(), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return }
        for event in [down, up] {
            event.flags = flags
            event.markSynthetic()
            event.postToPid(pid)
        }
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
