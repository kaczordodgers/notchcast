// Adapted from Damian Tools (GPL-3.0-or-later)
import Foundation

enum CleanOptimizeTask: String, CaseIterable, Sendable {
    case quickLook, downloadHistory, openWithMenu

    var titleID: String { "clean.optimize.\(rawValue).title" }
    var detailID: String { "clean.optimize.\(rawValue).detail" }
    var selectedByDefault: Bool { self != .openWithMenu }
}
