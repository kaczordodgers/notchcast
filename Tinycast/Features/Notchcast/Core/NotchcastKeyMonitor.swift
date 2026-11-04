import AppKit
import Carbon.HIToolbox
import Observation
import Synchronization

@MainActor
final class NotchcastKeyMonitor {
    private struct Routing: Sendable {
        var mute = false
        var media = false
        var replace = false
    }

    private enum Key: Sendable {
        case mute(Bool)
        case media(Int, Bool)
    }

    private final class SharedRouting: Sendable {
        let value = Mutex(Routing())
    }

    private let music: MusicNowPlayingModule
    private let blocker: MusicLaunchBlocker
    private let microphone: MicrophoneMuteModule
    private let preferences: NotchcastPreferences
    private let hub: EventTapHub
    private let routing = SharedRouting()
    private var registration: UUID?
    private var activation: NotificationToken?

    init(music: MusicNowPlayingModule, blocker: MusicLaunchBlocker, microphone: MicrophoneMuteModule,
         preferences: NotchcastPreferences, hub: EventTapHub) {
        self.music = music
        self.blocker = blocker
        self.microphone = microphone
        self.preferences = preferences
        self.hub = hub
        let center = NotificationCenter.default
        activation = NotificationToken(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }, center: center)
    }

    isolated deinit {
        if let registration { hub.remove(registration) }
    }

    func run() {
        withObservationTracking(update) { [weak self] in
            Task { @MainActor [weak self] in self?.run() }
        }
    }

    func update() {
        let mute = preferences.isEnabled(.microphoneMute)
        let media = preferences.isEnabled(.musicLastPlayer) || preferences.isEnabled(.musicBlockAppleMusic)
            || preferences.isEnabled(.spotifyConnect)
        let replacing = preferences.isEnabled(.musicLastPlayer) && music.model.nowPlaying == nil
            && music.model.canResume
        let soloist = preferences.isEnabled(.spotifyConnect)
            && (music.model.nowPlaying?.origin == .soloist || music.soloist.authState?.loggedIn == true)
        routing.value.withLock { $0 = Routing(mute: mute, media: media, replace: replacing || soloist) }
        microphone.model.hotKeyStatus = mute && !AXIsProcessTrusted() ? Int32(AXError.apiDisabled.rawValue) : nil
        if mute || media {
            if registration == nil {
                registration = hub.registerSynchronous(mask: (1 << NSEvent.EventType.systemDefined.rawValue)
                    | EventTapPolicy.mask(for: .keyDown) | EventTapPolicy.mask(for: .keyUp)) { [weak self, routing] type, event in
                    guard let key = Self.decode(type, event) else { return .pass }
                    let state = routing.value.withLock { $0 }
                    let enabled: Bool
                    let swallow: Bool
                    switch key {
                    case .mute: enabled = state.mute; swallow = state.mute
                    case .media: enabled = state.media; swallow = state.media && state.replace
                    }
                    if enabled {
                        DispatchQueue.main.async { [weak self] in self?.perform(key) }
                    }
                    return swallow ? .swallow : .pass
                }
            }
            hub.refreshPermission()
        } else if let registration {
            hub.remove(registration)
            self.registration = nil
        }
    }

    private nonisolated static func decode(_ type: CGEventType, _ event: CGEvent) -> Key? {
        if type == .keyDown || type == .keyUp {
            guard event.getIntegerValueField(.keyboardEventKeycode) == kVK_F5,
                event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift])
            else { return nil }
            return .mute(type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0)
        }
        guard type.rawValue == NSEvent.EventType.systemDefined.rawValue,
            let event = NSEvent(cgEvent: event), event.subtype.rawValue == 8 else { return nil }
        let key = (event.data1 >> 16) & 0xffff
        guard [16, 17, 18].contains(key) else { return nil }
        return .media(key, (event.data1 >> 8) & 0xff == 0x0a)
    }

    private func perform(_ key: Key) {
        switch key {
        case let .mute(down):
            if down, preferences.isEnabled(.microphoneMute) { microphone.toggle() }
        case let .media(code, down):
            guard preferences.isEnabled(.musicLastPlayer) || preferences.isEnabled(.musicBlockAppleMusic)
                || preferences.isEnabled(.spotifyConnect) else { return }
            let command: PlayerCommand = code == 16 ? .togglePlayPause : code == 17 ? .next : .previous
            let mediaKey: MusicLaunchPolicy.MediaKey = code == 16 ? .playPause : code == 17 ? .next : .previous
            if down {
                blocker.noteMediaKey(mediaKey)
                if routing.value.withLock({ $0.replace }) { music.send(command) }
            }
        }
    }
}
