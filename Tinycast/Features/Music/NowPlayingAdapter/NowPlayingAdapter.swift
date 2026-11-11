// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 794608a; reduced to the system session for Tinycast.

import AppKit
import Foundation
import Synchronization

private enum MediaRemote {
    // The immutable dlopen handle permits concurrent lookups and outlives every callback.
    private final class Library: @unchecked Sendable {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)

        deinit { if let handle { dlclose(handle) } }
    }

    private static let library = Library()
    private typealias Info = @convention(c) (
        DispatchQueue, @escaping @convention(block) @Sendable (NSDictionary?) -> Void
    ) -> Void
    private typealias PID = @convention(c) (
        DispatchQueue, @escaping @convention(block) @Sendable (Int32) -> Void
    ) -> Void
    private typealias Playing = @convention(c) (
        DispatchQueue, @escaping @convention(block) @Sendable (Bool) -> Void
    ) -> Void
    private typealias DisplayID = @convention(c) (
        DispatchQueue, @escaping @convention(block) @Sendable (NSString?) -> Void
    ) -> Void

    struct Snapshot: Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var elapsed: Double?
        var timestamp: Date?
        var rate: Double?
        var artwork: Data?
        var pid: Int32 = 0
        var bundleID: String?
        var playing: Bool?
        var shuffleMode: Double?
        var repeatMode: Double?

        func reply(at now: Date) -> [String: Any] {
            typealias Wire = NowPlayingAdapterWire
            var result: [String: Any] = [Wire.pid: pid, Wire.isPlaying: playing ?? ((rate ?? 0) > 0)]
            result[Wire.displayID] = bundleID
            result[Wire.Info.shuffleMode.key] = shuffleMode
            result[Wire.Info.repeatMode.key] = repeatMode
            result[Wire.Info.title.key] = title
            result[Wire.Info.artist.key] = artist
            result[Wire.Info.album.key] = album
            result[Wire.Info.duration.key] = duration
            let speed = playing == false ? 0 : max(0, rate ?? 0)
            if let elapsed {
                let age = timestamp.map { max(0, now.timeIntervalSince($0)) } ?? 0
                result[Wire.Info.elapsedTime.key] = elapsed + age * speed
            }
            result[Wire.Info.playbackRate.key] = speed
            return result.filter { ($0.value as? Double)?.isFinite != false }
        }
    }

    static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle = library.handle,
              let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    static func stringConstant(_ name: String) -> String? {
        guard let handle = library.handle else { return nil }
        guard let symbol = dlsym(handle, name) ?? dlsym(handle, "_" + name) else { return nil }
        return symbol.assumingMemoryBound(to: NSString?.self).pointee as String?
    }

    @concurrent static func read() async throws -> Snapshot {
        try Task.checkCancellation()
        let snapshot = try readSnapshot()
        try Task.checkCancellation()
        return snapshot
    }

    private static func readSnapshot() throws -> Snapshot {
        guard let info = function("MRMediaRemoteGetNowPlayingInfo", as: Info.self),
              let pid = function("MRMediaRemoteGetNowPlayingApplicationPID", as: PID.self),
              let playing = function("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: Playing.self),
              let display = function("MRMediaRemoteGetNowPlayingApplicationDisplayID", as: DisplayID.self) else {
            throw AdapterFailure.unavailable
        }
        let result = Mutex(Snapshot())
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.tinycast.now-playing.callbacks")
        group.enter()
        info(queue) { dictionary in
            result.withLock { snapshot in
                func value(_ suffix: String) -> Any? {
                    let key = "kMRMediaRemoteNowPlayingInfo\(suffix)"
                    return dictionary?[key] ?? dictionary?["_" + key]
                }
                func finite(_ suffix: String) -> Double? {
                    guard let number = value(suffix) as? NSNumber, number.doubleValue.isFinite else { return nil }
                    return number.doubleValue
                }
                snapshot.title = value("Title") as? String
                snapshot.artist = value("Artist") as? String
                snapshot.album = value("Album") as? String
                snapshot.duration = finite("Duration")
                snapshot.elapsed = finite("ElapsedTime")
                snapshot.timestamp = value("Timestamp") as? Date
                snapshot.rate = finite("PlaybackRate")
                snapshot.shuffleMode = finite("ShuffleMode")
                snapshot.repeatMode = finite("RepeatMode")
                if let data = value("ArtworkData") as? Data, data.count <= NowPlayingAdapterWire.maximumArtworkBytes {
                    snapshot.artwork = data
                }
            }
            group.leave()
        }
        group.enter()
        pid(queue) { value in result.withLock { $0.pid = value }; group.leave() }
        group.enter()
        playing(queue) { value in result.withLock { $0.playing = value }; group.leave() }
        group.enter()
        display(queue) { value in result.withLock { $0.bundleID = value as String? }; group.leave() }
        guard group.wait(timeout: .now() + 2) == .success else { throw AdapterFailure.timeout }
        return result.withLock { $0 }
    }

    static func send(_ command: Int32, position: Double?) -> Bool {
        typealias Send = @convention(c) (Int32, CFDictionary?) -> Bool
        guard let send = function("MRMediaRemoteSendCommand", as: Send.self) else { return false }
        var options: CFDictionary?
        if let position {
            guard let key = stringConstant("kMRMediaRemoteOptionPlaybackPosition") else { return false }
            options = [key: position] as CFDictionary
        }
        return send(command, options)
    }
}

private enum AdapterFailure: Error {
    case unavailable
    case timeout
}

@MainActor
private final class NowPlayingAdapter {
    private var observers: [NotificationToken] = []
    private var pending: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var input = Data()
    private var discardingInput = false
    private var previousSnapshot: MediaRemote.Snapshot?

    func watch() {
        typealias Register = @convention(c) (DispatchQueue) -> Void
        guard let register = MediaRemote.function("MRMediaRemoteRegisterForNowPlayingNotifications", as: Register.self) else {
            emit([NowPlayingAdapterWire.error: "unavailable"])
            exit(1)
        }
        register(.main)
        let names = ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                     "kMRMediaRemotePlayerNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemotePlayerIsPlayingDidChangeNotification",
                     "kMRMediaRemotePlayerPlaybackStateDidChangeNotification"]
        for symbol in names {
            let name = MediaRemote.stringConstant(symbol) ?? symbol
            let center = NotificationCenter.default
            observers.append(NotificationToken(center.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }, center: center))
        }
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { exit(0) }
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        refresh()
    }

    private func refresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(120))
                let snapshot = try await MediaRemote.read()
                try Task.checkCancellation()
                self?.publish(snapshot)
            } catch is CancellationError {
                return
            } catch {
                self?.emit([NowPlayingAdapterWire.error: "metadata timeout"])
                exit(1)
            }
        }
    }

    private func publish(_ snapshot: MediaRemote.Snapshot) {
        var reply = snapshot.reply(at: Date())
        if let previousSnapshot,
           previousSnapshot.pid == snapshot.pid, previousSnapshot.bundleID == snapshot.bundleID,
           previousSnapshot.title == snapshot.title, previousSnapshot.artist == snapshot.artist,
           previousSnapshot.album == snapshot.album, previousSnapshot.artwork == snapshot.artwork {
            reply[NowPlayingAdapterWire.artworkUnchanged] = true
        } else {
            reply[NowPlayingAdapterWire.artworkBase64] = snapshot.artwork?.base64EncodedString()
        }
        previousSnapshot = snapshot
        reply[NowPlayingAdapterWire.displayName] = NSRunningApplication(processIdentifier: snapshot.pid)?.localizedName
        emit(reply)
    }

    private func receive(_ data: Data) {
        for byte in data {
            if byte == 10 {
                if !discardingInput { command(input) } else { emit([NowPlayingAdapterWire.sent: false]) }
                input = Data()
                discardingInput = false
            } else if !discardingInput {
                if input.count < 2_048 { input.append(byte) } else { input = Data(); discardingInput = true }
            }
        }
    }

    private func command(_ data: Data) {
        guard let reply = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = reply["command"] as? String,
              let rawPID = reply["pid"] as? NSNumber,
              let pid = Int32(exactly: rawPID.doubleValue), pid > 0 else { emit([NowPlayingAdapterWire.sent: false]); return }
        let identifier: Int32
        var position: Double?
        switch name {
        case "play": identifier = 0
        case "pause": identifier = 1
        case "toggle": identifier = 2
        case "next": identifier = 4
        case "previous": identifier = 5
        case "seek":
            guard let value = reply["position"] as? Double, value.isFinite, value >= 0 else {
                emit([NowPlayingAdapterWire.sent: false]); return
            }
            identifier = 24
            position = value
        default: emit([NowPlayingAdapterWire.sent: false]); return
        }
        let previous = commandTask
        commandTask = Task { [weak self, position] in
            await previous?.value
            do {
                let current = try await MediaRemote.read()
                guard current.pid == pid else { self?.emit([NowPlayingAdapterWire.sent: false]); return }
                self?.emit([NowPlayingAdapterWire.sent: MediaRemote.send(identifier, position: position)])
                self?.refresh()
            } catch { self?.emit([NowPlayingAdapterWire.sent: false]) }
        }
    }

    private func emit(_ reply: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(reply),
              let data = try? JSONSerialization.data(withJSONObject: reply, options: .withoutEscapingSlashes) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

@_cdecl("tinycast_now_playing_watch")
@MainActor
public func tinycastNowPlayingWatch() {
    let adapter = NowPlayingAdapter()
    adapter.watch()
    withExtendedLifetime(adapter) { RunLoop.main.run() }
}
