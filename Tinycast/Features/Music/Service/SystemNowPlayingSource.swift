// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 794608a's watched process lifetime and restart policy for Tinycast.

import AppKit
import Foundation
import Synchronization

@MainActor
final class SystemNowPlayingSource: NowPlayingSource {
    enum State: Equatable {
        case stopped
        case starting
        case watching
        case retrying(NowPlayingAdapterReply.Failure)
    }

    private(set) var state: State = .stopped
    private(set) var commandFailure: NowPlayingAdapterReply.Failure?
    private var onChange: (@MainActor () -> Void)?
    private var playback: NowPlaying?
    private var pid: Int32 = 0
    private var connection: Connection?
    private var reader: Task<Void, Never>?
    private var restart: Task<Void, Never>?
    private var termination: NotificationToken?
    private var terminationMessage: NotificationCenter.ObservationToken?
    private var generation = UUID()
    private var failures = 0
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    isolated deinit {
        reader?.cancel()
        restart?.cancel()
        connection?.stop()
        if let terminationMessage { NotificationCenter.default.removeObserver(terminationMessage) }
    }

    func watch(_ onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard state == .stopped else { return }
        failures = 0
        launch()
    }

    func unwatch() {
        onChange = nil
        generation = UUID()
        reader?.cancel()
        reader = nil
        restart?.cancel()
        restart = nil
        connection?.stop()
        connection = nil
        termination = nil
        if let terminationMessage { NotificationCenter.default.removeObserver(terminationMessage) }
        terminationMessage = nil
        playback = nil
        pid = 0
        commandFailure = nil
        state = .stopped
    }

    func read() async throws -> NowPlaying? {
        try Task.checkCancellation()
        switch state {
        case .watching: return playback
        case .retrying(let failure): throw failure
        case .starting: return nil
        case .stopped: throw NowPlayingAdapterReply.Failure.unavailable
        }
    }

    func send(_ command: PlayerCommand) {
        guard state == .watching, pid > 0, let connection else { return }
        var message: [String: Any] = ["pid": pid]
        switch command {
        case .play: message["command"] = "play"
        case .pause: message["command"] = "pause"
        case .togglePlayPause: message["command"] = "toggle"
        case .next: message["command"] = "next"
        case .previous: message["command"] = "previous"
        case .seek(let position):
            guard position.isFinite, position >= 0 else { return }
            message["command"] = "seek"
            message["position"] = position
        case .volume: return
        }
        do {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try connection.write(data)
        } catch {
            fail(.commandRejected)
        }
    }

    private func launch() {
        guard onChange != nil else { return }
        generation = UUID()
        let requested = generation
        state = .starting
        do {
            let library = bundle.bundleURL.appending(path: "Contents/Helpers/libNowPlayingAdapter.dylib")
            guard let script = bundle.url(forResource: "now-playing", withExtension: "pl"),
                  FileManager.default.fileExists(atPath: library.path) else {
                throw NowPlayingAdapterReply.Failure.unavailable
            }
            let connection = try Connection(script: script, library: library)
            self.connection = connection
            let center = NotificationCenter.default
            if #available(macOS 27, *) {
                terminationMessage = center.addObserver(of: NSApplication.shared, for: .willTerminate) { [weak self] _ in
                    self?.unwatch()
                }
            } else {
                termination = NotificationToken(center.addObserver(
                    forName: NSApplication.willTerminateNotification, object: nil, queue: nil
                ) { _ in connection.stop() }, center: center)
            }
            reader = Task.detached(priority: .utility) { [weak self] in
                let started = ContinuousClock.now
                var failure: NowPlayingAdapterReply.Failure = .unavailable
                await withTaskCancellationHandler {
                    do {
                        var lines = NowPlayingAdapterReply.Lines()
                        var previous: NowPlaying?
                        while !Task.isCancelled {
                            let chunk = connection.output.availableData
                            guard !chunk.isEmpty else { break }
                            for line in try lines.append(chunk) {
                                try Task.checkCancellation()
                                let reply = try NowPlayingAdapterReply.parse(line, previous: previous, now: Date())
                                switch reply {
                                case .playback(let next, _): previous = next
                                case .idle: previous = nil
                                case .command: break
                                }
                                await self?.receive(reply, generation: requested)
                            }
                        }
                    } catch let error as NowPlayingAdapterReply.Failure {
                        failure = error
                    } catch {}
                    connection.stop()
                    connection.wait()
                } onCancel: {
                    connection.stop()
                }
                guard !Task.isCancelled else { return }
                await self?.ended(failure, generation: requested, healthy: started.duration(to: .now) >= .seconds(60))
            }
        } catch {
            ended(.unavailable, generation: requested, healthy: false)
        }
    }

    private func receive(_ reply: NowPlayingAdapterReply, generation requested: UUID) {
        guard generation == requested, onChange != nil else { return }
        switch reply {
        case .playback(let next, let pid): playback = next; self.pid = pid
        case .idle: playback = nil; pid = 0
        case .command(let sent):
            commandFailure = sent ? nil : .commandRejected
            onChange?()
            return
        }
        state = .watching
        onChange?()
    }

    private func fail(_ failure: NowPlayingAdapterReply.Failure) {
        connection?.stop()
        state = .retrying(failure)
        playback = nil
        pid = 0
        onChange?()
    }

    private func ended(_ failure: NowPlayingAdapterReply.Failure, generation requested: UUID, healthy: Bool) {
        guard generation == requested, onChange != nil else { return }
        connection = nil
        termination = nil
        if let terminationMessage { NotificationCenter.default.removeObserver(terminationMessage) }
        terminationMessage = nil
        reader = nil
        if healthy { failures = 0 }
        failures = min(failures + 1, 7)
        let delay = min(60, 1 << (failures - 1))
        fail(failure)
        guard generation == requested, onChange != nil else { return }
        restart = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.generation == requested, self.onChange != nil else { return }
            self.restart = nil
            self.launch()
        }
    }

    private final class Connection: Sendable {
        let output: FileHandle
        private let process: Process
        private let input: FileHandle
        private let exit: ProcessExit
        private let stopped = Mutex(false)

        init(script: URL, library: URL) throws {
            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let descriptor = input.fileHandleForWriting.fileDescriptor
            guard fcntl(descriptor, F_SETNOSIGPIPE, 1) == 0,
                  fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK) == 0 else {
                throw NowPlayingAdapterReply.Failure.unavailable
            }
            process.executableURL = URL(filePath: "/usr/bin/perl")
            process.arguments = [script.path, library.path, "watch"]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            self.process = process
            self.input = input.fileHandleForWriting
            self.output = output.fileHandleForReading
            exit = try process.runObservingExit()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }

        func write(_ data: Data) throws {
            try stopped.withLock { stopped in
                guard !stopped else { throw NowPlayingAdapterReply.Failure.unavailable }
                try input.write(contentsOf: data)
            }
        }

        func stop() {
            let shouldStop = stopped.withLock { stopped in
                guard !stopped else { return false }
                stopped = true
                try? input.close()
                return true
            }
            guard shouldStop else { return }
            if process.isRunning { process.terminate() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [process] in
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }

        func wait() {
            exit.wait()
            try? output.close()
        }
    }
}
