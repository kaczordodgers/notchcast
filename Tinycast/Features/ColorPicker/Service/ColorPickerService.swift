import AppKit

@MainActor
final class ColorPickerService {
    enum Outcome { case copied, cancelled, copyFailed }

    private let defaults: UserDefaults
    private let sample: (@escaping @MainActor (NSColor?) -> Void) -> Void
    private let copy: (String) -> Bool
    private var operation: UUID?
    private var completion: ((Outcome) -> Void)?
    nonisolated static let formatKey = "notchcast.colorPicker.format"

    var format: ColorPickerFormat {
        get {
            defaults.string(forKey: Self.formatKey).flatMap(ColorPickerFormat.init(rawValue:)) ?? .hex
        }
        set { defaults.set(newValue.rawValue, forKey: Self.formatKey) }
    }

    init(
        defaults: UserDefaults = NotchcastIdentity.current.defaults,
        sample: @escaping (@escaping @MainActor (NSColor?) -> Void) -> Void = { completion in
            NSColorSampler().show { color in
                Task { @MainActor in completion(color) }
            }
        },
        copy: @escaping (String) -> Bool = { text in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        }
    ) {
        self.defaults = defaults
        self.sample = sample
        self.copy = copy
    }

    func pick(isEnabled: Bool, completion: @escaping (Outcome) -> Void) {
        guard isEnabled, operation == nil else {
            completion(.cancelled)
            return
        }
        let identity = UUID()
        operation = identity
        self.completion = completion
        let selectedFormat = format
        sample { [weak self] color in
            guard let self, self.operation == identity else { return }
            self.operation = nil
            self.completion = nil
            guard let color, let value = Self.sRGBValue(for: color) else {
                completion(.cancelled)
                return
            }
            completion(self.copy(selectedFormat.string(for: value)) ? .copied : .copyFailed)
        }
    }

    func stop() {
        operation = nil
        let pending = completion
        completion = nil
        pending?(.cancelled)
    }

    static func sRGBValue(for color: NSColor) -> ColorValue? {
        guard let converted = color.usingColorSpace(.sRGB) else { return nil }
        return ColorValue(
            red: converted.redComponent, green: converted.greenComponent,
            blue: converted.blueComponent, alpha: converted.alphaComponent)
    }
}
