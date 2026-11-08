// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandID.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction+EntryID.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/QuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/CustomQuickAction.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/Quicklink.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/CustomCommands/Model/CustomCommand.swift
// notchcast-sources: Tinycast/Features/AppleShortcuts/Model/AppleShortcut.swift
// notchcast-sources: Tinycast/Features/Snippets/Model/Snippet.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowCommand.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowCycle.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowPlacementEngine.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutAnchor.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutDisplay.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayout.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowLayoutGeometry.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomLayoutKind.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomLayoutEngine.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomGrid.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/RoomWindow.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/Room.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/CustomWindowSize.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
// notchcast-reads: Tinycast/**/*.swift
import Foundation

@main @MainActor struct NotchcastLegacyEntryIDTests {
    static func main() throws {
        let files = FileManager.default.enumerator(at: URL(fileURLWithPath: "Tinycast"), includingPropertiesForKeys: nil)
        var ids: [String] = []
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            ids += text.matches(of: /legacyID: "([^"]+)"/).map { String($0.1) }
        }
        precondition(ids.contains("command:theme"), "The shipped catalog's legacy ids were not found: \(ids)")
        for id in ids {
            precondition(HotKeyAction(entryID: id) == .notchcastCommand(entryID: id),
                         "\(id) must resolve to its Notchcast command for hotkeys and deeplinks")
        }
        print("PASS: \(ids.count) legacy Notchcast entry ids resolve: \(ids.sorted())")
    }
}
