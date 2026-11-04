import CoreGraphics

enum RemoteDialogWindows {
    static func current() -> Set<RemoteDialogModule.Dialog> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] ?? []
        return visible(info)
    }

    static func visible(_ info: [[String: Any]]) -> Set<RemoteDialogModule.Dialog> {
        let owners: Set<String> = ["UserNotificationCenter", "CoreServicesUIAgent",
                                   "SecurityAgent", "universalAccessAuthWarn"]
        return Set(info.compactMap { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owners.contains(owner),
                  let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let process = window[kCGWindowOwnerPID as String] as? Int,
                  let number = window[kCGWindowNumber as String] as? Int else { return nil }
            return RemoteDialogModule.Dialog(processID: process, windowID: number)
        })
    }
}
