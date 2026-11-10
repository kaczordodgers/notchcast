// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/ColorPicker/ColorPickerModule*.swift
// notchcast-sources: Tinycast/Features/ColorPicker/Model/*.swift
// notchcast-sources: Tinycast/Features/ColorPicker/Service/*.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorValue.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorFormat.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorSpaces.swift
import AppKit

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor enum NotchcastCore {
    static var instance: ColorPickerModule?
    static var colorPicker: ColorPickerModule { instance! }
}

@MainActor final class AppCore {
    enum Tone { case danger }
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ message: String, tone: Tone) { messages.append(message) }
}

@main
struct ColorPickerModuleTest {
    @MainActor static func main() async {
        let suite = "color-module-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.colorPicker, false)
        var samples = 0
        var callback: (@MainActor (NSColor?) -> Void)?
        var copied: [String] = []
        var copySucceeds = true
        let service = ColorPickerService(defaults: defaults, sample: {
            samples += 1
            callback = $0
        }, copy: { copied.append($0); return copySucceeds })
        let module = ColorPickerModule(service: service)
        NotchcastCore.instance = module
        let controller = NotchcastModuleController([
            .init(requires: [.colorPicker], module: module)
        ], preferences: preferences)
        controller.run()
        let command = ColorPickerModule.launcherCommand
        command.run()
        precondition(samples == 0)
        precondition(AppCore.shared.messages.isEmpty)
        preferences.set(.colorPicker, true)
        await settle()
        command.run()
        callback?(.red)
        precondition(samples == 1 && copied == ["#FF0000"])
        command.run()
        command.run()
        precondition(AppCore.shared.messages.isEmpty)
        callback?(nil)
        precondition(AppCore.shared.messages.isEmpty)
        AppCore.shared.messages.removeAll()
        copySucceeds = false
        command.run()
        callback?(.blue)
        precondition(AppCore.shared.messages == [String(localized: "Pick Color")])
        command.run()
        let stale = callback
        preferences.set(.colorPicker, false)
        await settle()
        stale?(.green)
        command.run()
        precondition(samples == 4 && copied == ["#FF0000", "#0000FF"])
        precondition(AppCore.shared.messages == [String(localized: "Pick Color")])
        NotchcastCore.instance = nil
        print("PASS: color module command, switch lifecycle, copy failure and stale callback")
    }

    @MainActor private static func settle() async {
        for _ in 0..<40 { await Task.yield() }
    }
}
