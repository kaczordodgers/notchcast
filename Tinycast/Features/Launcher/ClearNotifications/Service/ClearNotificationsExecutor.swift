import AppKit

enum ClearNotificationsExecutor {
    @concurrent
    static func execute(_ source: String) async throws -> String {
        try Task.checkCancellation()
        guard let script = NSAppleScript(source: source) else {
            throw ClearNotificationsFailure.preparationFailed
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        try Task.checkCancellation()
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            throw ClearNotificationsFailure.appleScript(code: code)
        }
        return result.stringValue ?? ""
    }
}
