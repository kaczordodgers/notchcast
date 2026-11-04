import Foundation

nonisolated struct StartupItem: Sendable, Equatable {
    enum Kind: Sendable { case userAgent, systemAgent, daemon, loginItem, appService }
    let label: String
    let kind: Kind
    let path: String
    let program: String?
    let disabled: Bool?
    let loaded: Bool?

    static func decode(_ data: Data, path: String, kind: Kind,
                       disabled: Bool? = nil, loaded: Bool? = nil) throws -> Self {
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String, !label.isEmpty else { throw Failure.invalidPlist }
        return Self(label: label, kind: kind, path: path,
                    program: plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first,
                    disabled: disabled, loaded: loaded)
    }

    enum Failure: Error { case invalidPlist, readOnly, unknownState }

    func commands(enabled: Bool, uid: UInt32, home: String) throws -> [[String]] {
        let folder = URL(filePath: home).appending(path: "Library/LaunchAgents").path
        let file = URL(filePath: path).standardizedFileURL
        guard kind == .userAgent, file.deletingLastPathComponent().path == folder,
              file.pathExtension == "plist", !label.hasPrefix("com.apple."),
              !label.contains("/"), !label.contains("\0"), !label.isEmpty else { throw Failure.readOnly }
        guard let loaded, disabled != nil else { throw Failure.unknownState }
        let domain = "gui/\(uid)"
        let target = "\(domain)/\(label)"
        if enabled { return [["enable", target]] + (loaded ? [] : [["bootstrap", domain, file.path]]) }
        return [["disable", target]] + (loaded ? [["bootout", target]] : [])
    }
}
