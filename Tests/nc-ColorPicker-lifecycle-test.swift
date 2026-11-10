// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/ColorPicker/ColorPickerModule.swift
// notchcast-sources: Tinycast/Features/ColorPicker/ColorPickerModule+Registration.swift
// notchcast-sources: Tinycast/Features/ColorPicker/Model/*.swift
// notchcast-sources: Tinycast/Features/ColorPicker/Service/*.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorValue.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorFormat.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorSpaces.swift
import AppKit

@MainActor final class AppCore {}

@main
struct ColorPickerLifecycleTest {
    @MainActor
    static func main() async {
        let suite = "color-picker-lifecycle-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.colorPicker, false)
        var callback: (@MainActor (NSColor?) -> Void)?
        var samples = 0
        var copied: [String] = []
        let service = ColorPickerService(defaults: defaults, sample: {
            samples += 1
            callback = $0
        }, copy: {
            copied.append($0)
            return true
        })
        let module = ColorPickerModule(service: service)
        let controller = NotchcastModuleController([
            .init(requires: [.colorPicker], module: module)
        ], preferences: preferences)
        controller.run()
        module.pick { precondition($0 == .cancelled) }
        precondition(samples == 0)
        precondition(!NotchcastFeature.colorPicker.needsIsland)
        precondition(NotchcastFeature.colorPicker.requiredGrants.isEmpty)

        preferences.set(.colorPicker, true)
        await settle()
        preferences.set(.island, false)
        await settle()
        module.pick { precondition($0 == .copied) }
        callback?(.red)
        precondition(samples == 1 && copied == ["#FF0000"])

        module.pick { precondition($0 == .cancelled) }
        let stale = callback
        preferences.set(.colorPicker, false)
        await settle()
        module.pick { precondition($0 == .cancelled) }
        precondition(samples == 2)
        preferences.set(.colorPicker, true)
        await settle()
        stale?(.blue)
        precondition(copied == ["#FF0000"])

        module.format = .rgb
        precondition(ColorPickerModule(service: ColorPickerService(defaults: defaults)).format == .rgb)
        module.pick { precondition($0 == .copied) }
        preferences.set(.islandStatusMessages, false)
        await settle()
        callback?(.green)
        precondition(samples == 3 && copied == ["#FF0000", "rgb(0, 255, 0)"])

        preferences.set(.colorPicker, false)
        await settle()
        module.pick { precondition($0 == .cancelled) }
        precondition(samples == 3)
        let entries = ColorPickerModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.colorPicker] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === ColorPickerModule.shared)
        print("PASS: color picker switch gates sampling, stops stale copies and preserves format; registration entry")
    }

    @MainActor
    private static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
