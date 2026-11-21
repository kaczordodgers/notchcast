// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MonitorVolume: Equatable, Sendable {
    var path: String
    var name: String
    var size: UInt64?
    var isInternal: Bool?
    var isRemovable: Bool?
    var isEjectable: Bool?
    var isLocal: Bool?
    var isRootFileSystem: Bool?

    var canEject: Bool {
        isLocal == true && !(isRootFileSystem ?? (path == "/"))
            && (isInternal != true || isRemovable == true || isEjectable == true)
    }
}

enum MonitorVolumes {
    static let rowLimit = 4
    private static let ejectPrefix = "eject:"

    static func listed(_ volumes: [MonitorVolume], locale: Locale) -> [MonitorVolume] {
        volumes.filter(\.canEject).sorted {
            let order = $0.name.compare($1.name, options: [.caseInsensitive, .numeric, .widthInsensitive], locale: locale)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    static func action(for path: String) -> String { ejectPrefix + path }

    static func path(for action: String) -> String? {
        guard action.hasPrefix(ejectPrefix + "/") else { return nil }
        return String(action.dropFirst(ejectPrefix.count))
    }
}

struct MonitorEjectResult: Equatable, Sendable {
    var errorDomain: String?
    var errorCode: Int?
    var holder: String?
    var stillMounted = false

    var outcome: MonitorEjectOutcome {
        guard let errorDomain, stillMounted else { return .ejected }
        if errorDomain == NSCocoaErrorDomain, errorCode == 769 { return .busy(holder) }
        return .failed
    }
}

enum MonitorEjectOutcome: Equatable, Sendable {
    case ejected
    case busy(String?)
    case failed
}
