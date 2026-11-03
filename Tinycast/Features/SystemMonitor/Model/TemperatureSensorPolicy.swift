// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

nonisolated enum TemperatureSensorPolicy {
    static let gpuKeys = ["Tg0f", "Tg0j", "Tg0b", "Tg0T", "TG0P", "TG0D", "Tg1a", "Tg4a"]
    static let fallbackCPUKeys = [
        "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0T", "Tp0P", "Tp0X", "Tp0b",
        "Te05", "Te0S", "Te09", "Te0H", "TC0P", "TC0D"
    ]

    static func cpuKeys(brand: String) -> [String] {
        switch brand.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Apple M1":
            return ["Te0a", "Te0x", "Te3a", "Te3x", "Tp2a", "Tp2x", "Tp3a", "Tp3x",
                    "Tp4a", "Tp4x", "Tp5a", "Tp5x", "Tp7a", "Tp7x", "Tp8a", "Tp8x", "Tp9a", "Tp9x"]
        case "Apple M1 Pro", "Apple M1 Max", "Apple M1 Ultra":
            return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case "Apple M2", "Apple M2 Pro", "Apple M2 Max", "Apple M2 Ultra":
            return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case "Apple M3", "Apple M3 Pro", "Apple M3 Max", "Apple M3 Ultra":
            return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B",
                    "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        case "Apple M4 Pro":
            return ["Tex0", "Tex1", "Tex2", "Tex3", "Tpx0", "Tpx1", "Tpx2", "Tpx3", "Tpx4", "Tpx5",
                    "Tpx8", "Tpx9", "TpxA", "TpxB", "TpxC", "TpxD"]
        case "Apple M4", "Apple M4 Max", "Apple M4 Ultra":
            return ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case "Apple M5", "Apple M5 Pro", "Apple M5 Max", "Apple M5 Ultra":
            return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X",
                    "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        default: return fallbackCPUKeys
        }
    }

    static func hottest(_ readings: [Double]) -> Double? {
        readings.filter { $0.isFinite && $0 >= 10 && $0 < 125 }.max()
    }

    static func average(_ readings: [Double]) -> Double? {
        let valid = readings.filter { $0.isFinite && $0 >= 10 && $0 < 125 }
        return valid.isEmpty ? nil : valid.reduce(0, +) / Double(valid.count)
    }

    static func isCPUKey(_ key: String, includesTf: Bool) -> Bool {
        key.utf8.count == 4 && !key.hasSuffix("b") && !key.hasSuffix("z")
            && (key.hasPrefix("Tp") || key.hasPrefix("Te") || (includesTf && key.hasPrefix("Tf")))
    }

    static func isGPUKey(_ key: String) -> Bool {
        key.utf8.count == 4 && key.hasPrefix("Tg")
    }
}
