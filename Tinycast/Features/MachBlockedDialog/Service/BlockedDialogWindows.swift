import CoreGraphics
import Foundation

enum BlockedDialogWindows {
    static func current() -> [BlockedDialogWindow] {
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID) as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            guard let owner = entry[kCGWindowOwnerName as String] as? String,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            let window = BlockedDialogWindow(owner: owner, processID: pid, windowID: id,
                layer: layer, width: frame.width, height: frame.height)
            return window.isCandidate ? window : nil
        }
    }
}
