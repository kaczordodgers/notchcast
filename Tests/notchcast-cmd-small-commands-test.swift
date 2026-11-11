// notchcast-sources: Tinycast/Features/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/SmallCommands/Service/*.swift
// notchcast-sources: Tinycast/Features/CopyPath/Model/*.swift
// notchcast-sources: Tinycast/Features/CopyPath/Service/*.swift
// notchcast-kit: host
// notchcast-sources: Tinycast/Features/Notchcast/Model/WebRules.swift
import AppKit
import Synchronization

enum DialogTone {}

@main
struct SmallCommandsTest {
    final class NoiseFake: Sendable {
        struct State {
            var actions: [NoiseControlService.Action] = []
            var mode = NoiseControlEngine.Mode.noiseCancellation
            var now = Duration.zero
            var empty = false
            var cancelOnSnapshot = false
            var expireOnSnapshot = false
            var denyOpen = false
        }
        let state = Mutex(State())

        func perform(_ action: NoiseControlService.Action, deadline: Duration) async throws -> [NoiseControlEngine.Button] {
            try state.withLock { state in
                state.actions.append(action)
                if state.denyOpen { throw NoiseControlService.Failure.needsAccessibility }
                switch action {
                case .snapshot:
                    if state.cancelOnSnapshot { withUnsafeCurrentTask { $0?.cancel() } }
                    if state.expireOnSnapshot { state.now += .seconds(9) }
                    if state.empty { return [] }
                    return NoiseControlEngine.Mode.allCases.map { .init(mode: $0, selected: $0 == state.mode) }
                case .press(let mode): state.mode = mode
                default: break
                }
                return []
            }
        }

        var service: NoiseControlService {
            NoiseControlService(
                perform: { try await self.perform($0, deadline: $1) },
                sleep: { self.state.withLock { $0.now += .milliseconds(50) } },
                now: { self.state.withLock { $0.now } })
        }
    }

    @MainActor
    final class Sharing {
        let service = NSSharingService(title: "Fixture", image: NSImage(), alternateImage: nil) {}
        var onPerform: ((NSSharingService) -> Void)?
    }

    @MainActor
    static func main() async throws {
        try passwords()
        try await shortening()
        try await noise()
        try await airDrop()
        print("Verified cmd-small-commands: unbiased passwords, fake TinyURL, noise timeout/cancellation, AirDrop lifecycle")
    }

    static func passwords() throws {
        let values = [UInt8(0), UInt8(RandomPasswordEngine.letters.count),
                      UInt8(RandomPasswordEngine.letters.count + RandomPasswordEngine.digits.count)]
        let password = try RandomPasswordEngine.make { _ in
            [255] + (0..<24).map { values[$0 % values.count] }
        }
        precondition(password.count == 24 && !password.contains("I"))
        precondition(password.contains(where: RandomPasswordEngine.digits.contains))
        precondition(password.contains(where: RandomPasswordEngine.signs.contains))
        do {
            _ = try RandomPasswordEngine.make { _ in [255] }
            preconditionFailure("Biased bytes accepted")
        } catch RandomPasswordEngine.Failure.entropyUnavailable {}
        do {
            _ = try RandomPasswordEngine.make { _ in [] }
            preconditionFailure("Empty entropy accepted")
        } catch RandomPasswordEngine.Failure.entropyUnavailable {}
        do {
            _ = try RandomPasswordEngine.make { _ in [UInt8](repeating: 0, count: 48) }
            preconditionFailure("Password without digits or symbols accepted")
        } catch RandomPasswordEngine.Failure.entropyUnavailable {}
        let secure = try RandomPasswordService.make()
        precondition(secure.count == 24 && secure.allSatisfy(RandomPasswordEngine.alphabet.contains))
    }

    static func shortening() async throws {
        for host in ["localhost", "127.0.0.1", "10.0.0.1", "172.16.0.1", "172.31.255.255",
                     "192.168.1.1", "169.254.1.2", "[::1]", "[fe80::1]", "[fc00::1]",
                     "[::ffff:192.168.1.1]", "127.1", "2130706433"] {
            do {
                _ = try await ShortenLinkService { _ in preconditionFailure("Private host disclosed: \(host)") }
                    .shorten("http://\(host)/secret")
                preconditionFailure("Private host accepted: \(host)")
            } catch ShortenLinkService.Failure.noLink {}
        }
        precondition(ShortenLinkService.pick(argument: "invalid", frontAddress: "https://example.com", clipboard: nil) == nil)
        precondition(ShortenLinkService.pick(argument: "", frontAddress: nil, clipboard: "Read https://example.com/a") != nil)
        precondition(ShortenLinkService.pick(argument: "example.com", frontAddress: nil, clipboard: nil) != nil)
        precondition(ShortenLinkService.pick(argument: "https://typed.example/path", frontAddress: nil,
            clipboard: "https://clipboard.example") == "https://typed.example/path")
        precondition(ShortenLinkService.pick(argument: " \n", frontAddress: nil,
            clipboard: "https://clipboard.example") == "https://clipboard.example")
        precondition(ShortenLinkService.pick(argument: "invalid", frontAddress: nil,
            clipboard: "https://clipboard.example") == nil)
        precondition(ShortenLinkService.pick(argument: "", frontAddress: nil, clipboard: "invalid") == nil)
        let service = ShortenLinkService { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            precondition(parts.host == "tinyurl.com" && request.timeoutInterval == 10)
            precondition(parts.queryItems == [URLQueryItem(name: "url", value: "https://example.com/?q=a%2Bb#z")])
            return (Data("https://tinyurl.com/example\n".utf8), 200)
        }
        let result = try await service.shorten("https://example.com/?q=a%2Bb&utm_source=x#z")
        precondition(result == "https://tinyurl.com/example")
        for body in ["Error", "<html>Error</html>", "https://evil.example/a", "https://tinyurl.com/"] {
            do {
                _ = try await ShortenLinkService { _ in (Data(body.utf8), 200) }.shorten("https://example.com")
                preconditionFailure("Invalid shortener reply accepted")
            } catch ShortenLinkService.Failure.unavailable {}
        }
        do {
            _ = try await ShortenLinkService { _ in (Data(), 429) }.shorten("https://example.com")
            preconditionFailure("HTTP failure swallowed")
        } catch ShortenLinkService.Failure.unavailable {}
        do {
            _ = try await ShortenLinkService { _ in throw URLError(.timedOut) }.shorten("https://example.com")
            preconditionFailure("Timeout swallowed")
        } catch let error as URLError { precondition(error.code == .timedOut) }
        do {
            _ = try await ShortenLinkService { _ in preconditionFailure("Fetched a non-web address") }
                .shorten("file:///tmp/example")
            preconditionFailure("Non-web address accepted")
        } catch ShortenLinkService.Failure.noLink {}
        let cancelled = Task {
            try await ShortenLinkService { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return (Data("https://tinyurl.com/example".utf8), 200)
            }.shorten("https://example.com")
        }
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled fetch returned a link")
        } catch is CancellationError {}
    }

    static func noise() async throws {
        let fake = NoiseFake()
        let result = try await fake.service.switchMode()
        precondition(result == .switched(.transparency))
        precondition(fake.state.withLock { $0.actions.last } == .close)
        fake.state.withLock { $0.empty = true; $0.actions = [] }
        let timedOut = try await fake.service.switchMode()
        precondition(timedOut == .unchanged || timedOut == .noAirPods)
        precondition(fake.state.withLock { !$0.actions.contains { if case .press = $0 { true } else { false } } })
        let cancelled = NoiseFake()
        cancelled.state.withLock { $0.cancelOnSnapshot = true }
        let task = Task { try await cancelled.service.switchMode() }
        do {
            _ = try await task.value
            preconditionFailure("Cancelled noise press allowed")
        } catch is CancellationError {}
        precondition(cancelled.state.withLock { $0.actions } == [.open, .snapshot, .close])
        let denied = NoiseFake()
        denied.state.withLock { $0.denyOpen = true }
        do {
            _ = try await denied.service.switchMode()
            preconditionFailure("Accessibility refusal swallowed")
        } catch NoiseControlService.Failure.needsAccessibility {}
        precondition(denied.state.withLock { $0.actions } == [.open])
        let expired = NoiseFake()
        expired.state.withLock { $0.expireOnSnapshot = true }
        let unchanged = try await expired.service.switchMode()
        precondition(unchanged == .unchanged)
        precondition(expired.state.withLock { $0.actions } == [.open, .snapshot, .close])
        precondition(NoiseControlEngine.Mode.adaptive.next == .noiseCancellation)
        precondition(NoiseControlEngine.Mode.transparency.next == .noiseCancellation)
    }

    @MainActor
    static func airDrop() async throws {
        let empty = AirDropService(selection: { [] }, makeService: { _ in preconditionFailure("Shared empty selection") })
        let noSelection = try await empty.shareSelection()
        precondition(noSelection == .noSelection)
        let file = URL(filePath: "/tmp/example.txt")
        let sharing = Sharing()
        let driver = AirDropService(
            selection: { [file] }, makeService: { _ in sharing.service },
            perform: { service, _ in sharing.onPerform?(service) }, activate: {})
        sharing.onPerform = { driver.sharingService($0, didShareItems: [file]) }
        let sent = try await driver.shareSelection()
        precondition(sent == .sent(1))
        sharing.onPerform = {
            driver.sharingService($0, didFailToShareItems: [file], error: NSError(domain: NSCocoaErrorDomain,
                                                                             code: NSUserCancelledError))
        }
        let cancelled = try await driver.shareSelection()
        precondition(cancelled == .cancelled)
        sharing.onPerform = { _ in driver.stop() }
        do {
            _ = try await driver.shareSelection()
            preconditionFailure("Stopped share kept waiting")
        } catch is CancellationError {}
        driver.sharingService(sharing.service, didShareItems: [file])
        let started = AsyncStream<Void>.makeStream()
        sharing.onPerform = { _ in started.continuation.yield(()) }
        let pending = Task { try await driver.shareSelection() }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        do {
            _ = try await driver.shareSelection()
            preconditionFailure("Overlapping share accepted")
        } catch AirDropService.Failure.busy {}
        pending.cancel()
        do {
            _ = try await pending.value
            preconditionFailure("Cancelled share kept waiting")
        } catch is CancellationError {}
        started.continuation.finish()
        driver.sharingService(sharing.service, didShareItems: [file])
        let invalid = AirDropService(selection: { [URL(string: "https://example.com")!] }, activate: {})
        do {
            _ = try await invalid.shareSelection()
            preconditionFailure("Non-file shared")
        } catch AirDropService.Failure.invalidSelection {}
        sharing.onPerform = nil
    }
}
