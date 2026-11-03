// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

@MainActor
struct PlayerApps {
    struct Launch: Equatable, Sendable {
        var bundleID: String
        var processID: pid_t
    }

    enum Failure: Error {
        case notInstalled
        case noPlayCommand
        case automation(Int)
    }

    var isInstalled: (String) -> Bool
    var isRunning: (String) -> Bool
    var open: (String) async throws -> Void
    var play: (String) async throws -> Void
    var watchLaunches: (@escaping @MainActor (Launch) -> Void) -> [NotificationToken]
    var quit: (Launch) -> Bool
    var canPlay: (String) -> Bool = { $0 == LastPlayer.spotify }

    static func workspace() -> Self {
        Self(
            isInstalled: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
            isRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty },
            open: { id in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                    throw Failure.notInstalled
                }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            },
            play: { id in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                    throw Failure.notInstalled
                }
                try await sendPlay(bundleID: id, bundleURL: url)
            },
            watchLaunches: { onLaunch in
                let center = NSWorkspace.shared.notificationCenter
                return [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification].map { name in
                    let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                            let id = app.bundleIdentifier else { return }
                        let launch = Launch(bundleID: id, processID: app.processIdentifier)
                        Task { @MainActor in onLaunch(launch) }
                    }
                    return NotificationToken(token, center: center)
                }
            },
            quit: { launch in
                guard let app = NSRunningApplication(processIdentifier: launch.processID),
                    app.bundleIdentifier == launch.bundleID else { return false }
                return app.forceTerminate() || app.terminate()
            },
            canPlay: { id in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return false }
                return (try? playCode(bundleURL: url)) != nil
            }
        )
    }

    static func isRetryable(_ error: any Error) -> Bool {
        let status: Int
        if case Failure.automation(let code) = error {
            status = code
        } else {
            let error = error as NSError
            guard error.domain == NSOSStatusErrorDomain else { return false }
            status = error.code
        }
        return status == -600 || status == -609
    }

    @concurrent
    private static func sendPlay(bundleID: String, bundleURL: URL) async throws {
        try Task.checkCancellation()
        let code = try playCode(bundleURL: bundleURL)
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let event = NSAppleEventDescriptor(
            eventClass: code.eventClass, eventID: code.eventID, targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        try Task.checkCancellation()
        let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, .dontRecord], timeout: 2)
        let status = reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0
        if status != 0 { throw Failure.automation(Int(status)) }
    }

    private nonisolated static func playCode(bundleURL: URL) throws -> (eventClass: UInt32, eventID: UInt32) {
        guard let bundle = Bundle(url: bundleURL),
            let name = bundle.object(forInfoDictionaryKey: "OSAScriptingDefinition") as? String,
            !name.isEmpty, !name.contains("/"), !name.contains("\\"),
            let resources = bundle.resourceURL,
            let url = bundle.url(forResource: (name as NSString).deletingPathExtension, withExtension: "sdef")
        else { throw Failure.noPlayCommand }
        var relationship = FileManager.URLRelationship.other
        try FileManager.default.getRelationship(
            &relationship, ofDirectoryAt: resources.resolvingSymlinksInPath(), toItemAt: url.resolvingSymlinksInPath())
        guard relationship == .contains else { throw Failure.noPlayCommand }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let maximumBytes = 256 * 1024
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw Failure.noPlayCommand }
        let document = try XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever)
        let commands = try document.nodes(forXPath: "/dictionary/suite/command[@name='play']")
        guard commands.count == 1, let command = commands.first as? XMLElement,
            let code = command.attribute(forName: "code")?.stringValue,
            code.utf8.count == 8, code.utf8.allSatisfy({ (0x20...0x7E).contains($0) }),
            try command.nodes(forXPath: "parameter[not(@optional='yes')]|direct-parameter[not(@optional='yes')]").isEmpty
        else { throw Failure.noPlayCommand }
        return (code.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) },
                code.utf8.suffix(4).reduce(0) { $0 << 8 | UInt32($1) })
    }
}
