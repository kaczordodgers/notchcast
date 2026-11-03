import Foundation

struct BrightnessDisplay: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let rawValue: UInt32
        let uuid: String

        init(rawValue: UInt32, uuid: String) {
            self.rawValue = rawValue
            self.uuid = uuid.uppercased()
        }
    }

    enum Control: Sendable {
        case system, ddc, software
    }

    let id: ID
    let name: String
    let isBuiltIn: Bool
    let control: Control
    var level: BrightnessLevel
}
