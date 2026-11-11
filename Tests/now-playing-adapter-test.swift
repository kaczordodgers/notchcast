// notchcast-sources: -parse-as-library Tinycast/Features/Music/Model/NowPlaying.swift
// notchcast-sources: Tinycast/Features/Music/Model/NowPlayingAdapterReply.swift
// notchcast-sources: Tinycast/Features/Music/Model/NowPlayingAdapterWire.swift
// notchcast-sources: Tinycast/Features/Music/Service/SystemNowPlayingSource.swift
// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-kit: platform
import Foundation

@main
struct NowPlayingAdapterTests {
    static func expect(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func data(_ reply: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: reply, options: .withoutEscapingSlashes)
    }

    static func playback(_ reply: [String: Any], previous: NowPlaying? = nil) throws -> NowPlaying? {
        let result = try NowPlayingAdapterReply.parse(data(reply), previous: previous, now: Date(timeIntervalSince1970: 123))
        guard case .playback(let track, _) = result else { return nil }
        return track
    }

    static func parsing() throws {
        let prefix = "kMRMediaRemoteNowPlayingInfo"
        let reply: [String: Any] = [
            prefix + "Title": "Song", prefix + "Artist": "Artist", prefix + "Album": "Album",
            prefix + "Duration": 120, prefix + "ElapsedTime": 30, prefix + "PlaybackRate": 1,
            "isPlaying": true, "displayID": "test.player", "displayName": "Player", "pid": 42,
            "artworkBase64": Data([1, 2, 3]).base64EncodedString()
        ]
        guard let song = try playback(reply) else { fatalError("Missing playback") }
        expect(song.title == "Song" && song.artist == "Artist" && song.album == "Album", "Metadata")
        expect(song.app == "Player" && song.bundleID == "test.player" && song.origin == .system, "Identity")
        expect(song.duration == 120 && song.elapsed == 30 && song.isPlaying, "Position")
        expect(song.stamp == Date(timeIntervalSince1970: 123), "Injected clock")
        expect(song.artwork == Data([1, 2, 3]), "Artwork")
        var paused = reply
        paused["isPlaying"] = false
        expect(try playback(paused)?.isPlaying == false, "Playing state overrides stale rate")

        let underscored: [String: Any] = ["_" + prefix + "Title": "Renamed", "_" + prefix + "PlaybackRate": 1]
        expect(try playback(underscored)?.title == "Renamed", "Underscore-renamed metadata key")
        expect(try playback(underscored)?.isPlaying == true, "Underscore-renamed playback rate")
        guard let minimal = try playback([prefix + "Title": "Minimal"]) else { fatalError("Missing minimal track") }
        expect(minimal.artist.isEmpty && minimal.album.isEmpty && minimal.app.isEmpty, "Missing strings")
        expect(minimal.duration == 0 && minimal.elapsed == 0 && !minimal.isPlaying, "Missing numbers")
        expect(minimal.artwork == nil && minimal.bundleID == nil, "Missing optional fields")
        expect(try playback([:]) == nil, "Empty reply is idle")
        expect(try playback([prefix + "Title": " \n\t"]) == nil, "Blank title is idle")

        var unusual = reply
        unusual[prefix + "ElapsedTime"] = -50
        unusual[prefix + "Duration"] = -10
        unusual["isPlaying"] = "true"
        expect(try playback(unusual)?.elapsed == 0, "Negative elapsed is clamped")
        expect(try playback(unusual)?.duration == 0, "Negative duration is clamped")
        unusual[prefix + "ElapsedTime"] = 500
        unusual[prefix + "Duration"] = 120
        expect(try playback(unusual)?.elapsed == 120, "Position cannot exceed duration")
        unusual[prefix + "Duration"] = true
        unusual[prefix + "PlaybackRate"] = true
        expect(try playback(unusual)?.duration == 0, "Boolean is not a duration")
        expect(try playback(unusual)?.isPlaying == false, "Boolean is not a rate")

        var unchanged = reply
        unchanged["artworkBase64"] = nil
        unchanged["artworkUnchanged"] = true
        expect(try playback(unchanged, previous: song)?.artwork == song.artwork, "Same-track artwork reuse")
        var changed = unchanged
        changed["artworkUnchanged"] = nil
        changed["artworkBase64"] = Data([4, 5, 6]).base64EncodedString()
        expect(try playback(changed, previous: song)?.artwork == Data([4, 5, 6]), "Changed artwork replaces cache")
        changed["artworkBase64"] = nil
        expect(try playback(changed, previous: song)?.artwork == nil, "Removed artwork clears cache")
        unchanged[prefix + "Title"] = "New song"
        expect(try playback(unchanged, previous: song)?.artwork == nil, "Artwork cannot leak between tracks")
        unchanged[prefix + "Title"] = "Song"
        unchanged["displayID"] = "another.player"
        expect(try playback(unchanged, previous: song)?.artwork == nil, "Artwork cannot leak between players")

        var cover = reply
        cover["artworkBase64"] = ""
        expect(try playback(cover)?.artwork == nil, "Empty artwork")
        cover["artworkBase64"] = "not base64"
        expect(try playback(cover)?.artwork == nil, "Invalid artwork")
        cover["artworkBase64"] = Data(repeating: 0, count: NowPlayingAdapterWire.maximumArtworkBytes + 1).base64EncodedString()
        expect(try playback(cover)?.artwork == nil, "Oversized decoded artwork")
        cover["artworkBase64"] = String(repeating: "A", count: 4 * (NowPlayingAdapterWire.maximumArtworkBytes / 3) + 4)
        expect(try playback(cover)?.artwork == nil, "Oversized encoded artwork")
        cover["artworkBase64"] = Data(repeating: 1, count: NowPlayingAdapterWire.maximumArtworkBytes).base64EncodedString()
        expect(try playback(cover)?.artwork?.count == NowPlayingAdapterWire.maximumArtworkBytes, "Artwork cap boundary")
        cover["artworkBase64"] = Data(repeating: 255, count: NowPlayingAdapterWire.maximumArtworkBytes).base64EncodedString()
        let nearCap = try data(cover)
        expect(nearCap.count <= NowPlayingAdapterReply.maximumLineBytes, "Slash-heavy artwork fits line cap")
        var artworkLines = NowPlayingAdapterReply.Lines()
        expect(try artworkLines.append(nearCap + Data([10])) == [nearCap], "Near-cap artwork is framed")
        expect(try playback(cover)?.artwork?.count == NowPlayingAdapterWire.maximumArtworkBytes,
               "Slash-heavy artwork survives parsing")

        expect(try NowPlayingAdapterReply.parse(data(["sent": true]), previous: song, now: .distantPast) == .command(true),
               "Command acknowledgment is separate from playback")
        for (bytes, expected) in [
            (Data("[]".utf8), NowPlayingAdapterReply.Failure.invalidReply),
            (Data("broken".utf8), .invalidReply),
            (try data(["error": "metadata timeout"]), .unavailable),
            (Data(repeating: 32, count: NowPlayingAdapterReply.maximumLineBytes + 1), .oversizedReply)
        ] {
            do {
                _ = try NowPlayingAdapterReply.parse(bytes, previous: nil, now: .distantPast)
                fatalError("Expected \(expected)")
            } catch let failure as NowPlayingAdapterReply.Failure {
                expect(failure == expected, "Typed parser failure")
            }
        }

        var lines = NowPlayingAdapterReply.Lines()
        let unicode = Data("{\"title\":\"音楽\"}\n{\"sent\":true}\n".utf8)
        var framed: [Data] = []
        for byte in unicode { framed += try lines.append(Data([byte])) }
        expect(framed.count == 2 && String(data: framed[0], encoding: .utf8)?.contains("音楽") == true, "Split UTF-8")
        expect(try lines.append(Data("a\nb\npartial".utf8)) == [Data("a".utf8), Data("b".utf8)], "Batched lines")
        expect(try lines.append(Data("\n".utf8)) == [Data("partial".utf8)], "Partial tail")
        do {
            _ = try lines.append(Data(repeating: 1, count: NowPlayingAdapterReply.maximumLineBytes + 1))
            fatalError("Expected bounded pipe")
        } catch NowPlayingAdapterReply.Failure.oversizedReply {}
        print("PASS reply parsing: renamed keys, missing fields, artwork cap, framing and typed failures")
    }

    @MainActor
    static func waitFor(line: UInt = #line, _ predicate: @MainActor () async throws -> Bool) async throws {
        for _ in 0..<300 {
            if try await predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        fatalError("Timed out waiting for source at line \(line)")
    }

    @MainActor
    static func lifecycle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "now-playing-\(UUID()).bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appending(path: "Contents/Resources")
        let frameworks = root.appending(path: "Contents/Helpers")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": "test.now-playing", "CFBundlePackageType": "BNDL"],
            format: .xml, options: 0
        )
        try plist.write(to: root.appending(path: "Contents/Info.plist"))
        try Data().write(to: frameworks.appending(path: "libNowPlayingAdapter.dylib"))
        let commands = resources.appending(path: "commands")
        let launches = resources.appending(path: "launches")
        let script = """
        use strict;
        use warnings;
        use JSON::PP;
        $| = 1;
        open(my $launches, '>>', '\(launches.path)') or die $!;
        print $launches "$$\\n";
        close($launches);
        print encode_json({kMRMediaRemoteNowPlayingInfoTitle => 'Fixture', isPlaying => JSON::PP::true, pid => $$}), "\\n";
        while (my $line = <STDIN>) {
            open(my $commands, '>>', '\(commands.path)') or die $!;
            print $commands $line;
            close($commands);
            my $reply = decode_json($line);
            if ($reply->{command} eq 'next') { exit 1; }
            if ($reply->{command} eq 'seek' && $reply->{position} == 999) {
                print "{\\"sent\\":false}\\n";
                next;
            }
            print "{\\"sent\\":true}\\n";
        }
        """
        try script.write(to: resources.appending(path: "now-playing.pl"), atomically: true, encoding: .utf8)
        guard let bundle = Bundle(url: root) else { fatalError("Fixture bundle") }
        let source = SystemNowPlayingSource(bundle: bundle)
        var changes = 0
        source.watch { changes += 1 }
        expect(try await source.read() == nil, "Starting source is idle")
        try await waitFor { source.state == .watching }
        expect(try await source.read()?.title == "Fixture", "Source reads helper metadata")
        source.send(.play)
        source.send(.pause)
        source.send(.togglePlayPause)
        source.send(.previous)
        source.send(.seek(12.5))
        source.send(.volume(0.5))
        source.send(.seek(.nan))
        try await waitFor {
            guard let text = try? String(contentsOf: commands, encoding: .utf8) else { return false }
            return text.split(separator: "\n").count == 5
        }
        let messages = try String(contentsOf: commands, encoding: .utf8).split(separator: "\n").map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] ?? [:]
        }
        expect(messages.compactMap { $0["command"] as? String } == ["play", "pause", "toggle", "previous", "seek"],
               "Commands retain order; volume and invalid seek are ignored")
        expect(messages.last?["position"] as? Double == 12.5, "Seek position")
        source.send(.seek(999))
        try await waitFor { source.commandFailure == .commandRejected }
        expect(source.state == .watching, "Rejected command preserves the watch")
        expect(try await source.read()?.title == "Fixture", "Rejected command preserves playback")
        source.send(.next)
        try await waitFor {
            let count = (try? String(contentsOf: launches, encoding: .utf8).split(separator: "\n").count) ?? 0
            return count >= 2 && source.state == .watching
        }
        expect(changes >= 3, "Exit and restart notify observers")
        source.unwatch()
        let oldChanges = changes
        try await Task.sleep(for: .milliseconds(150))
        expect(source.state == .stopped && changes == oldChanges, "Unwatch rejects stale callbacks")
        source.watch { changes += 1 }
        source.unwatch()
        source.watch { changes += 1 }
        try await waitFor { source.state == .watching }
        source.unwatch()
        try await Task.sleep(for: .milliseconds(150))
        let childPIDs = try String(contentsOf: launches, encoding: .utf8).split(separator: "\n").compactMap { Int32($0) }
        try await waitFor { childPIDs.allSatisfy { kill($0, 0) != 0 } }
        source.watch { changes += 1 }
        try await waitFor { source.state == .watching }
        source.send(.next)
        try await waitFor {
            if case .retrying = source.state { return true }
            return false
        }
        source.unwatch()
        let launchesBefore = try String(contentsOf: launches, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(1_200))
        expect(try String(contentsOf: launches, encoding: .utf8) == launchesBefore, "Unwatch cancels pending restart")
        try FileManager.default.removeItem(at: frameworks.appending(path: "libNowPlayingAdapter.dylib"))
        source.watch { changes += 1 }
        expect(source.state == .retrying(.unavailable), "Missing bundled helper has a typed failure")
        do {
            _ = try await source.read()
            fatalError("Expected unavailable source")
        } catch NowPlayingAdapterReply.Failure.unavailable {}
        source.unwatch()
        print("PASS source lifecycle: commands, crash restart, unwatch and immediate rewatch")
    }

    static func main() async throws {
        try parsing()
        try await lifecycle()
        print("✓ now-playing-adapter-test passed")
    }
}
