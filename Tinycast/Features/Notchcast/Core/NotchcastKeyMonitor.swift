import AppKit
import Carbon.HIToolbox
import Observation
import OSLog

@MainActor
final class NotchcastKeyMonitor {
    private let music: MusicNowPlayingModule
    private let blocker: MusicLaunchBlocker
    private let microphone: MicrophoneMuteModule
    private let preferences: NotchcastPreferences
    private static let muteSignature: OSType = 0x4E43_4D49
    private var muteKey: EventHotKeyRef?
    private var keyHandler: EventHandlerRef?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var muteRegistered = false
    private var retry: Task<Void, Never>?
    private var activation: NotificationToken?

    init(music: MusicNowPlayingModule, blocker: MusicLaunchBlocker, microphone: MicrophoneMuteModule,
         preferences: NotchcastPreferences) {
        self.music = music
        self.blocker = blocker
        self.microphone = microphone
        self.preferences = preferences
        let center = NotificationCenter.default
        activation = NotificationToken(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }, center: center)
    }

    isolated deinit {
        retry?.cancel()
        stopTap()
        unregisterMute()
    }

    func run() {
        if retry == nil {
            retry = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    self?.update()
                }
            }
        }
        withObservationTracking(update) { [weak self] in
            Task { @MainActor [weak self] in self?.run() }
        }
    }

    func update() {
        let mute = preferences.isEnabled(.microphoneMute)
        if mute != muteRegistered {
            if mute {
                registerMute()
                muteRegistered = muteKey != nil
            } else {
                unregisterMute()
                muteRegistered = false
                microphone.model.hotKeyStatus = nil
            }
        }
        let media = preferences.isEnabled(.musicLastPlayer) || preferences.isEnabled(.musicBlockAppleMusic)
        if media { startTap() } else { stopTap() }
    }

    private func registerMute() {
        microphone.model.hotKeyStatus = nil
        unregisterMute()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetEventDispatcherTarget(), { @MainActor _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                                               nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr, identifier.signature == NotchcastKeyMonitor.muteSignature, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                let monitor = Unmanaged<NotchcastKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                guard monitor.preferences.isEnabled(.microphoneMute) else { return OSStatus(eventNotHandledErr) }
                monitor.microphone.toggle()
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &keyHandler)
        guard installed == noErr else {
            reportRegistration(installed)
            return
        }
        let registered = RegisterEventHotKey(UInt32(kVK_F5), 0,
            EventHotKeyID(signature: Self.muteSignature, id: 1), GetEventDispatcherTarget(), 0, &muteKey)
        if registered != noErr {
            unregisterMute()
            reportRegistration(registered)
        }
    }

    private func unregisterMute() {
        if let muteKey { UnregisterEventHotKey(muteKey) }
        muteKey = nil
        if let keyHandler { RemoveEventHandler(keyHandler) }
        keyHandler = nil
    }

    private func reportRegistration(_ status: OSStatus) {
        microphone.model.hotKeyStatus = status
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast.dev", category: "Microphone")
            .error("Could not register F5 (OSStatus \(status))")
    }

    private func startTap() {
        guard tap == nil else { return }
        tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: 1 << NSEvent.EventType.systemDefined.rawValue,
            callback: { @MainActor _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<NotchcastKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return monitor.handle(event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else { return }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    private func stopTap() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
    }

    func handle(_ event: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: event), event.subtype.rawValue == 8 else { return false }
        let key = (event.data1 >> 16) & 0xffff
        let down = (event.data1 >> 8) & 0xff == 0x0a
        let command: PlayerCommand
        let mediaKey: MusicLaunchPolicy.MediaKey
        switch key {
        case 16: command = .togglePlayPause; mediaKey = .playPause
        case 17: command = .next; mediaKey = .next
        case 18: command = .previous; mediaKey = .previous
        default: return false
        }
        let replacing = preferences.isEnabled(.musicLastPlayer) && music.model.nowPlaying == nil
            && music.model.canResume
        let soloist = preferences.isEnabled(.spotifyConnect)
            && (music.model.nowPlaying?.origin == .soloist || music.soloist.authState?.loggedIn == true)
        if down {
            blocker.noteMediaKey(mediaKey)
            if replacing || soloist { music.send(command) }
        }
        return replacing || soloist
    }
}
