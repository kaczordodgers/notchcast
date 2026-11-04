import Foundation

enum CleanCategory: String, CaseIterable, Sendable {
    case caches, logs, derivedData, deviceSupport, installers, firmware, leftovers, trash

    var relativeRoot: String {
        switch self {
        case .caches: "Library/Caches"
        case .logs: "Library/Logs"
        case .derivedData: "Library/Developer/Xcode/DerivedData"
        case .deviceSupport: "Library/Developer/Xcode/iOS DeviceSupport"
        case .installers: "Applications"
        case .firmware: "Library/iTunes/iPhone Software Updates"
        case .leftovers: "Library/Application Support"
        case .trash: ".Trash"
        }
    }
}
