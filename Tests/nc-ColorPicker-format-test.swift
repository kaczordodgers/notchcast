// notchcast-sources: Tinycast/Features/ColorPicker/Model/*.swift
// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/ColorPicker/Service/*.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorValue.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorFormat.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ColorSpaces.swift
import AppKit

@main
struct ColorPickerTests {
    @MainActor
    static func main() {
        let color = ColorValue(red: 1, green: 0.5, blue: 0, alpha: 0.25)
        precondition(ColorPickerFormat.hex.string(for: color) == "#FF8000")
        precondition(ColorPickerFormat.hexLowercase.string(for: color) == "#ff8000")
        precondition(ColorPickerFormat.rgb.string(for: color) == "rgb(255, 128, 0)")
        precondition(ColorPickerFormat.hsl.string(for: color) == "hsl(30deg, 100%, 50%)")
        precondition(ColorPickerFormat.swiftUIColor.string(for: color)
            == "Color(.sRGB, red: 1.000000, green: 0.500000, blue: 0.000000, opacity: 0.250000)")
        precondition(ColorPickerFormat.nsColorLiteral.string(for: color)
            == "#colorLiteral(red: 1.000000, green: 0.500000, blue: 0.000000, alpha: 0.250000)")
        precondition(ColorPickerFormat.hex.string(for: ColorValue(red: .nan, green: -1, blue: 2)) == "#0000FF")
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let colorSpace = NSColorSpace(cgColorSpace: space) else {
            fatalError("Missing linear color space")
        }
        let linear = NSColor(colorSpace: colorSpace, components: [0.5, 0.5, 0.5, 0.25], count: 4)
        guard let converted = ColorPickerService.sRGBValue(for: linear) else { fatalError("Conversion failed") }
        precondition(abs(converted.red - 0.735357) < 0.0001)
        precondition(abs(converted.alpha - 0.25) < 0.0001)
        let suite = "color-picker-test-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        var callback: (@MainActor (NSColor?) -> Void)?
        var copied: [String] = []
        let service = ColorPickerService(defaults: defaults, sample: { callback = $0 }, copy: {
            copied.append($0)
            return true
        })
        precondition(service.format == .hex)
        service.pick(isEnabled: false) { precondition(!$0) }
        precondition(callback == nil)
        service.pick(isEnabled: true) { precondition($0) }
        var busyCompleted = false
        service.pick(isEnabled: true) {
            precondition(!$0)
            busyCompleted = true
        }
        precondition(busyCompleted)
        callback?(NSColor.red)
        precondition(copied == ["#FF0000"])
        service.format = .rgb
        precondition(ColorPickerService(defaults: defaults).format == .rgb)
        var stopCompletions = 0
        service.pick(isEnabled: true) { precondition(!$0); stopCompletions += 1 }
        let stale = callback
        service.stop()
        service.stop()
        precondition(stopCompletions == 1)
        stale?(NSColor.blue)
        precondition(stopCompletions == 1)
        service.pick(isEnabled: true) { precondition(!$0) }
        callback?(nil)
        precondition(copied.count == 1)
        print("ColorPicker: all checks passed")
    }
}
