// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's capture region guide: a click-through outline over the chosen area.

import AppKit
import SwiftUI

/// The scrolled area, outlined over its display for the whole run; clicks and scrolls pass through it.
@MainActor
final class ScrollingCaptureGuide {
    private var panel: ScrollingCaptureGuidePanel?

    init(_ region: ScrollingCaptureRegion) {
        let display = CGDisplayBounds(region.displayID)
        guard let primaryHeight = NSScreen.primary?.frame.height, !display.isEmpty else { return }
        let panel = ScrollingCaptureGuidePanel(
            frame: ScreenshotGeometry.cocoaRect(fromQuartz: display, primaryHeight: primaryHeight))
        panel.contentView = NSHostingView(rootView: ScrollingCaptureGuideView(
            area: region.rect.offsetBy(dx: -display.minX, dy: -display.minY)))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Never key and never hit: the page under it keeps every event while it is scrolled.
final class ScrollingCaptureGuidePanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                   defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isRestorable = false
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
}

/// The selection overlay's two tokens: the display dimmed outside the area, a hairline around it.
struct ScrollingCaptureGuideView: View {
    let area: CGRect

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    path.addRect(area)
                }
                .fill(Theme.Colors.dialogDimming, style: FillStyle(eoFill: true))
                Path(area).stroke(Theme.Colors.dropTarget, lineWidth: Theme.Size.hairline)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
