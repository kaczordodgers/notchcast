import Foundation

enum ColorPickerFormat: String, CaseIterable, Sendable {
    case hex
    case hexLowercase
    case rgb
    case hsl
    case swiftUIColor
    case nsColorLiteral

    func string(for color: ColorValue) -> String {
        switch self {
        case .hex: return ColorFormat.hex.string(for: color)
        case .hexLowercase: return ColorFormat.hex.string(for: color).lowercased()
        case .rgb:
            return "rgb(\(Int((color.red * 255).rounded())), \(Int((color.green * 255).rounded())), "
                + "\(Int((color.blue * 255).rounded())))"
        case .hsl: return ColorFormat.hsl.string(for: color)
        case .swiftUIColor:
            return "Color(.sRGB, red: \(Self.decimal(color.red)), green: \(Self.decimal(color.green)), "
                + "blue: \(Self.decimal(color.blue)), opacity: \(Self.decimal(color.alpha)))"
        case .nsColorLiteral:
            return "#colorLiteral(red: \(Self.decimal(color.red)), green: \(Self.decimal(color.green)), "
                + "blue: \(Self.decimal(color.blue)), alpha: \(Self.decimal(color.alpha)))"
        }
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
