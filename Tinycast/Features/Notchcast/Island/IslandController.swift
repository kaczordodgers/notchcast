import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class IslandController: NotchcastModule {
    struct ClosedContent {
        var leading: AnyView?
        var trailing: AnyView?
    }

    static let shared = IslandController()

    private(set) var isOpen = false
    var isPinned = false
    private(set) var page = "home"
    var openContent = AnyView(Color.clear.frame(height: NotchcastTheme.estimatedContentHeight)) {
        didSet { updateContent() }
    }
    var closedContent = ClosedContent() {
        didSet { updateContent() }
    }

    @ObservationIgnored private var panels: [IslandPanel] = []
    @ObservationIgnored private weak var openPanel: IslandPanel?
    @ObservationIgnored private var screenObservation: NotificationToken?
    @ObservationIgnored private var mouseMonitors: [Any] = []
    @ObservationIgnored private var observationID: UUID?

    func start() {
        guard observationID == nil else { return }
        let identity = UUID()
        observationID = identity
        let center = NotificationCenter.default
        screenObservation = NotificationToken(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, observationID == identity else { return }
                rebuildPanels()
            }
        }, center: center)
        watchPointer()
        rebuildPanels()
        observePreferences(identity: identity)
    }

    func stop() {
        observationID = nil
        screenObservation = nil
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors.removeAll()
        panels.forEach { $0.close() }
        panels.removeAll()
        isOpen = false
        isPinned = false
    }

    func open(page: String, on screen: NSScreen? = nil, takeKey: Bool = false) {
        guard observationID != nil else { return }
        let frames = panels.map(\.displayFrame)
        let point = screen.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSEvent.mouseLocation
        guard let index = IslandGeometry.screenIndex(containing: point, frames: frames),
              panels[index].isVisible else { return }
        if openPanel !== panels[index] { openPanel?.setOpen(false, animated: true) }
        openPanel = panels[index]
        self.page = page
        isOpen = true
        openPanel?.setOpen(true, animated: true)
        if takeKey { openPanel?.makeKey() }
    }

    func close() {
        isOpen = false
        isPinned = false
        openPanel?.setOpen(false, animated: true)
        openPanel = nil
    }

    func toggle() {
        if isOpen { close() } else { open(page: page, takeKey: true) }
    }

    private func rebuildPanels() {
        let previousFrame = openPanel?.displayFrame
        panels.forEach { $0.close() }
        openPanel = nil
        panels = NSScreen.screens.map(IslandPanel.init(screen:))
        updateContent()
        applyPreferences()
        if isOpen, let panel = panels.first(where: { $0.displayFrame == previousFrame && $0.isVisible }) {
            openPanel = panel
            panel.setOpen(true, animated: false)
        } else { close() }
    }

    private func updateContent() {
        panels.forEach { $0.setContent(open: openContent, closed: closedContent) }
    }

    private func applyPreferences() {
        let preferences = NotchcastPreferences.shared
        let externalDisplays = preferences.isOn(.islandExternalDisplays)
        let fullScreen = preferences.isOn(.islandFullScreen)
        for panel in panels {
            panel.setFullScreenEnabled(fullScreen)
            if panel.hardwareNotch != nil || externalDisplays {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
            panel.updateMousePassthrough()
        }
    }

    private func observePreferences(identity: UUID) {
        withObservationTracking {
            applyPreferences()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, observationID == identity else { return }
                observePreferences(identity: identity)
            }
        }
    }

    private func watchPointer() {
        // The global pointer monitor is the deliberate M0 hook for island hit-region tracking.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                             .otherMouseDragged, .leftMouseDown, .rightMouseDown,
                                             .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.panels.forEach { $0.updateMousePassthrough() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.panels.forEach { $0.updateMousePassthrough() }
            return event
        }
        mouseMonitors = [global, local].compactMap { $0 }
    }
}
