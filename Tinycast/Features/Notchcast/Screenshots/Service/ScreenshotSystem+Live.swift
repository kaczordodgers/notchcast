// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's capture engine: excluded windows left out, windows front to back.
// The scrolling region adapted from Vorssaint faada18d's capture engine and recorder filter.

import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

extension ScreenshotSystem {
    static let live = ScreenshotSystem(
        grantAccess: { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() },
        freeze: { point, exclusion in
            try await freezeDisplays(under: point, excluding: exclusion, captureUI: captureUIWindowIDs())
        },
        windows: windowsFrontToBack,
        freezeWindows: { ids in try await freezeWindows(ids) },
        cursor: { CGEvent(source: nil)?.location ?? .zero },
        writeClipboard: { data in
            let item = NSPasteboardItem()
            guard item.setData(data, forType: .png) else { return false }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([item])
        },
        writeText: { text in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        },
        recognizeText: { image in
            try await ScreenTextRecognizer.lines(in: image, preferredLanguages: Locale.preferredLanguages)
        },
        warmTextRecognition: { await ScreenTextRecognizer.warmUp(preferredLanguages: Locale.preferredLanguages) },
        openScreenRecordingSettings: {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            else { return }
            NSWorkspace.shared.open(url)
        },
        downloads: {
            try FileManager.default.url(
                for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        },
        chooseSaveFile: { name in
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            // The editor floats; a panel at the normal level would open behind it.
            panel.level = .modalPanel
            NSApp.activate()
            return panel.runModal() == .OK ? panel.url : nil
        },
        select: { frozen, windows, completion in
            let surface = ScreenshotSelectionSurface(frozen: frozen, windows: windows, completion: completion)
            return { surface.finish(nil) }
        },
        edit: { image, scale, finish in CaptureEditorPanel.open(image, scale: scale, finish: finish) },
        openRegion: { region in try await openRegion(region) },
        uptime: { ProcessInfo.processInfo.systemUptime },
        pause: { seconds in try await Task.sleep(for: .seconds(seconds)) },
        showGuide: { region in
            let guide = ScrollingCaptureGuide(region)
            return { guide.close() }
        }
    )

    private static var configuration: SCScreenshotConfiguration {
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.dynamicRange = .sdr
        return configuration
    }

    @concurrent
    private static func freezeDisplays(
        under point: CGPoint?, excluding exclusion: ScreenshotExclusion, captureUI: Set<UInt32>
    ) async throws -> [ScreenshotFrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let unshared = unsharedWindowIDs()
        let own = content.windows.filter {
            exclusion.excludes(ScreenshotWindow(
                id: $0.windowID, ownerPID: $0.owningApplication?.processID ?? 0,
                bundleID: $0.owningApplication?.bundleIdentifier, frame: $0.frame, layer: $0.windowLayer,
                isShared: !unshared.contains($0.windowID), isCaptureUI: captureUI.contains($0.windowID)))
        }
        var frozen: [ScreenshotFrozenDisplay] = []
        for display in content.displays where point.map(display.frame.contains) ?? true {
            try Task.checkCancellation()
            let output = try await SCScreenshotManager.captureScreenshot(
                contentFilter: SCContentFilter(display: display, excludingWindows: own), configuration: configuration)
            guard let image = output.sdrImage else { throw ScreenshotRequest.Failure.encodingFailed }
            frozen.append(ScreenshotFrozenDisplay(id: display.displayID, frame: display.frame, image: image))
        }
        return frozen
    }

    @concurrent
    private static func freezeWindows(_ ids: [UInt32]) async throws -> [UInt32: CGImage] {
        let wanted = Set(ids)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var images: [UInt32: CGImage] = [:]
        for window in content.windows where wanted.contains(window.windowID) {
            try Task.checkCancellation()
            let output = try? await SCScreenshotManager.captureScreenshot(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
            images[window.windowID] = output?.sdrImage
        }
        return images
    }

    /// Built once per run, since resolving windows per frame loses the overlap; all of our app stays out.
    @concurrent
    private static func openRegion(_ region: ScrollingCaptureRegion) async throws -> ScreenshotRegionSource {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw ScreenshotRequest.Failure.targetUnavailable
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == pid }
        guard let app = content.applications.first(where: { $0.processID == pid })
            ?? ownWindows.compactMap(\.owningApplication).first else {
            throw ScreenshotRequest.Failure.targetUnavailable
        }
        let filter = SCContentFilter(display: display, excludingApplications: [app], exceptingWindows: [])
        let configuration = configuration
        configuration.sourceRect = region.rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        configuration.width = Int((region.rect.width * region.scale).rounded())
        configuration.height = Int((region.rect.height * region.scale).rounded())
        let capture = RegionCapture(filter: filter, configuration: configuration)
        return ScreenshotRegionSource { await capture.image() }
    }

    @MainActor private static func captureUIWindowIDs() -> Set<UInt32> {
        Set(NSApp.windows.compactMap {
            $0 is ScreenshotSelectionPanel || $0 is ScrollingCaptureGuidePanel ? UInt32($0.windowNumber) : nil
        })
    }

    /// Read from WindowServer, because AppKit's getter can keep answering none after a change.
    private static func unsharedWindowIDs() -> Set<UInt32> {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return Set((info as? [[String: Any]] ?? []).compactMap { entry in
            let sharing = (entry[kCGWindowSharingState as String] as? NSNumber)?.uint32Value
            guard sharing == CGWindowSharingType.none.rawValue else { return nil }
            return (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        })
    }

    @MainActor private static func windowsFrontToBack() -> [ScreenshotWindow] {
        let captureUI = captureUIWindowIDs()
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return (info as? [[String: Any]] ?? []).compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            let sharing = (entry[kCGWindowSharingState as String] as? NSNumber)?.uint32Value
            return ScreenshotWindow(id: id, ownerPID: pid, frame: frame, layer: layer,
                                    alpha: entry[kCGWindowAlpha as String] as? Double ?? 1,
                                    isShared: sharing != CGWindowSharingType.none.rawValue,
                                    isCaptureUI: captureUI.contains(id))
        }
    }
}

/// `SCContentFilter` is not marked Sendable, but nothing changes it after it is built.
private final class RegionCapture: @unchecked Sendable {
    private let filter: SCContentFilter
    private let configuration: SCScreenshotConfiguration

    init(filter: SCContentFilter, configuration: SCScreenshotConfiguration) {
        self.filter = filter
        self.configuration = configuration
    }

    /// Nil when this frame failed; the run then keeps what it joined so far.
    @concurrent
    func image() async -> CGImage? {
        try? await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration).sdrImage
    }
}
